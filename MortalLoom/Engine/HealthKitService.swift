import Foundation
import HealthKit
import os

private let logger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "HealthKit")

@MainActor @Observable
final class HealthKitService {
    static let shared = HealthKitService()

    @ObservationIgnored private let store = HKHealthStore()
    private(set) var authorizationRequestCompleted = false

    // All types we want to read
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
            .oxygenSaturation, .respiratoryRate, .vo2Max,
            .stepCount, .activeEnergyBurned, .basalEnergyBurned,
            .flightsClimbed, .appleExerciseTime, .appleStandTime,
            .distanceWalkingRunning, .distanceCycling,
            .bodyMass, .bodyMassIndex, .bodyFatPercentage, .leanBodyMass,
            .walkingSpeed, .walkingStepLength,
            .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage,
            .stairAscentSpeed, .stairDescentSpeed, .walkingHeartRateAverage,
            .heartRateRecoveryOneMinute,
            .timeInDaylight,
            .environmentalAudioExposure, .headphoneAudioExposure,
        ]
        for id in quantityTypes {
            if let t = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(t)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            // HealthKit completes without throwing even when the user
            // denies access. For read-only types Apple keeps authorization
            // status opaque (always .notDetermined) for privacy reasons,
            // so there is no API to confirm access was granted without a
            // data query. `authorized` means "auth prompt completed without
            // error"; callers must handle empty / nil query results.
            authorizationRequestCompleted = true
        } catch {
            authorizationRequestCompleted = false
            // Surface the failure so it can be diagnosed in Console.app —
            // previously the error was silently swallowed and "denied" was
            // indistinguishable from "request threw an error".
            logger.error("🩺 HealthKit authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // Query latest value for a quantity type
    func latestValue(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> (value: Double, date: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: (value, sample.startDate))
            }
            store.execute(query)
        }
    }

    // Query daily averages/sums for a date range
    func dailyStats(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, aggregation: StatAggregation, from: Date, to: Date) async -> [(date: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
            let interval = DateComponents(day: 1)

            let options: HKStatisticsOptions = aggregation == .sum
                ? .cumulativeSum
                : .discreteAverage

            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: Calendar.current.startOfDay(for: from),
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, _ in
                var data: [(Date, Double)] = []
                results?.enumerateStatistics(from: from, to: to) { stats, _ in
                    let val: Double?
                    if aggregation == .sum {
                        val = stats.sumQuantity()?.doubleValue(for: unit)
                    } else {
                        val = stats.averageQuantity()?.doubleValue(for: unit)
                    }
                    if let v = val {
                        data.append((stats.startDate, v))
                    }
                }
                continuation.resume(returning: data)
            }

            store.execute(query)
        }
    }

    // Query daily total sleep hours for a date range.
    // Sums all asleep sample durations (core + deep + REM + unspecified) per calendar day.
    func dailySleepHours(from: Date, to: Date) async -> [(date: Date, value: Double)] {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }

                // Filter to asleep samples only (not inBed or awake)
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let asleepSamples = samples.filter { asleepValues.contains($0.value) }

                // Group by the calendar day of the sample's END date (sleep ends in morning)
                var dailySeconds: [Date: Double] = [:]
                let calendar = Calendar.current
                for sample in asleepSamples {
                    let dayStart = calendar.startOfDay(for: sample.endDate)
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    dailySeconds[dayStart, default: 0] += duration
                }

                let result = dailySeconds.map { (date: $0.key, value: $0.value / 3600.0) }
                    .sorted { $0.date < $1.date }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    /// Sleep stage breakdown per calendar day.
    struct SleepStageDay: Sendable {
        let date: Date
        let totalHours: Double
        let deepHours: Double
        let remHours: Double
        let coreHours: Double
    }

    /// Query daily sleep with stage breakdown (deep / REM / core).
    func dailySleepStages(from: Date, to: Date) async -> [SleepStageDay] {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let calendar = Calendar.current
                var dayDeep: [Date: Double] = [:]
                var dayRem: [Date: Double] = [:]
                var dayCore: [Date: Double] = [:]
                var dayTotal: [Date: Double] = [:]

                for sample in samples {
                    let dayStart = calendar.startOfDay(for: sample.endDate)
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        dayDeep[dayStart, default: 0] += duration
                        dayTotal[dayStart, default: 0] += duration
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        dayRem[dayStart, default: 0] += duration
                        dayTotal[dayStart, default: 0] += duration
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        dayCore[dayStart, default: 0] += duration
                        dayTotal[dayStart, default: 0] += duration
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        dayCore[dayStart, default: 0] += duration
                        dayTotal[dayStart, default: 0] += duration
                    default:
                        break // inBed, awake — don't count
                    }
                }

                let allDates = Set(dayTotal.keys)
                let result = allDates.map { date in
                    SleepStageDay(
                        date: date,
                        totalHours: dayTotal[date] ?? 0,
                        deepHours: dayDeep[date] ?? 0,
                        remHours: dayRem[date] ?? 0,
                        coreHours: dayCore[date] ?? 0
                    )
                }.sorted { $0.date < $1.date }

                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    enum StatAggregation {
        case sum, average
    }
}
