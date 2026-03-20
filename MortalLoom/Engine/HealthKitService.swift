import Foundation
import HealthKit

@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    @Published var authorized = false

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
            authorized = true
        } catch {
            authorized = false
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

    enum StatAggregation {
        case sum, average
    }
}
