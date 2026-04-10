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
    }

    static func update(data: AppData) {
        #if os(iOS)
        let activeGoals = data.goals.filter { $0.status == .active }

        // Sort: overdue first, then by nearest target date, then by needsCheckIn
        let sorted = activeGoals.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            if a.needsCheckIn != b.needsCheckIn { return a.needsCheckIn }
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
                needsCheckIn: goal.needsCheckIn,
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

        let snapshot = Snapshot(
            goals: widgetGoals,
            activeCount: activeGoals.count,
            overdueCount: activeGoals.filter(\.isOverdue).count,
            needsCheckInCount: activeGoals.filter(\.needsCheckIn).count,
            healthScore: healthScore,
            updatedAt: Date()
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
