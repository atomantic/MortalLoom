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

/// A sauna session day paired with next-day HRV and sleep stage quality.
struct SaunaRecoveryDataPoint: Sendable {
    let date: String              // "YYYY-MM-DD" of the sauna day
    let saunaMinutes: Int         // total sauna minutes that day
    let nextDayHRV: Double?       // HRV (ms SDNN) the following day
    let nextNightDeepPct: Double? // deep sleep % the following night
    let nextNightRemPct: Double?  // REM sleep % the following night
    let nextNightTotalHours: Double? // total sleep hours the following night
}

/// A day's alcohol intake paired with next-night sleep stage quality.
struct AlcoholSleepDataPoint: Sendable {
    let date: String           // "YYYY-MM-DD" of the drinking day
    let standardDrinks: Double // total standard drinks that day
    let nextNightDeepPct: Double? // deep sleep % the following night
    let nextNightRemPct: Double?  // REM sleep % the following night
    let nextNightTotalHours: Double? // total sleep hours the following night
}

/// Nicotine usage over the last 30 days paired with same-day heart rate, plus a
/// high-vs-low comparison summarising the heart-rate difference between the
/// user's nicotine (or higher-usage) days and their clean (or lower-usage) days.
struct NicotineHRCorrelation: Sendable {
    let correlationData: [NicotineHRDataPoint]
    let highLabel: String
    let lowLabel: String
    let avgHigh: Double
    let avgLow: Double
    let hasData: Bool
    let explanation: String
}

/// One day's heart rate paired with that day's total nicotine intake.
struct NicotineHRDataPoint: Sendable {
    let date: String
    let hr: Double?
    let rhr: Double?
    let nicotineMg: Double
}

enum CorrelationEngine {

    // MARK: - Sauna → HRV / Sleep Quality

