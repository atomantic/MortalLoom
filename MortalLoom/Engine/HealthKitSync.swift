import Foundation
#if os(iOS)
import HealthKit

/// Pulls HealthKit metrics into AppData so they sync to macOS via iCloud.
/// Runs on iOS only since macOS doesn't have direct HealthKit access.
@MainActor
final class HealthKitSync {
    static let shared = HealthKitSync()

    private let hk = HealthKitService.shared

    /// Pull latest weight and body fat from HealthKit into bodyEntries.
    /// Merges with existing data — HealthKit entries won't duplicate manual entries.
    func syncBodyMetrics() async {
        guard hk.isAvailable, hk.authorized else { return }

        var data = await DataStore.shared.getData()
        var changed = false

        // Sync weight
        if let result = await hk.latestValue(for: .bodyMass, unit: .pound()) {
            let dateStr = DateFormatting.dateString(result.date)
            if let idx = data.bodyEntries.firstIndex(where: { $0.date == dateStr }) {
                if data.bodyEntries[idx].weightLbs != result.value {
                    data.bodyEntries[idx].weightLbs = result.value
                    changed = true
                }
            } else {
                data.bodyEntries.append(BodyEntry(date: dateStr, weightLbs: result.value))
                changed = true
            }
        }

        // Sync body fat percentage
        if let result = await hk.latestValue(for: .bodyFatPercentage, unit: .percent()) {
            let dateStr = DateFormatting.dateString(result.date)
            let pct = result.value * 100 // HealthKit returns 0-1
            if let idx = data.bodyEntries.firstIndex(where: { $0.date == dateStr }) {
                if data.bodyEntries[idx].bodyFatPct != pct {
                    data.bodyEntries[idx].bodyFatPct = pct
                    changed = true
                }
            } else {
                data.bodyEntries.append(BodyEntry(date: dateStr, bodyFatPct: pct))
                changed = true
            }
        }

        // Sync BMI into lifestyle profile if available
        if let result = await hk.latestValue(for: .bodyMassIndex, unit: .count()) {
            if data.profile.lifestyle.bmi != result.value {
                data.profile.lifestyle.bmi = result.value
                changed = true
            }
        }

        if changed {
            await DataStore.shared.save(data)
            NotificationCenter.default.post(name: .profileDidChange, object: nil)
        }
    }

    /// Pull historical weight data for the last 90 days.
    func syncWeightHistory() async {
        guard hk.isAvailable, hk.authorized else { return }

        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -90, to: to) ?? to

        let weightData = await hk.dailyStats(for: .bodyMass, unit: .pound(), aggregation: .average, from: from, to: to)
        guard !weightData.isEmpty else { return }

        var data = await DataStore.shared.getData()
        let existingDates = Set(data.bodyEntries.map(\.date))
        var changed = false

        for entry in weightData {
            let dateStr = DateFormatting.dateString(entry.date)
            if !existingDates.contains(dateStr) {
                data.bodyEntries.append(BodyEntry(date: dateStr, weightLbs: entry.value))
                changed = true
            }
        }

        if changed {
            await DataStore.shared.save(data)
            NotificationCenter.default.post(name: .profileDidChange, object: nil)
        }
    }

    /// Pull 90 days of daily health metrics (HRV, heart rate, steps, etc.) into AppData.
    /// These persist to iCloud so macOS can render correlation charts without HealthKit.
    func syncHealthMetrics() async {
        guard hk.isAvailable, hk.authorized else { return }

        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -90, to: to) ?? to

        // Fetch all metric types in parallel
        async let hrvData = hk.dailyStats(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), aggregation: .average, from: from, to: to)
        async let hrData = hk.dailyStats(for: .heartRate, unit: .count().unitDivided(by: .minute()), aggregation: .average, from: from, to: to)
        async let rhrData = hk.dailyStats(for: .restingHeartRate, unit: .count().unitDivided(by: .minute()), aggregation: .average, from: from, to: to)
        async let stepsData = hk.dailyStats(for: .stepCount, unit: .count(), aggregation: .sum, from: from, to: to)
        async let activeEnergyData = hk.dailyStats(for: .activeEnergyBurned, unit: .kilocalorie(), aggregation: .sum, from: from, to: to)
        async let exerciseData = hk.dailyStats(for: .appleExerciseTime, unit: .minute(), aggregation: .sum, from: from, to: to)
        async let flightsData = hk.dailyStats(for: .flightsClimbed, unit: .count(), aggregation: .sum, from: from, to: to)
        async let vo2Data = hk.dailyStats(for: .vo2Max, unit: HKUnit(from: "mL/min*kg"), aggregation: .average, from: from, to: to)
        async let spo2Data = hk.dailyStats(for: .oxygenSaturation, unit: .percent(), aggregation: .average, from: from, to: to)
        async let respData = hk.dailyStats(for: .respiratoryRate, unit: .count().unitDivided(by: .minute()), aggregation: .average, from: from, to: to)

        // Collect all results
        let hrv = await hrvData
        let hr = await hrData
        let rhr = await rhrData
        let steps = await stepsData
        let energy = await activeEnergyData
        let exercise = await exerciseData
        let flights = await flightsData
        let vo2 = await vo2Data
        let spo2 = await spo2Data
        let resp = await respData

        // Build a date-keyed dictionary of all metrics
        var byDate: [String: HealthMetricEntry] = [:]

        func merge(_ data: [(date: Date, value: Double)], into path: WritableKeyPath<HealthMetricEntry, Double?>) {
            for item in data {
                let dateStr = DateFormatting.dateString(item.date)
                var entry = byDate[dateStr] ?? HealthMetricEntry(date: dateStr)
                entry[keyPath: path] = item.value
                byDate[dateStr] = entry
            }
        }

        merge(hrv, into: \.hrv)
        merge(hr, into: \.heartRate)
        merge(rhr, into: \.restingHeartRate)
        merge(steps, into: \.steps)
        merge(energy, into: \.activeEnergy)
        merge(exercise, into: \.exerciseMinutes)
        merge(flights, into: \.flightsClimbed)
        merge(vo2, into: \.vo2Max)
        merge(resp, into: \.respiratoryRate)

        // SpO2 comes as 0-1, convert to 0-100
        for item in spo2 {
            let dateStr = DateFormatting.dateString(item.date)
            var entry = byDate[dateStr] ?? HealthMetricEntry(date: dateStr)
            entry.oxygenSaturation = item.value * 100
            byDate[dateStr] = entry
        }

        guard !byDate.isEmpty else { return }

        await DataStore.shared.upsertHealthMetrics(Array(byDate.values))
        NotificationCenter.default.post(name: .dataDidSync, object: nil)
    }
}
#endif
