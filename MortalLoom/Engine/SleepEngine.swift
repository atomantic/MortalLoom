import Foundation

enum SleepEngine {

    // MARK: - Sleep Duration Rating

    enum DurationRating: String, Sendable {
        case optimal = "Optimal"
        case good = "Good"
        case adequate = "Adequate"
        case short = "Short"
        case veryShort = "Very Short"
        case excessive = "Excessive"

        var color: String {
            switch self {
            case .optimal: return "green"
            case .good: return "blue"
            case .adequate: return "yellow"
            case .short: return "orange"
            case .veryShort, .excessive: return "red"
            }
        }

        var systemImage: String {
            switch self {
            case .optimal: return "moon.stars.fill"
            case .good: return "moon.fill"
            case .adequate: return "moon.haze.fill"
            case .short: return "moon.circle"
            case .veryShort: return "exclamationmark.triangle.fill"
            case .excessive: return "bed.double.fill"
            }
        }
    }

    /// Rate sleep duration based on National Sleep Foundation guidelines.
    /// Adults (26-64): Recommended 7-9h, Appropriate 6-10h
    /// Older adults (65+): Recommended 7-8h, Appropriate 5-9h
    static func rateDuration(_ hours: Double, age: Int) -> DurationRating {
        let isOlder = age >= 65
        if hours < 5 { return .veryShort }
        if hours < 6 { return .short }
        if hours < 7 { return .adequate }
        if hours <= (isOlder ? 8 : 9) { return .optimal }
        if hours <= 10 { return .good }
        return .excessive
    }

    // MARK: - Sleep Consistency Score

    /// Calculate sleep consistency as coefficient of variation (lower = more consistent).
    /// Returns a 0-100 score where 100 = perfectly consistent.
    static func consistencyScore(_ sleepHours: [Double]) -> Double {
        guard sleepHours.count >= 3 else { return 0 }
        let mean = sleepHours.reduce(0, +) / Double(sleepHours.count)
        guard mean > 0 else { return 0 }
        let variance = sleepHours.reduce(0) { $0 + pow($1 - mean, 2) } / Double(sleepHours.count)
        let cv = sqrt(variance) / mean
        // CV of 0 = 100 score, CV of 0.3+ = 0 score
        return max(0, min(100, (1 - cv / 0.3) * 100))
    }

    // MARK: - Daylight → Sleep Consistency Correlation

    /// A sliding-window pairing of daylight exposure and the sleep that
    /// FOLLOWED it. Each point represents `nightsInWindow` consecutive nights
    /// with sleep data, where each night's sleep is paired with daylight
    /// recorded on the prior calendar date (the daytime leading into that
    /// night). `endDate` is the date of the last night in the window;
    /// `avgDaylightMinutes` is the mean daylight reading across those prior
    /// days; `consistency` is the SleepEngine consistency score (0–100) of the
    /// sleep hours in the window.
    /// Note: when source data has gaps, a window of `nightsInWindow`
    /// observations may span MORE than `nightsInWindow` calendar days.
    struct DaylightConsistencyPoint: Sendable, Equatable {
        let endDate: Date
        let avgDaylightMinutes: Double
        let consistency: Double
        let nightsInWindow: Int
    }

