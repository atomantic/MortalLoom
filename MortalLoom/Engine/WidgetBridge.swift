import Foundation
import os
import WidgetKit

private let widgetLogger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "Widget")

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
        let countdownMode: String?
        let levDeathDate: Date?
        let levYearsRemaining: Double?
        let levLifeExpectancy: Double?
        let levPercentComplete: Double?
    }

    static func update(data: AppData) {
        #if os(iOS)
        guard let birthDate = data.profile.birthDate,
              let result = DeathClockEngine.calculate(
                  birthDateStr: birthDate,
                  sex: data.profile.biologicalSex,
                  lifestyle: data.profile.lifestyle,
                  genome: data.genomeScanRecord,
                  locationProfile: data.profile.locationProfile
              ) else { return }

        let alcoholRisk = DeathClockEngine.alcoholRisk(
            drinks: data.alcoholDrinks, sex: data.profile.biologicalSex
        )
        let healthScore = DeathClockEngine.healthScore(
            lifestyle: data.profile.lifestyle,
            ageYears: result.ageYears,
            latestEpigeneticTest: data.epigeneticTests.sorted(by: { $0.date > $1.date }).first,
            alcoholRisk: alcoholRisk,
            healthMetrics: data.healthMetrics
        )

        let levResult = DeathClockEngine.calculateLEVResult(standardResult: result, birthDateStr: birthDate, levTargetAge: data.profile.levTargetAge)

        let snapshot = Snapshot(
            deathDate: result.deathDate,
            percentComplete: result.percentComplete,
            yearsRemaining: result.yearsRemaining,
            healthScore: healthScore,
            ageYears: result.ageYears,
            lifeExpectancy: result.lifeExpectancy.total,
            updatedAt: Date(),
            countdownMode: data.profile.countdownMode.rawValue,
            levDeathDate: levResult?.deathDate,
            levYearsRemaining: levResult?.yearsRemaining,
            levLifeExpectancy: levResult?.lifeExpectancy.total,
            levPercentComplete: levResult?.percentComplete
        )

        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
                .appendingPathComponent("widget-snapshot.json") else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(snapshot) else { return }
        // .completeFileProtectionUntilFirstUserAuthentication — widget extensions need
        // to be able to open/read the snapshot while the device is locked after
        // the first unlock following boot, while still keeping the file encrypted
        // at rest before first user authentication. We cannot use .complete
        // because WidgetKit reads the snapshot in the background.
        do {
            try encoded.write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            widgetLogger.error("⚠️ WidgetBridge.update failed to write snapshot: \(error.localizedDescription, privacy: .private)")
        }
        #endif
    }
}
