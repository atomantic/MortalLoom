import Foundation
import UserNotifications
import os

private let notificationLogger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "Notifications")

// MARK: - NotificationService

/// Thin wrapper around UNUserNotificationCenter for MortalLoom's two
/// notification types:
///
/// 1. **Weekly review reminder** — a single repeating local notification
///    scheduled for the user's chosen weekday/time. Fires every 7 days.
/// 2. **Stagnation alerts** — one-shot notifications scheduled when a
///    stagnation signal fires for the first time. Each alert is scoped to a
///    specific goal; rescheduling is idempotent via signal title.
///
/// All notifications are local (no server). The service respects the user's
/// opt-in state via UserDefaults keys so toggling Settings off stops both
/// types immediately.
@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    /// Identifiers of the most recent signal set we reconciled against.
    /// Used to short-circuit reconcileStagnationAlerts when called
    /// repeatedly with the same input (Overview's recalculate fires every
    /// data-sync, even when nothing goal-related changed).
    private var lastReconciledSet: Set<String> = []

    // MARK: Keys

    static let weeklyReviewEnabledKey = "notifications.weeklyReviewEnabled"
    static let weeklyReviewWeekdayKey = "notifications.weeklyReviewWeekday"  // 1=Sun ... 7=Sat
    static let weeklyReviewHourKey = "notifications.weeklyReviewHour"        // 0–23
    static let stagnationAlertsEnabledKey = "notifications.stagnationAlertsEnabled"

    static let weeklyReviewIdentifier = "mortalloom.weekly-review"
    static let stagnationPrefix = "mortalloom.stagnation."

    // MARK: Authorization

    /// Request notification permission. Returns true if the user granted
    /// authorization (or had already granted). Safe to call repeatedly —
    /// iOS will only show the system prompt once.
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationLogger.info("🔔 auth granted: \(granted, privacy: .public)")
            return granted
        } catch {
            notificationLogger.error("🔔 auth error: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    /// True if the user currently has authorization (checked via the system).
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // MARK: Weekly review

    /// Schedule the repeating weekly-review reminder at the configured
    /// weekday + hour. Replaces any existing reminder so settings changes
    /// take effect immediately. No-op if the user has opted out.
    func scheduleWeeklyReviewReminder() async {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: Self.weeklyReviewEnabledKey)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.weeklyReviewIdentifier])
        guard enabled else { return }

        // Defaults: Sunday at 6pm.
        let weekday = defaults.object(forKey: Self.weeklyReviewWeekdayKey) as? Int ?? 1
        let hour = defaults.object(forKey: Self.weeklyReviewHourKey) as? Int ?? 18

        let content = UNMutableNotificationContent()
        content.title = "Weekly Review"
        content.body = "5 minutes to reset alignment and plan the week."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.weeklyReviewIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            notificationLogger.info("🔔 scheduled weekly review for weekday=\(weekday), hour=\(hour)")
        } catch {
            notificationLogger.error("🔔 failed to schedule weekly review: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Convenience to toggle weekly-review reminders on/off. Persists the
    /// choice and re-schedules (or clears) in one call.
    func setWeeklyReviewEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.weeklyReviewEnabledKey)
        if enabled {
            _ = await requestAuthorization()
        }
        await scheduleWeeklyReviewReminder()
    }

    // MARK: Stagnation alerts

    /// Reconcile stagnation notifications. For each currently-firing signal
    /// with a goalId, ensure a pending notification exists (one per unique
    /// goalId+title pair). Cancels any pending notifications whose signals
    /// are no longer firing (the user fixed the problem or muted it).
    ///
    /// Called after any goal/habit state change that might affect signals.
    /// Idempotent — safe to call repeatedly.
    func reconcileStagnationAlerts(_ signals: [StagnationSignal]) async {
        let enabled = UserDefaults.standard.bool(forKey: Self.stagnationAlertsEnabledKey)
        let center = UNUserNotificationCenter.current()

        let activeSignals = signals.filter { $0.goalId != nil }
        let activeIds = Set(activeSignals.map { Self.identifier(for: $0) })

        // Short-circuit when the caller keeps passing the same signal set
        // (e.g. Overview.recalculate firing on non-goal data-sync events).
        // Still honour the enabled toggle — if the user just flipped it,
        // we want to reconcile even with an unchanged set.
        if enabled && activeIds == lastReconciledSet { return }

        // Pull the current pending set so we know what to prune.
        let existing = await center.pendingNotificationRequests()
        let existingStagnationIds = existing
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.stagnationPrefix) }

        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: existingStagnationIds)
            lastReconciledSet = []
            return
        }

        // Cancel stagnation notifications whose signals no longer fire.
        let stale = existingStagnationIds.filter { !activeIds.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        // Schedule any new ones that don't already have a pending request.
        let existingSet = Set(existingStagnationIds)
        for signal in activeSignals {
            let id = Self.identifier(for: signal)
            guard !existingSet.contains(id) else { continue }
            await scheduleStagnationAlert(signal, id: id)
        }
        lastReconciledSet = activeIds
    }

    private func scheduleStagnationAlert(_ signal: StagnationSignal, id: String) async {
        let content = UNMutableNotificationContent()
        content.title = signal.title
        content.body = signal.detail
        content.sound = .default
        content.subtitle = signal.suggestedPrompt

        // Fire once 15 minutes from now so we don't blast the user
        // immediately on app launch. Rescheduling is debounced by the
        // existing-id check in reconcileStagnationAlerts.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 900, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            notificationLogger.error("🔔 failed to schedule stagnation alert: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Convenience to toggle stagnation alerts on/off and clear pending
    /// ones when disabling.
    func setStagnationAlertsEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.stagnationAlertsEnabledKey)
        if enabled {
            _ = await requestAuthorization()
        } else {
            let center = UNUserNotificationCenter.current()
            let existing = await center.pendingNotificationRequests()
            let ids = existing.map(\.identifier).filter { $0.hasPrefix(Self.stagnationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: Identifier helpers

    /// Stable per-signal identifier so reconciliation is idempotent.
    /// Uses goalId + a title hash so the same underlying stagnation signal
    /// always maps to the same notification.
    private static func identifier(for signal: StagnationSignal) -> String {
        let goalSegment = signal.goalId?.uuidString ?? "global"
        // Simple hash: title's string hash isn't stable across runs, so
        // use a deterministic conversion instead.
        let titleKey = signal.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0 == "-" }
        return "\(stagnationPrefix)\(goalSegment).\(titleKey)"
    }
}