    /// Build per-day data points correlating sauna use with next-day HRV and sleep stages.
    /// Sauna on day N is compared to HRV on day N+1 and sleep recorded on day N+1.
    static func saunaRecoveryCorrelation(
        sessions: [SaunaSession],
        healthMetrics: [HealthMetricEntry]
    ) -> [SaunaRecoveryDataPoint] {
        guard !sessions.isEmpty, !healthMetrics.isEmpty else { return [] }

        let metricsByDate = Dictionary(grouping: healthMetrics, by: \.date)
            .compactMapValues(\.first)

        // Sum sauna minutes per day
        var minutesByDate: [String: Int] = [:]
        for session in sessions {
            minutesByDate[session.date, default: 0] += session.durationMinutes
        }

        // Also include non-sauna days that have HRV/sleep data for contrast
        let allMetricDates = Set(healthMetrics.compactMap { m -> String? in
            guard m.hrv != nil || m.sleepDeepHours != nil else { return nil }
            guard let metricDate = DateFormatting.dateFromString(m.date) else { return nil }
            guard let priorDay = Calendar.current.date(byAdding: .day, value: -1, to: metricDate) else { return nil }
            return DateFormatting.dateString(priorDay)
        })

        let allDates = Set(minutesByDate.keys).union(allMetricDates)

        return allDates.compactMap { dateStr -> SaunaRecoveryDataPoint? in
            let minutes = minutesByDate[dateStr] ?? 0

            guard let day = DateFormatting.dateFromString(dateStr),
                  let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return nil }
            let nextDayStr = DateFormatting.dateString(nextDay)
            let nextMetrics = metricsByDate[nextDayStr]

            let hrv = nextMetrics?.hrv
            let total = nextMetrics?.sleepHours
            let deepPct: Double? = {
                guard let deep = nextMetrics?.sleepDeepHours, let t = total, t > 0 else { return nil }
                return (deep / t) * 100
            }()
            let remPct: Double? = {
                guard let rem = nextMetrics?.sleepRemHours, let t = total, t > 0 else { return nil }
                return (rem / t) * 100
            }()

            guard hrv != nil || deepPct != nil || remPct != nil || total != nil else { return nil }

            return SaunaRecoveryDataPoint(
                date: dateStr,
                saunaMinutes: minutes,
                nextDayHRV: hrv,
                nextNightDeepPct: deepPct,
                nextNightRemPct: remPct,
                nextNightTotalHours: total
            )
        }.sorted { $0.date < $1.date }
    }

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

    // MARK: - Alcohol → Breathing Disturbances

    struct AlcoholBreathingDataPoint: Sendable {
        let date: String
        let standardDrinks: Double
        let nextNightDisturbances: Double?
    }

    static func alcoholBreathingCorrelation(
        drinks: [AlcoholDrink],
        healthMetrics: [HealthMetricEntry]
    ) -> [AlcoholBreathingDataPoint] {
        guard !drinks.isEmpty, !healthMetrics.isEmpty else { return [] }

        let metricsByDate = Dictionary(grouping: healthMetrics, by: \.date)
            .compactMapValues(\.first)

        var drinksByDate: [String: Double] = [:]
        for drink in drinks {
            drinksByDate[drink.date, default: 0] += drink.standardDrinks
        }

        let allMetricDates = Set(healthMetrics.compactMap { m -> String? in
            guard m.breathingDisturbances != nil else { return nil }
            guard let metricDate = DateFormatting.dateFromString(m.date) else { return nil }
            guard let priorDay = Calendar.current.date(byAdding: .day, value: -1, to: metricDate) else { return nil }
            return DateFormatting.dateString(priorDay)
        })

        let allDates = Set(drinksByDate.keys).union(allMetricDates)

        return allDates.compactMap { dateStr -> AlcoholBreathingDataPoint? in
            let drinks = drinksByDate[dateStr] ?? 0

            guard let day = DateFormatting.dateFromString(dateStr),
                  let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return nil }
            let nextDayStr = DateFormatting.dateString(nextDay)
            let nextMetrics = metricsByDate[nextDayStr]

            guard let disturbances = nextMetrics?.breathingDisturbances else { return nil }

            return AlcoholBreathingDataPoint(
                date: dateStr,
                standardDrinks: drinks,
                nextNightDisturbances: disturbances
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Nicotine → Heart Rate

    /// Correlate the last 30 days of nicotine intake with same-day heart rate.
    ///
    /// Builds two comparison groups: prefer clean-vs-used when the user has at
    /// least 3 days of each. For daily users (few or no zero-nicotine days), fall
    /// back to a median split — high-usage days vs low-usage days — so the card
    /// still shows a meaningful contrast.
    static func nicotineHeartRateCorrelation(
        entries: [NicotineEntry],
        healthMetrics: [HealthMetricEntry],
        now: Date = Date()
    ) -> NicotineHRCorrelation {
        let days = (0..<30).reversed().map { DateFormatting.dateString(daysAgo: $0, from: now) }
        let metricsByDate = Dictionary(healthMetrics.map { ($0.date, $0) }, uniquingKeysWith: { _, latest in latest })
        let nicoByDate = Dictionary(grouping: entries, by: \.date)

        let correlationData: [NicotineHRDataPoint] = days.map { day in
            let metric = metricsByDate[day]
            let mg = (nicoByDate[day] ?? []).reduce(0.0) { $0 + $1.totalMg }
            return NicotineHRDataPoint(date: day, hr: metric?.heartRate, rhr: metric?.restingHeartRate, nicotineMg: mg)
        }

        // Build comparison groups. Prefer clean-vs-used when the user has enough
        // of both. For daily users (few or no zero-nicotine days), fall back to
        // a median split: high-usage days vs low-usage days.
        let daysWithHR = correlationData.filter { $0.hr != nil }
        let zeroDays = daysWithHR.filter { $0.nicotineMg == 0 }
        let usedDays = daysWithHR.filter { $0.nicotineMg > 0 }

        let cleanVsUsed = zeroDays.count >= 3 && usedDays.count >= 3
        let highGroup: [NicotineHRDataPoint]
        let lowGroup: [NicotineHRDataPoint]
        let highLabel: String
        let lowLabel: String
        let explanation: String

        if cleanVsUsed {
            highGroup = usedDays
            lowGroup = zeroDays
            highLabel = "Nicotine Days"
            lowLabel = "Clean Days"
            explanation = "Nicotine raises heart rate by stimulating adrenaline release."
        } else {
            // Median split on usage among days with HR data. Prefer used-only
            // days when there are enough of them.
            let pool = usedDays.count >= 4 ? usedDays : daysWithHR
            let sortedMg = pool.map(\.nicotineMg).sorted()
            let median: Double
            if sortedMg.isEmpty {
                median = 0
            } else {
                let mid = sortedMg.count / 2
                median = sortedMg.count % 2 == 0
                    ? (sortedMg[mid - 1] + sortedMg[mid]) / 2
                    : sortedMg[mid]
            }
            highGroup = pool.filter { $0.nicotineMg > median }
            lowGroup = pool.filter { $0.nicotineMg <= median }
            highLabel = "High Usage"
            lowLabel = "Low Usage"
            explanation = "Comparing your higher-usage days against your lower-usage days. Nicotine raises heart rate by stimulating adrenaline release."
        }

        let avgHigh = highGroup.isEmpty ? 0 : highGroup.compactMap(\.hr).reduce(0, +) / Double(highGroup.count)
        let avgLow = lowGroup.isEmpty ? 0 : lowGroup.compactMap(\.hr).reduce(0, +) / Double(lowGroup.count)
        let hasData = !highGroup.isEmpty && !lowGroup.isEmpty

        return NicotineHRCorrelation(
            correlationData: correlationData,
            highLabel: highLabel,
            lowLabel: lowLabel,
            avgHigh: avgHigh,
            avgLow: avgLow,
            hasData: hasData,
            explanation: explanation
        )
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
