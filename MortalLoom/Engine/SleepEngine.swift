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
