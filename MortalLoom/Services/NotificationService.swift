import Foundation
import UserNotifications
import os

private let notificationLogger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "Notifications")

// MARK: - NotificationService

/// Thin wrapper around UNUserNotificationCenter for MortalLoom's notification
/// types:
///
/// 1. **Reflection-cadence reminders** — a plan of up to three repeating
///    local notifications (daily nudge, weekly review, monthly rethink), each
///    scheduled for the user's chosen time via `scheduleReflectionPlan`. Only
///    the weekly review is default-on; daily and monthly are opt-in.
/// 2. **Stagnation alerts** — one-shot notifications scheduled when a
///    stagnation signal fires for the first time. Each alert is scoped to a
///    specific goal; rescheduling is idempotent via signal title.
///
/// All notifications are local (no server). The service respects the user's
/// opt-in state via UserDefaults keys so toggling Settings off stops the
/// affected reminders immediately.
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

    // Daily nudge — a once-a-day reflection prompt at the chosen hour.
    static let dailyNudgeEnabledKey = "notifications.dailyNudgeEnabled"
    static let dailyNudgeHourKey = "notifications.dailyNudgeHour"            // 0–23

    static let weeklyReviewEnabledKey = "notifications.weeklyReviewEnabled"
    static let weeklyReviewWeekdayKey = "notifications.weeklyReviewWeekday"  // 1=Sun ... 7=Sat
    static let weeklyReviewHourKey = "notifications.weeklyReviewHour"        // 0–23

    // Monthly rethink — a once-a-month prompt on the chosen day-of-month.
    static let monthlyRethinkEnabledKey = "notifications.monthlyRethinkEnabled"
    static let monthlyRethinkDayKey = "notifications.monthlyRethinkDay"      // 1–28
    static let monthlyRethinkHourKey = "notifications.monthlyRethinkHour"    // 0–23

    static let stagnationAlertsEnabledKey = "notifications.stagnationAlertsEnabled"

    /// Global default goal check-in interval (days). The "Follow my global
    /// cadence" button on GoalEditSheet snaps a goal's per-goal override back
    /// to this value, and new goals inherit it as their reminder cadence.
    nonisolated static let defaultCheckInIntervalKey = "reflection.defaultCheckInIntervalDays"

    /// The current global goal check-in default (days), falling back to 7 when
    /// unset. Single source of truth for reading `defaultCheckInIntervalKey`
    /// so the fallback lives in one place. `nonisolated` so non-async call
    /// sites (e.g. `GoalEditSheet.init`) can read it directly.
    nonisolated static var defaultCheckInInterval: Int {
        UserDefaults.standard.object(forKey: defaultCheckInIntervalKey) as? Int ?? 7
    }

    static let dailyNudgeIdentifier = "mortalloom.daily-nudge"
    static let weeklyReviewIdentifier = "mortalloom.weekly-review"
    static let monthlyRethinkIdentifier = "mortalloom.monthly-rethink"
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

    // MARK: Reflection plan (daily / weekly / monthly)

    /// Register every enabled reflection-cadence reminder against its current
    /// pref. Each ritual is an independent `UNCalendarNotificationTrigger`
    /// keyed by a stable identifier, so toggling or retiming one never
    /// disturbs the others. Idempotent — each call clears and re-adds the
    /// single pending request for each ritual, so it's safe to run on every
    /// launch and after any settings change.
    func scheduleReflectionPlan() async {
        // The three rituals are independent (distinct identifiers, no shared
        // state). This type is @MainActor, so the children don't run in true
        // parallel — but `async let` lets their notification-center `add`
        // awaits overlap (each suspension frees the actor for the next), so
        // launch isn't blocked on three fully-serial round-trips.
        async let daily: Void = scheduleDailyNudge()
        async let weekly: Void = scheduleWeeklyReviewReminder()
        async let monthly: Void = scheduleMonthlyRethinkReminder()
        _ = await (daily, weekly, monthly)
    }

    /// Daily nudge — fires every day at the configured hour (default 9am).
    func scheduleDailyNudge() async {
        let defaults = UserDefaults.standard
        let hour = defaults.object(forKey: Self.dailyNudgeHourKey) as? Int ?? 9
        await scheduleCalendarReminder(
            enabled: defaults.bool(forKey: Self.dailyNudgeEnabledKey),
            identifier: Self.dailyNudgeIdentifier,
            title: "Daily Nudge",
            body: ReflectionPrompts.dailyNudge,
            components: ReflectionPlan.dailyComponents(hour: hour),
            logLabel: "daily nudge hour=\(hour)"
        )
    }

    /// Weekly review — fires on the configured weekday + hour (default Sunday
    /// 6pm). Replaces any existing reminder so settings changes take effect
    /// immediately. No-op if the user has opted out.
    func scheduleWeeklyReviewReminder() async {
        let defaults = UserDefaults.standard
        let weekday = defaults.object(forKey: Self.weeklyReviewWeekdayKey) as? Int ?? 1
        let hour = defaults.object(forKey: Self.weeklyReviewHourKey) as? Int ?? 18
        await scheduleCalendarReminder(
            // Default-on (matches the Settings @AppStorage default) — read via
            // `object … ?? true` rather than `bool(forKey:)` so a user who
            // never persisted the key (e.g. skipped onboarding on a device that
            // already had iCloud data) still gets the reminder scheduled at
            // launch, instead of the silent false that `bool(forKey:)` returns.
            enabled: defaults.object(forKey: Self.weeklyReviewEnabledKey) as? Bool ?? true,
            identifier: Self.weeklyReviewIdentifier,
            title: "Weekly Review",
            body: "5 minutes to reset alignment and plan the week.",
            components: ReflectionPlan.weeklyComponents(weekday: weekday, hour: hour),
            logLabel: "weekly review weekday=\(weekday) hour=\(hour)"
        )
    }

    /// Monthly rethink — fires on the configured day-of-month + hour (default
    /// the 1st at 6pm). Day is clamped to 1…28 so it fires every month.
    func scheduleMonthlyRethinkReminder() async {
        let defaults = UserDefaults.standard
        let day = defaults.object(forKey: Self.monthlyRethinkDayKey) as? Int ?? 1
        let hour = defaults.object(forKey: Self.monthlyRethinkHourKey) as? Int ?? 18
        await scheduleCalendarReminder(
            enabled: defaults.bool(forKey: Self.monthlyRethinkEnabledKey),
            identifier: Self.monthlyRethinkIdentifier,
            title: "Monthly Rethink",
            body: "Step back and reassess your goals for the month ahead.",
            components: ReflectionPlan.monthlyComponents(day: day, hour: hour),
            logLabel: "monthly rethink day=\(day) hour=\(hour)"
        )
    }

    /// Shared scheduler for every plan-based reminder. Clears the existing
    /// pending request for `identifier`, then (if enabled) registers a single
    /// repeating calendar trigger built from `components`.
    private func scheduleCalendarReminder(
        enabled: Bool,
        identifier: String,
        title: String,
        body: String,
        components: DateComponents,
        logLabel: String
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            notificationLogger.info("🔔 scheduled \(logLabel, privacy: .public)")
        } catch {
            notificationLogger.error("🔔 failed to schedule \(logLabel, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Convenience to toggle the daily nudge on/off. Persists the choice and
    /// re-schedules (or clears) in one call.
    func setDailyNudgeEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.dailyNudgeEnabledKey)
        if enabled {
            _ = await requestAuthorization()
        }
        await scheduleDailyNudge()
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

    /// Convenience to toggle the monthly rethink on/off. Persists the choice
    /// and re-schedules (or clears) in one call.
    func setMonthlyRethinkEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.monthlyRethinkEnabledKey)
        if enabled {
            _ = await requestAuthorization()
        }
        await scheduleMonthlyRethinkReminder()
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

