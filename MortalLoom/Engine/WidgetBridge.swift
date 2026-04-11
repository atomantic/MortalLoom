import Foundation
import os
import WidgetKit

private let widgetLogger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "Widget")

enum WidgetBridge: Sendable {
    static let appGroupID = "group.net.shadowpuppet.MeatSpaceTracker"

    struct WidgetGoal: Codable, Sendable {
        let title: String
        let targetDate: Date?
        let progressPercent: Double
        let isOverdue: Bool
        let needsCheckIn: Bool
        let category: String?
    }

    struct Snapshot: Codable, Sendable {
        let goals: [WidgetGoal]
        let activeCount: Int
        let overdueCount: Int
        let needsCheckInCount: Int
        let healthScore: Double
        let updatedAt: Date
        /// North Star goal title, if set. The widget uses this to frame
        /// the alignment score with the user's actual apex.
        let apexTitle: String?
        /// Current alignment score (0-100) derived from active standard
        /// descendants of the apex. Nil when the user has no apex or no
        /// standard goals to compute from.
        let alignmentScore: Double?
        /// One rotating reflection prompt surfaced on the widget so the
        /// user has a one-tap reflection entry point from the home screen.
        let todaysPrompt: String?
    }

    static func update(data: AppData) {
        #if os(iOS)
        let activeGoals = data.goals.filter { $0.status == .active }

        // Single-pass hierarchy walk — parent goals inherit check-in credit
        // from active descendants so the widget doesn't over-nag.
        let effectiveLatestDates = data.goals.effectiveLatestCheckInDates()
        var needsCheckInCount = 0
        var needsCheckInById: [UUID: Bool] = [:]
        for g in activeGoals {
            let days = DateFormatting.daysSince(effectiveLatestDates[g.id] ?? g.createdDate)
            let needs = days >= g.checkInIntervalDays
            needsCheckInById[g.id] = needs
            if needs { needsCheckInCount += 1 }
        }

        // Sort: overdue first, then by needsCheckIn, then by nearest target date
        let sorted = activeGoals.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            let aNeeds = needsCheckInById[a.id] ?? false
            let bNeeds = needsCheckInById[b.id] ?? false
            if aNeeds != bNeeds { return aNeeds }
            guard let aDate = a.targetDate, let bDate = b.targetDate else {
                return a.targetDate != nil
            }
            return aDate < bDate
        }

        let widgetGoals = sorted.prefix(5).map { goal in
            WidgetGoal(
                title: goal.title,
                targetDate: goal.targetDate.flatMap { DateFormatting.dateFromString($0) },
                progressPercent: goal.progressPercent,
                isOverdue: goal.isOverdue,
                needsCheckIn: needsCheckInById[goal.id] ?? false,
                category: goal.category?.rawValue
            )
        }

        // Compute health score if we have the data
        var healthScore = 0.0
        if let birthDate = data.profile.birthDate,
           let result = DeathClockEngine.calculate(
               birthDateStr: birthDate,
               sex: data.profile.biologicalSex,
               lifestyle: data.profile.lifestyle,
               genome: data.genomeScanRecord,
               locationProfile: data.profile.locationProfile,
               healthMetrics: data.healthMetrics
           ) {
            let alcoholRisk = DeathClockEngine.alcoholRisk(
                drinks: data.alcoholDrinks, sex: data.profile.biologicalSex
            )
            healthScore = DeathClockEngine.healthScore(
                lifestyle: data.profile.lifestyle,
                ageYears: result.ageYears,
                latestEpigeneticTest: data.epigeneticTests.sorted(by: { $0.date > $1.date }).first,
                alcoholRisk: alcoholRisk,
                healthMetrics: data.healthMetrics
            )
        }

        // Compute North Star alignment from active standard descendants.
        let apex = data.goals.first { $0.goalType == .apex && $0.status == .active }
        let alignment: Double? = apex.flatMap { GoalEngine.alignmentScore(for: $0, in: data.goals) }

        // Rotating prompt for the widget — excludes any answered on the apex
        // in the last 5 check-ins so the user doesn't see the same question
        // repeatedly.
        let todaysPrompt = apex != nil ? ReflectionPrompts.nextPrompt(for: apex) : nil

        let snapshot = Snapshot(
            goals: widgetGoals,
            activeCount: activeGoals.count,
            overdueCount: activeGoals.filter(\.isOverdue).count,
            needsCheckInCount: needsCheckInCount,
            healthScore: healthScore,
            updatedAt: Date(),
            apexTitle: apex?.title,
            alignmentScore: alignment,
            todaysPrompt: todaysPrompt
        )

        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
                .appendingPathComponent("widget-snapshot.json") else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(snapshot) else {
            widgetLogger.error("🧩 Failed to encode widget snapshot")
            return
        }
        do {
            let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            try encoded.write(to: url, options: writeOptions)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            widgetLogger.error("⚠️ WidgetBridge.update failed to write snapshot: \(error.localizedDescription, privacy: .private)")
        }
        #endif
    }

}
