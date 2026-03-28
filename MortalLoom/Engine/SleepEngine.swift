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
        if hours < 6 { return isOlder ? .short : .short }
        if hours < 7 { return isOlder ? .adequate : .adequate }
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
    }

    /// Compute a full sleep summary from daily sleep hours and user age.
    static func summarize(sleepHours: [Double], age: Int) -> SleepSummary {
        let avg = sleepHours.isEmpty ? 0 : sleepHours.reduce(0, +) / Double(sleepHours.count)
        return SleepSummary(
            averageDuration: avg,
            avg7Day: rollingAverage(sleepHours, days: 7),
            avg30Day: rollingAverage(sleepHours, days: 30),
            consistency: consistencyScore(sleepHours),
            debt: sleepDebt(sleepHours),
            rating: rateDuration(avg, age: age),
            longevityYears: longevityImpact(averageHours: avg),
            totalNights: sleepHours.count
        )
    }
}