// MARK: - ReflectionPlan

/// Pure builders for the reflection-plan calendar triggers. Kept separate from
/// `NotificationService` (which is `@MainActor` and touches the notification
/// center) so the date-component math is unit-testable in isolation. Each
/// builder clamps its inputs to a range the calendar can always satisfy.
enum ReflectionPlan {
    /// Daily nudge: matches `hour` on every day → fires once per day.
    static func dailyComponents(hour: Int) -> DateComponents {
        var c = DateComponents()
        c.hour = clampHour(hour)
        c.minute = 0
        return c
    }

    /// Weekly review: matches `weekday` (1=Sun…7=Sat) + `hour` → fires weekly.
    static func weeklyComponents(weekday: Int, hour: Int) -> DateComponents {
        var c = DateComponents()
        c.weekday = clampWeekday(weekday)
        c.hour = clampHour(hour)
        c.minute = 0
        return c
    }

    /// Monthly rethink: matches `day`-of-month + `hour` → fires monthly. Day is
    /// clamped to 1…28 so the trigger fires in every month, February included
    /// (a `day` of 29–31 would silently skip months that lack that date).
    static func monthlyComponents(day: Int, hour: Int) -> DateComponents {
        var c = DateComponents()
        c.day = clampMonthDay(day)
        c.hour = clampHour(hour)
        c.minute = 0
        return c
    }

    static func clampHour(_ hour: Int) -> Int { min(23, max(0, hour)) }
    static func clampWeekday(_ weekday: Int) -> Int { min(7, max(1, weekday)) }
    static func clampMonthDay(_ day: Int) -> Int { min(28, max(1, day)) }
}
