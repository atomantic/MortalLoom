import Foundation
import WidgetKit

enum WidgetBridge: Sendable {
    static let appGroupID = "group.net.shadowpuppet.MeatSpaceTracker"

    struct Snapshot: Codable, Sendable {
        let deathDate: Date
        let percentComplete: Double
        let yearsRemaining: Double
        let healthScore: Double
        let ageYears: Int
        let lifeExpectancy: Double
        let updatedAt: Date
    }

    static func update(data: AppData) {
        guard let birthDate = data.profile.birthDate,
              let result = DeathClockEngine.calculate(
                  birthDateStr: birthDate,
                  sex: data.profile.biologicalSex,
                  lifestyle: data.profile.lifestyle
              ) else { return }

        let alcoholRisk = DeathClockEngine.alcoholRisk(
            drinks: data.alcoholDrinks, sex: data.profile.biologicalSex
        )
        let healthScore = DeathClockEngine.healthScore(
            lifestyle: data.profile.lifestyle,
            ageYears: result.ageYears,
            latestEpigeneticTest: data.epigeneticTests.sorted(by: { $0.date > $1.date }).first,
            alcoholRisk: alcoholRisk
        )

        let snapshot = Snapshot(
            deathDate: result.deathDate,
            percentComplete: result.percentComplete,
            yearsRemaining: result.yearsRemaining,
            healthScore: healthScore,
            ageYears: result.ageYears,
            lifeExpectancy: result.lifeExpectancy.total,
            updatedAt: Date()
        )

        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
                .appendingPathComponent("widget-snapshot.json") else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(snapshot) else { return }
        try? encoded.write(to: url, options: .atomic)

        WidgetCenter.shared.reloadAllTimelines()
    }
}