    /// Build sliding-window data points correlating outdoor light exposure to
    /// the sleep that followed it. The "→ Sleep" direction matters: HealthKit
    /// keys sleep samples to their END date (the morning after) while it keys
    /// daylight intervals to their START date (the daytime they cover). So
    /// the daylight that *led into* sleep date D is recorded on calendar date
    /// D-1, mirroring the day-N → night-N+1 convention used by
    /// `alcoholSleepCorrelation`. Requires sleepHours on date D AND
    /// daylightMinutes on date D-1; nights missing either signal are skipped
    /// before windowing. Windowing is by COUNT of qualifying nights, not by
    /// calendar span — a `windowNights: 7` window therefore represents the
    /// last 7 nights with both signals, which may span more than 7 calendar
    /// days when readings are missing on intervening dates. `windowNights`
    /// must be ≥3 because `consistencyScore` needs ≥3 nights to be meaningful;
    /// values below that produce an empty result.
    static func daylightConsistencyCorrelation(
        metrics: [HealthMetricEntry],
        windowNights: Int = 7
    ) -> [DaylightConsistencyPoint] {
        guard windowNights >= 3 else { return [] }

        // Deduplicate by calendar date upfront. HealthMetricEntry permits
        // multiple entries per date (e.g., one from an iCloud merge that
        // hasn't been collapsed yet); without this, both the daylight index
        // AND the sleep iteration would double-count the same calendar day,
        // inflating usable.count and biasing the window averages / Pearson r.
        // deduplicatedByDate merges all non-nil fields per date, so we keep
        // both signals when they came from separate entries on the same day.
        let deduped = HealthMetricEntry.deduplicatedByDate(metrics)

        // Index daylight readings by their (now-unique) calendar date for
        // prior-day lookup.
        let daylightByDate: [String: Double] = Dictionary(
            uniqueKeysWithValues: deduped.compactMap { m in
                m.daylightMinutes.map { (m.date, $0) }
            }
        )

        // For each sleep night, find the daylight from the PRIOR calendar day.
        // That's the daytime leading into that sleep — the correct direction
        // for "daylight → sleep".
        let usable: [(date: Date, daylight: Double, sleep: Double)] = deduped
            .compactMap { m in
                guard let sleep = m.sleepHours,
                      let sleepDate = DateFormatting.dateFromString(m.date),
                      let priorDay = Calendar.current.date(byAdding: .day, value: -1, to: sleepDate)
                else { return nil }
                let priorDayStr = DateFormatting.dateString(priorDay)
                guard let daylight = daylightByDate[priorDayStr] else { return nil }
                return (sleepDate, daylight, sleep)
            }
            .sorted { $0.date < $1.date }

        guard usable.count >= windowNights else { return [] }

        var points: [DaylightConsistencyPoint] = []
        points.reserveCapacity(usable.count - windowNights + 1)

        for endIdx in (windowNights - 1)..<usable.count {
            let window = usable[(endIdx - windowNights + 1)...endIdx]
            let avgDaylight = window.map(\.daylight).reduce(0, +) / Double(window.count)
            let score = consistencyScore(window.map(\.sleep))
            points.append(DaylightConsistencyPoint(
                endDate: usable[endIdx].date,
                avgDaylightMinutes: avgDaylight,
                consistency: score,
                nightsInWindow: window.count
            ))
        }

        return points
    }

