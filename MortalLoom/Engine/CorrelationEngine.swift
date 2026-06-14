import Foundation

struct CorrelationDataPoint: Sendable {
    let testDate: Date
    let avgDailySteps: Double
    let avgDailyDistance: Double?         // walking + running, km, averaged over days with a walking reading
    let avgDailyCyclingDistance: Double?  // cycling, km, averaged over days with a cycling reading
    // Combined walking/running + cycling distance, averaged per day over the days
    // that had ANY distance reading. This is NOT `avgDailyDistance + avgDailyCyclingDistance`:
    // those two are averaged over different denominators (walking is near-daily,
    // cycling is sparse), so summing them overstates active distance on days a
    // person didn't cycle. Averaging the per-day total over one shared denominator
    // keeps a single 30 km ride from reading as +30 km/day across the window.
    let avgDailyActiveDistance: Double?
    let avgExerciseMinutes: Double?
    let avgHRV: Double?
    let avgSleepHours: Double?
    let avgDeepSleepPct: Double?
    let avgStandMinutes: Double?
    let markers: [String: Double]
}

/// A correlation point keyed by the `"YYYY-MM-DD"` day it represents. Lets the
/// shared `nextDayPairing` skeleton sort heterogeneous result types by date.
protocol DatedCorrelationPoint: Sendable {
    var date: String { get }
}

/// A sauna session day paired with next-day HRV and sleep stage quality.
struct SaunaRecoveryDataPoint: DatedCorrelationPoint {
    let date: String              // "YYYY-MM-DD" of the sauna day
    let saunaMinutes: Int         // total sauna minutes that day
    let nextDayHRV: Double?       // HRV (ms SDNN) the following day
    let nextNightDeepPct: Double? // deep sleep % the following night
    let nextNightRemPct: Double?  // REM sleep % the following night
    let nextNightTotalHours: Double? // total sleep hours the following night
}

/// A day's alcohol intake paired with next-night sleep stage quality.
struct AlcoholSleepDataPoint: DatedCorrelationPoint {
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

    // MARK: - Shared next-day pairing

    /// Percentage a sleep stage contributes to the night's total, or `nil` when
    /// the stage value or a positive total is missing.
    static func sleepStagePercent(_ stageHours: Double?, of totalHours: Double?) -> Double? {
        guard let stage = stageHours, let total = totalHours, total > 0 else { return nil }
        return (stage / total) * 100
    }

