import Foundation

struct CorrelationDataPoint: Sendable {
    let testDate: Date
    let avgDailySteps: Double
    let avgDailyDistance: Double?
    let avgExerciseMinutes: Double?
    let avgHRV: Double?
    let avgSleepHours: Double?
    let avgDeepSleepPct: Double?
    let avgStandMinutes: Double?
    let markers: [String: Double]
}

/// A day's alcohol intake paired with next-night sleep stage quality.
struct AlcoholSleepDataPoint: Sendable {
    let date: String           // "YYYY-MM-DD" of the drinking day
    let standardDrinks: Double // total standard drinks that day
    let nextNightDeepPct: Double? // deep sleep % the following night
    let nextNightRemPct: Double?  // REM sleep % the following night
    let nextNightTotalHours: Double? // total sleep hours the following night
}

enum CorrelationEngine {

    // MARK: - Alcohol → Sleep Quality

    /// Build per-day data points correlating alcohol intake with next-night sleep stages.
    /// Alcohol consumed on day N is compared to sleep recorded on day N+1
    /// (sleep that ends the morning after drinking).
    static func alcoholSleepCorrelation(
        drinks: [AlcoholDrink],
        healthMetrics: [HealthMetricEntry]
    ) -> [AlcoholSleepDataPoint] {
        guard !drinks.isEmpty, !healthMetrics.isEmpty else { return [] }

        // Index sleep metrics by date string for O(1) lookup
        let sleepByDate = Dictionary(grouping: healthMetrics, by: \.date)
            .compactMapValues(\.first)

        // Sum standard drinks per day
        var drinksByDate: [String: Double] = [:]
        for drink in drinks {
            drinksByDate[drink.date, default: 0] += drink.standardDrinks
        }

        // Also include zero-drink days that have sleep data for contrast
        let allSleepDates = Set(healthMetrics.compactMap { m -> String? in
            guard m.sleepDeepHours != nil || m.sleepRemHours != nil else { return nil }
            // The sleep date is the morning-after date; the "drinking day" is one day prior
            guard let sleepDate = DateFormatting.dateFromString(m.date) else { return nil }
            guard let priorDay = Calendar.current.date(byAdding: .day, value: -1, to: sleepDate) else { return nil }
            return DateFormatting.dateString(priorDay)
        })

        let allDates = Set(drinksByDate.keys).union(allSleepDates)

        return allDates.compactMap { dateStr -> AlcoholSleepDataPoint? in
            let drinks = drinksByDate[dateStr] ?? 0

            // Look up sleep for the next day (morning after)
            guard let day = DateFormatting.dateFromString(dateStr),
                  let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return nil }
            let nextDayStr = DateFormatting.dateString(nextDay)
            let sleep = sleepByDate[nextDayStr]

            let total = sleep?.sleepHours
            let deepPct: Double? = {
                guard let deep = sleep?.sleepDeepHours, let t = total, t > 0 else { return nil }
                return (deep / t) * 100
            }()
            let remPct: Double? = {
                guard let rem = sleep?.sleepRemHours, let t = total, t > 0 else { return nil }
                return (rem / t) * 100
            }()

            // Only include if we have at least some sleep data for the next night
            guard deepPct != nil || remPct != nil || total != nil else { return nil }

            return AlcoholSleepDataPoint(
                date: dateStr,
                standardDrinks: drinks,
                nextNightDeepPct: deepPct,
                nextNightRemPct: remPct,
                nextNightTotalHours: total
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Activity → Blood Markers

    static func buildCorrelationData(
        tests: [BloodTest],
        healthMetrics: [HealthMetricEntry],
        windowDays: Int = 30
    ) -> [CorrelationDataPoint] {
        let metricsByDate = Dictionary(grouping: healthMetrics, by: \.date)

        return tests.compactMap { test -> CorrelationDataPoint? in
            guard let testDate = DateFormatting.dateFromString(test.date) else { return nil }

            var totalSteps = 0.0, totalDist = 0.0, totalExercise = 0.0
            var totalHRV = 0.0, totalSleep = 0.0, totalDeepPct = 0.0, totalStand = 0.0
            var count = 0.0
            var distCount = 0.0, exerciseCount = 0.0, hrvCount = 0.0
            var sleepCount = 0.0, deepCount = 0.0, standCount = 0.0

            for dayOffset in 1...windowDays {
                guard let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: testDate) else { continue }
                let dayStr = DateFormatting.dateString(day)
                guard let metrics = metricsByDate[dayStr]?.first else { continue }

                totalSteps += metrics.steps ?? 0
                count += 1

                if let d = metrics.walkingDistance { totalDist += d; distCount += 1 }
                if let e = metrics.exerciseMinutes { totalExercise += e; exerciseCount += 1 }
                if let h = metrics.hrv { totalHRV += h; hrvCount += 1 }
                if let s = metrics.sleepHours { totalSleep += s; sleepCount += 1 }
                if let deep = metrics.sleepDeepHours, let total = metrics.sleepHours, total > 0 {
                    totalDeepPct += (deep / total) * 100
                    deepCount += 1
                }
                if let st = metrics.standMinutes { totalStand += st; standCount += 1 }
            }

            guard count > 0 else { return nil }

            return CorrelationDataPoint(
                testDate: testDate,
                avgDailySteps: totalSteps / count,
                avgDailyDistance: distCount > 0 ? totalDist / distCount : nil,
                avgExerciseMinutes: exerciseCount > 0 ? totalExercise / exerciseCount : nil,
                avgHRV: hrvCount > 0 ? totalHRV / hrvCount : nil,
                avgSleepHours: sleepCount > 0 ? totalSleep / sleepCount : nil,
                avgDeepSleepPct: deepCount > 0 ? totalDeepPct / deepCount : nil,
                avgStandMinutes: standCount > 0 ? totalStand / standCount : nil,
                markers: test.markers
            )
        }
    }
}