    /// Pearson correlation coefficient between daylight and consistency across
    /// the provided sliding-window points. Returns nil for <3 points (too few
    /// observations) or when either series has zero variance. Result is clamped
    /// to [-1.0, 1.0] to guard against floating-point overshoot (e.g., a
    /// theoretically-±1.0 series occasionally computes as 1.0000000002, which
    /// would skip past UI thresholds set at exactly ±1.0).
    static func daylightConsistencyCorrelationCoefficient(
        _ points: [DaylightConsistencyPoint]
    ) -> Double? {
        guard points.count >= 3 else { return nil }
        let xs = points.map(\.avgDaylightMinutes)
        let ys = points.map(\.consistency)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0, denX = 0.0, denY = 0.0
        for i in 0..<points.count {
            let dx = xs[i] - meanX
            let dy = ys[i] - meanY
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        guard denX > 0, denY > 0 else { return nil }
        return max(-1.0, min(1.0, num / sqrt(denX * denY)))
    }

    // MARK: - Correlation Strength Bucketing

    /// Bucket a correlation coefficient into a strength + sign category.
    /// Single source of truth for the thresholds shared by SleepView's
    /// interpretation copy and badge color — prevents the two from drifting.
    enum CorrelationStrength: Sendable {
        case strongPositive  //  r ≥ 0.5
        case weakPositive    //  0.2 ≤ r < 0.5
        case none            // -0.2 < r < 0.2
        case weakNegative    // -0.5 < r ≤ -0.2
        case strongNegative  //  r ≤ -0.5
    }

    static func classifyCorrelation(_ r: Double) -> CorrelationStrength {
        if r >= 0.5 { return .strongPositive }
        if r >= 0.2 { return .weakPositive }
        if r > -0.2 { return .none }
        if r > -0.5 { return .weakNegative }
        return .strongNegative
    }

    // MARK: - 7-Day and 30-Day Averages

    /// Calculate rolling average from daily sleep values, most recent N days.
    static func rollingAverage(_ values: [Double], days: Int) -> Double? {
        guard !values.isEmpty else { return nil }
        let subset = Array(values.suffix(days))
        return subset.reduce(0, +) / Double(subset.count)
    }

    // MARK: - Sleep Debt

    /// Cumulative sleep debt vs recommended 7-9h (target: 8h) over the given period.
    /// Negative = debt, positive = surplus.
    static func sleepDebt(_ sleepHours: [Double], targetHours: Double = 8.0) -> Double {
        sleepHours.reduce(0) { $0 + ($1 - targetHours) }
    }

    // MARK: - Longevity Impact

    /// Estimate life expectancy impact based on habitual sleep duration.
    /// Research: Sleeping <6h or >9h associated with increased all-cause mortality.
    /// Cappuccio et al., Sleep 2010 meta-analysis:
    ///   Short sleep (<6h): 12% increased mortality risk (~-1.5 years)
    ///   Long sleep (>9h): 30% increased mortality risk (~-2.0 years)
    ///   Optimal (7-8h): reference (baseline)
    static func longevityImpact(averageHours: Double) -> Double {
        switch averageHours {
        case ..<5: return -3.0
        case 5..<6: return -1.5
        case 6..<7: return -0.5
        case 7...8: return 1.0
        case 8..<9: return 0.5
        case 9..<10: return -1.0
        default: return -2.0
        }
    }

    // MARK: - Sleep Stage Analysis

    /// Sleep stage quality rating.
    /// Adults should get ~20% deep sleep and ~20-25% REM per night.
    enum StageQuality: String, Sendable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"

        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "yellow"
            case .poor: return "red"
            }
        }
    }

    /// Rate deep sleep quality based on percentage of total sleep.
    /// Ideal: 15-25% deep sleep. Below 10% is concerning for cognitive health.
    static func rateDeepSleep(deepPct: Double) -> StageQuality {
        if deepPct >= 20 { return .excellent }
        if deepPct >= 15 { return .good }
        if deepPct >= 10 { return .fair }
        return .poor
    }

    /// Rate REM sleep quality based on percentage of total sleep.
    /// Ideal: 20-25% REM. Below 15% is concerning for emotional/cardiovascular health.
    static func rateRemSleep(remPct: Double) -> StageQuality {
        if remPct >= 22 { return .excellent }
        if remPct >= 18 { return .good }
        if remPct >= 13 { return .fair }
        return .poor
    }

    struct SleepStageBreakdown: Sendable {
        let avgDeepHours: Double
        let avgRemHours: Double
        let avgCoreHours: Double
        let deepPct: Double
        let remPct: Double
        let corePct: Double
        let deepQuality: StageQuality
        let remQuality: StageQuality
        let totalNights: Int
    }

    /// Summarize sleep stages from health metrics that have stage data.
    static func stageBreakdown(metrics: [HealthMetricEntry]) -> SleepStageBreakdown? {
        let withStages = metrics.filter { $0.sleepDeepHours != nil || $0.sleepRemHours != nil }
        guard !withStages.isEmpty else { return nil }

        let deepVals = withStages.compactMap(\.sleepDeepHours)
        let remVals = withStages.compactMap(\.sleepRemHours)
        let coreVals = withStages.compactMap(\.sleepCoreHours)
        let totalVals = withStages.compactMap(\.sleepHours)

        let avgDeep = deepVals.isEmpty ? 0 : deepVals.reduce(0, +) / Double(deepVals.count)
        let avgRem = remVals.isEmpty ? 0 : remVals.reduce(0, +) / Double(remVals.count)
        let avgCore = coreVals.isEmpty ? 0 : coreVals.reduce(0, +) / Double(coreVals.count)
        let avgTotal = totalVals.isEmpty ? 1 : totalVals.reduce(0, +) / Double(totalVals.count)

        let deepPct = avgTotal > 0 ? (avgDeep / avgTotal) * 100 : 0
        let remPct = avgTotal > 0 ? (avgRem / avgTotal) * 100 : 0
        let corePct = avgTotal > 0 ? (avgCore / avgTotal) * 100 : 0

        return SleepStageBreakdown(
            avgDeepHours: avgDeep,
            avgRemHours: avgRem,
            avgCoreHours: avgCore,
            deepPct: deepPct,
            remPct: remPct,
            corePct: corePct,
            deepQuality: rateDeepSleep(deepPct: deepPct),
            remQuality: rateRemSleep(remPct: remPct),
            totalNights: withStages.count
        )
    }

    // MARK: - Breathing Disturbances (Apnea Risk)

    enum ApneaRisk: String, Sendable {
        case normal = "Normal"
        case mild = "Mild"
        case moderate = "Moderate"
        case severe = "Severe"

        var color: String {
            switch self {
            case .normal: return "green"
            case .mild: return "yellow"
            case .moderate: return "orange"
            case .severe: return "red"
            }
        }

        var systemImage: String {
            switch self {
            case .normal: return "lungs.fill"
            case .mild: return "lungs"
            case .moderate: return "exclamationmark.triangle"
            case .severe: return "exclamationmark.triangle.fill"
            }
        }
    }

    /// Classify breathing disturbance index (events/hour) into AHI severity.
    /// AHI thresholds: <5 normal, 5-15 mild, 15-30 moderate, >30 severe.
    static func classifyApneaRisk(_ eventsPerHour: Double) -> ApneaRisk {
        if eventsPerHour < 5 { return .normal }
        if eventsPerHour < 15 { return .mild }
        if eventsPerHour < 30 { return .moderate }
        return .severe
    }

    /// Apnea risk longevity impact (years).
    /// Untreated moderate-to-severe apnea: 2-3x cardiovascular mortality risk.
    static func apneaLongevityImpact(_ eventsPerHour: Double) -> Double {
        switch classifyApneaRisk(eventsPerHour) {
        case .normal: return 0
        case .mild: return -0.5
        case .moderate: return -1.5
        case .severe: return -3.0
        }
    }

    // MARK: - Enhanced Longevity Impact (with stages)

    /// Adjusted sleep longevity impact that accounts for stage quality.
    /// Poor deep sleep or REM can reduce the benefit of adequate total hours.
    static func enhancedLongevityImpact(averageHours: Double, stageBreakdown: SleepStageBreakdown?) -> Double {
        var base = longevityImpact(averageHours: averageHours)
        guard let stages = stageBreakdown else { return base }

        // Penalize consistently poor deep sleep
        switch stages.deepQuality {
        case .excellent: base += 0.3
        case .good: break
        case .fair: base -= 0.3
        case .poor: base -= 0.7
        }

        // Penalize poor REM
        switch stages.remQuality {
        case .excellent: base += 0.2
        case .good: break
        case .fair: base -= 0.2
        case .poor: base -= 0.5
        }

        return max(-4.0, min(2.0, base))
    }

    // MARK: - Sleep Quality Summary

    struct SleepSummary: Sendable {
        let averageDuration: Double
        let avg7Day: Double?
        let avg30Day: Double?
        let consistency: Double
        let debt: Double
        let rating: DurationRating
        let longevityYears: Double
        let totalNights: Int
        let stageBreakdown: SleepStageBreakdown?
        let apneaRisk: ApneaRisk?
        let avgBreathingDisturbances: Double?
    }

    /// Compute a full sleep summary from daily sleep hours and user age.
    static func summarize(sleepHours: [Double], age: Int, metrics: [HealthMetricEntry] = []) -> SleepSummary {
        let avg = sleepHours.isEmpty ? 0 : sleepHours.reduce(0, +) / Double(sleepHours.count)
        let stages = stageBreakdown(metrics: metrics)
        let longevity = enhancedLongevityImpact(averageHours: avg, stageBreakdown: stages)

        let bdValues = metrics.compactMap(\.breathingDisturbances)
        let avgBD = bdValues.isEmpty ? nil : bdValues.reduce(0, +) / Double(bdValues.count)
        let apnea = avgBD.map { classifyApneaRisk($0) }

        return SleepSummary(
            averageDuration: avg,
            avg7Day: rollingAverage(sleepHours, days: 7),
            avg30Day: rollingAverage(sleepHours, days: 30),
            consistency: consistencyScore(sleepHours),
            debt: sleepDebt(sleepHours),
            rating: rateDuration(avg, age: age),
            longevityYears: longevity,
            totalNights: sleepHours.count,
            stageBreakdown: stages,
            apneaRisk: apnea,
            avgBreathingDisturbances: avgBD
        )
    }
}