    /// Pair a per-day "cause" series (sauna minutes, standard drinks, …) with the
    /// health metric recorded the *following* day. Sums `value(cause)` per
    /// `causeDate`, seeds contrast days from metrics matching `metricIsRelevant`
    /// (whose prior day had no cause), then lets `build` produce a point per day;
    /// `nil` points are dropped and the result is sorted by date. This is the
    /// skeleton the sauna/alcohol correlations previously each duplicated.
    static func nextDayPairing<Cause, Point: DatedCorrelationPoint>(
        causes: [Cause],
        causeDate: KeyPath<Cause, String>,
        value: (Cause) -> Double,
        healthMetrics: [HealthMetricEntry],
        metricIsRelevant: (HealthMetricEntry) -> Bool,
        build: (_ date: String, _ causeTotal: Double, _ nextDayMetric: HealthMetricEntry?) -> Point?
    ) -> [Point] {
        guard !causes.isEmpty, !healthMetrics.isEmpty else { return [] }

        let metricsByDate = Dictionary(grouping: healthMetrics, by: \.date)
            .compactMapValues(\.first)

        // Sum the cause value per day.
        var causeByDate: [String: Double] = [:]
        for cause in causes {
            causeByDate[cause[keyPath: causeDate], default: 0] += value(cause)
        }

        // Seed contrast days: a relevant metric implies its *prior* day, so a
        // zero-cause day with next-day data still appears.
        let priorDates = Set(healthMetrics.compactMap { m -> String? in
            guard metricIsRelevant(m),
                  let metricDate = DateFormatting.dateFromString(m.date),
                  let priorDay = Calendar.current.date(byAdding: .day, value: -1, to: metricDate)
            else { return nil }
            return DateFormatting.dateString(priorDay)
        })

        let allDates = Set(causeByDate.keys).union(priorDates)

        return allDates.compactMap { dateStr -> Point? in
            guard let day = DateFormatting.dateFromString(dateStr),
                  let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)
            else { return nil }
            let nextDayStr = DateFormatting.dateString(nextDay)
            return build(dateStr, causeByDate[dateStr] ?? 0, metricsByDate[nextDayStr])
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Sauna → HRV / Sleep Quality

    /// Build per-day data points correlating sauna use with next-day HRV and sleep stages.
    /// Sauna on day N is compared to HRV on day N+1 and sleep recorded on day N+1.
    static func saunaRecoveryCorrelation(
        sessions: [SaunaSession],
        healthMetrics: [HealthMetricEntry]
    ) -> [SaunaRecoveryDataPoint] {
        nextDayPairing(
            causes: sessions,
            causeDate: \.date,
            value: { Double($0.durationMinutes) },
            healthMetrics: healthMetrics,
            metricIsRelevant: { $0.hrv != nil || $0.sleepDeepHours != nil }
        ) { dateStr, minutes, nextMetrics in
            let hrv = nextMetrics?.hrv
            let total = nextMetrics?.sleepHours
            let deepPct = sleepStagePercent(nextMetrics?.sleepDeepHours, of: total)
            let remPct = sleepStagePercent(nextMetrics?.sleepRemHours, of: total)

            guard hrv != nil || deepPct != nil || remPct != nil || total != nil else { return nil }

            return SaunaRecoveryDataPoint(
                date: dateStr,
                saunaMinutes: Int(minutes),
                nextDayHRV: hrv,
                nextNightDeepPct: deepPct,
                nextNightRemPct: remPct,
                nextNightTotalHours: total
            )
        }
    }

    // MARK: - Alcohol → Sleep Quality

    /// Build per-day data points correlating alcohol intake with next-night sleep stages.
    /// Alcohol consumed on day N is compared to sleep recorded on day N+1
    /// (sleep that ends the morning after drinking).
    static func alcoholSleepCorrelation(
        drinks: [AlcoholDrink],
        healthMetrics: [HealthMetricEntry]
    ) -> [AlcoholSleepDataPoint] {
        // Alcohol on day N is compared to sleep recorded on day N+1 (the morning
        // after), so a relevant sleep metric implies a drinking day one day prior.
        nextDayPairing(
            causes: drinks,
            causeDate: \.date,
            value: { $0.standardDrinks },
            healthMetrics: healthMetrics,
            metricIsRelevant: { $0.sleepDeepHours != nil || $0.sleepRemHours != nil }
        ) { dateStr, drinks, sleep in
            let total = sleep?.sleepHours
            let deepPct = sleepStagePercent(sleep?.sleepDeepHours, of: total)
            let remPct = sleepStagePercent(sleep?.sleepRemHours, of: total)

            // Only include if we have at least some sleep data for the next night
            guard deepPct != nil || remPct != nil || total != nil else { return nil }

            return AlcoholSleepDataPoint(
                date: dateStr,
                standardDrinks: drinks,
                nextNightDeepPct: deepPct,
                nextNightRemPct: remPct,
                nextNightTotalHours: total
            )
        }
    }

    // MARK: - Alcohol → Breathing Disturbances

    struct AlcoholBreathingDataPoint: DatedCorrelationPoint {
        let date: String
        let standardDrinks: Double
        let nextNightDisturbances: Double?
    }

    static func alcoholBreathingCorrelation(
        drinks: [AlcoholDrink],
        healthMetrics: [HealthMetricEntry]
    ) -> [AlcoholBreathingDataPoint] {
        nextDayPairing(
            causes: drinks,
            causeDate: \.date,
            value: { $0.standardDrinks },
            healthMetrics: healthMetrics,
            metricIsRelevant: { $0.breathingDisturbances != nil }
        ) { dateStr, drinks, nextMetrics in
            guard let disturbances = nextMetrics?.breathingDisturbances else { return nil }

            return AlcoholBreathingDataPoint(
                date: dateStr,
                standardDrinks: drinks,
                nextNightDisturbances: disturbances
            )
        }
    }

    // MARK: - BMI → Breathing Disturbances

    /// A night's body-mass index paired with that night's breathing disturbances
    /// (apnea/hypopnea events per hour during sleep). Surfaces the obesity↔apnea
    /// link on `BodyView`.
    struct BMIBreathingDataPoint: DatedCorrelationPoint {
        let date: String                  // "YYYY-MM-DD" of the night
        let bmi: Double                   // BMI implied by the carried-forward weigh-in
        let breathingDisturbances: Double // apnea/hypopnea events per hour that night
    }

    /// Height (inches) implied by a known `bmi` at a known `weightLbs`, via the
    /// imperial formula `BMI = 703 × lbs / in²`. The app stores a single static
    /// BMI rather than a height, so we back the height out of the user's
    /// reference weigh-in to reconstruct BMI for their other weigh-ins. Returns
    /// `nil` when either input is non-positive.
    static func impliedHeightInches(weightLbs: Double, bmi: Double) -> Double? {
        guard weightLbs > 0, bmi > 0 else { return nil }
        return (703 * weightLbs / bmi).squareRoot()
    }

    /// BMI for a weight at a fixed height, via `BMI = 703 × lbs / in²`. Returns
    /// `nil` for a non-positive height.
    static func bmi(weightLbs: Double, heightInches: Double) -> Double? {
        guard heightInches > 0 else { return nil }
        return 703 * weightLbs / (heightInches * heightInches)
    }

    /// Pair derived BMI with same-night breathing disturbances. The stored
    /// `referenceBMI` is assumed to describe `referenceWeightLbs` (the user's
    /// latest weigh-in); that anchors a constant height which converts every
    /// historical `BodyEntry.weightLbs` into a BMI. Each breathing-disturbance
    /// night is matched to the most recent weigh-in on or before it (weight is a
    /// slow-moving baseline), so nights before the first weigh-in are dropped.
    static func bmiBreathingCorrelation(
        bodyEntries: [BodyEntry],
        healthMetrics: [HealthMetricEntry],
        referenceBMI: Double?,
        referenceWeightLbs: Double?
    ) -> [BMIBreathingDataPoint] {
        guard let referenceBMI, let referenceWeightLbs,
              let heightInches = impliedHeightInches(weightLbs: referenceWeightLbs, bmi: referenceBMI)
        else { return [] }

        let weighIns = bodyEntries
            .compactMap { entry in entry.weightLbs.map { (date: entry.date, weight: $0) } }
            .sorted { $0.date < $1.date }
        guard !weighIns.isEmpty else { return [] }

        let nights = healthMetrics
            .compactMap { metric in metric.breathingDisturbances.map { (date: metric.date, disturbances: $0) } }
            .sorted { $0.date < $1.date }

        return nights.compactMap { night -> BMIBreathingDataPoint? in
            // "YYYY-MM-DD" sorts lexically == chronologically, so the last
            // weigh-in not after the night is the carried-forward weight.
            guard let weight = weighIns.last(where: { $0.date <= night.date })?.weight,
                  let value = bmi(weightLbs: weight, heightInches: heightInches)
            else { return nil }
            return BMIBreathingDataPoint(
                date: night.date,
                bmi: value,
                breathingDisturbances: night.disturbances
            )
        }
    }

    // MARK: - Nicotine → Cardio Recovery

    /// A day's nicotine intake paired with next-day cardio recovery (the bpm
    /// the heart rate drops in the minute after exercise — a higher number means
    /// better cardiovascular fitness).
    struct NicotineCardioRecoveryDataPoint: DatedCorrelationPoint {
        let date: String                   // "YYYY-MM-DD" of the nicotine day
        let nicotineMg: Double             // total nicotine mg that day
        let nextDayCardioRecovery: Double? // HR recovery (bpm) the following day
    }

    /// Build per-day points correlating nicotine intake with next-day cardio
    /// recovery. Nicotine on day N is compared to the cardio-recovery reading on
    /// day N+1, analogous to `alcoholSleepCorrelation`.
    static func nicotineCardioRecoveryCorrelation(
        entries: [NicotineEntry],
        healthMetrics: [HealthMetricEntry]
    ) -> [NicotineCardioRecoveryDataPoint] {
        nextDayPairing(
            causes: entries,
            causeDate: \.date,
            value: { $0.totalMg },
            healthMetrics: healthMetrics,
            metricIsRelevant: { $0.cardioRecovery != nil }
        ) { dateStr, mg, nextMetrics in
            guard let recovery = nextMetrics?.cardioRecovery else { return nil }

            return NicotineCardioRecoveryDataPoint(
                date: dateStr,
                nicotineMg: mg,
                nextDayCardioRecovery: recovery
            )
        }
    }

    // MARK: - Exercise → Cardio Recovery

    /// One ISO week's training load paired with that week's average cardio
    /// recovery — the fitness-improvement feedback loop. `date` is the
    /// "YYYY-MM-DD" of the week's Monday so the point sorts chronologically and
    /// conforms to `DatedCorrelationPoint`.
    struct ExerciseCardioRecoveryDataPoint: DatedCorrelationPoint {
        let date: String                // "YYYY-MM-DD" of the week start (Monday)
        let weekExerciseMinutes: Double // total exercise minutes logged that week
        let avgCardioRecovery: Double   // mean cardio-recovery (bpm) that week
    }

    /// Bucket health metrics by ISO week (Monday-anchored, via
    /// `HabitEngine.startOfWeek`) and pair each week's total exercise minutes
    /// with that week's average cardio recovery. Weekly aggregation smooths the
    /// day-to-day noise in both signals so a training-load → fitness trend can
    /// emerge; a single recovery reading on a rest day shouldn't anchor a week.
    ///
    /// A week is included only when it has at least one cardio-recovery reading
    /// (so the average is defined). Its exercise load is the sum of that week's
    /// logged exercise minutes — `0` when none were logged, which keeps low-/no-
    /// training weeks as honest low-load contrast points rather than dropping them.
    static func exerciseCardioRecoveryCorrelation(
        healthMetrics: [HealthMetricEntry]
    ) -> [ExerciseCardioRecoveryDataPoint] {
        guard !healthMetrics.isEmpty else { return [] }

        // Collapse to one entry per date first — the rest of the engine treats
        // health metrics as one-per-day (see `nextDayPairing` / `buildCorrelationData`),
        // so a stray duplicate shouldn't double-count a week's exercise or recovery.
        let metricsByDate = Dictionary(grouping: healthMetrics, by: \.date)
            .compactMapValues(\.first)

        var exerciseByWeek: [String: Double] = [:]
        var recoverySumByWeek: [String: Double] = [:]
        var recoveryCountByWeek: [String: Int] = [:]

        for metric in metricsByDate.values {
            guard let day = DateFormatting.dateFromString(metric.date) else { continue }
            let weekStart = DateFormatting.dateString(HabitEngine.startOfWeek(day))
            if let mins = metric.exerciseMinutes {
                exerciseByWeek[weekStart, default: 0] += mins
            }
            if let recovery = metric.cardioRecovery {
                recoverySumByWeek[weekStart, default: 0] += recovery
                recoveryCountByWeek[weekStart, default: 0] += 1
            }
        }

        // Keys exist in `recoveryCountByWeek` only via `+= 1`, so `count` is
        // always ≥ 1 here and `recoverySumByWeek` has the same key — the bind is
        // for the optional subscript, not a real emptiness check.
        return recoveryCountByWeek.compactMap { weekStart, count -> ExerciseCardioRecoveryDataPoint? in
            guard let recoverySum = recoverySumByWeek[weekStart] else { return nil }
            return ExerciseCardioRecoveryDataPoint(
                date: weekStart,
                weekExerciseMinutes: exerciseByWeek[weekStart] ?? 0,
                avgCardioRecovery: recoverySum / Double(count)
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

        let avgHigh = highGroup.compactAverage(\.hr) ?? 0
        let avgLow = lowGroup.compactAverage(\.hr) ?? 0
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

            var totalSteps = 0.0, totalDist = 0.0, totalCycling = 0.0, totalExercise = 0.0
            var totalActiveDist = 0.0
            var totalHRV = 0.0, totalSleep = 0.0, totalDeepPct = 0.0, totalStand = 0.0
            var count = 0.0
            var distCount = 0.0, cyclingCount = 0.0, activeDistCount = 0.0, exerciseCount = 0.0, hrvCount = 0.0
            var sleepCount = 0.0, deepCount = 0.0, standCount = 0.0

            for dayOffset in 1...windowDays {
                guard let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: testDate) else { continue }
                let dayStr = DateFormatting.dateString(day)
                guard let metrics = metricsByDate[dayStr]?.first else { continue }

                totalSteps += metrics.steps ?? 0
                count += 1

                if let d = metrics.walkingDistance { totalDist += d; distCount += 1 }
                if let c = metrics.distanceCycling { totalCycling += c; cyclingCount += 1 }
                // Active distance: per-day total of whatever distance was recorded,
                // counted once per day that had any reading (see field doc above).
                if metrics.walkingDistance != nil || metrics.distanceCycling != nil {
                    totalActiveDist += (metrics.walkingDistance ?? 0) + (metrics.distanceCycling ?? 0)
                    activeDistCount += 1
                }
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
                avgDailyCyclingDistance: cyclingCount > 0 ? totalCycling / cyclingCount : nil,
                avgDailyActiveDistance: activeDistCount > 0 ? totalActiveDist / activeDistCount : nil,
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
