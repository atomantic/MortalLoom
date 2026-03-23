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
}
#endif
