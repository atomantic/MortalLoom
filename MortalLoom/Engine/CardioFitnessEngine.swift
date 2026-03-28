import Foundation

enum CardioFitnessEngine {

    // MARK: - VO2 Max Fitness Classification

    /// ACSM fitness classifications based on VO2 max (mL/kg/min), age, and sex.
    /// Source: American College of Sports Medicine Guidelines for Exercise Testing
    enum FitnessLevel: String, Sendable {
        case superior = "Superior"
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case veryPoor = "Very Poor"

        var color: String {
            switch self {
            case .superior, .excellent: return "green"
            case .good: return "blue"
            case .fair: return "yellow"
            case .poor: return "orange"
            case .veryPoor: return "red"
            }
        }

        var systemImage: String {
            switch self {
            case .superior: return "star.fill"
            case .excellent: return "checkmark.seal.fill"
            case .good: return "hand.thumbsup.fill"
            case .fair: return "minus.circle.fill"
            case .poor: return "exclamationmark.triangle.fill"
            case .veryPoor: return "xmark.circle.fill"
            }
        }
    }

    /// Classify VO2 max fitness level using ACSM percentile-based thresholds.
    /// Male thresholds (mL/kg/min) by age decade:
    ///   20-29: Superior >=52, Excellent >=47, Good >=43, Fair >=39, Poor >=34, Very Poor <34
    ///   30-39: Superior >=49, Excellent >=44, Good >=40, Fair >=36, Poor >=31, Very Poor <31
    ///   40-49: Superior >=46, Excellent >=41, Good >=37, Fair >=33, Poor >=28, Very Poor <28
    ///   50-59: Superior >=43, Excellent >=38, Good >=34, Fair >=30, Poor >=25, Very Poor <25
    ///   60-69: Superior >=40, Excellent >=35, Good >=31, Fair >=27, Poor >=22, Very Poor <22
    ///   70+:   Superior >=37, Excellent >=32, Good >=28, Fair >=24, Poor >=20, Very Poor <20
    /// Female thresholds are offset ~8-10 mL/kg/min lower.
    static func classifyVO2Max(_ vo2max: Double, age: Int, sex: BiologicalSex?) -> FitnessLevel {
        let thresholds: [Double] // [superior, excellent, good, fair, poor] cutoffs
        let isMale = sex != .female

        if isMale {
            switch age {
            case ..<30: thresholds = [52, 47, 43, 39, 34]
            case 30..<40: thresholds = [49, 44, 40, 36, 31]
            case 40..<50: thresholds = [46, 41, 37, 33, 28]
            case 50..<60: thresholds = [43, 38, 34, 30, 25]
            case 60..<70: thresholds = [40, 35, 31, 27, 22]
            default: thresholds = [37, 32, 28, 24, 20]
            }
        } else {
            switch age {
            case ..<30: thresholds = [44, 39, 35, 31, 26]
            case 30..<40: thresholds = [41, 36, 32, 28, 23]
            case 40..<50: thresholds = [38, 33, 29, 25, 20]
            case 50..<60: thresholds = [35, 30, 26, 22, 18]
            case 60..<70: thresholds = [32, 27, 23, 19, 16]
            default: thresholds = [29, 24, 20, 17, 14]
            }
        }

        if vo2max >= thresholds[0] { return .superior }
        if vo2max >= thresholds[1] { return .excellent }
        if vo2max >= thresholds[2] { return .good }
        if vo2max >= thresholds[3] { return .fair }
        if vo2max >= thresholds[4] { return .poor }
        return .veryPoor
    }

    // MARK: - Resting Heart Rate Classification

    enum HeartRateZone: String, Sendable {
        case athlete = "Athlete"
        case excellent = "Excellent"
        case good = "Good"
        case aboveAverage = "Above Average"
        case average = "Average"
        case belowAverage = "Below Average"
        case poor = "Poor"

        var color: String {
            switch self {
            case .athlete, .excellent: return "green"
            case .good, .aboveAverage: return "blue"
            case .average: return "yellow"
            case .belowAverage: return "orange"
            case .poor: return "red"
            }
        }
    }

    /// Classify resting heart rate. General adult ranges.
    static func classifyRestingHR(_ bpm: Double) -> HeartRateZone {
        switch bpm {
        case ..<50: return .athlete
        case 50..<60: return .excellent
        case 60..<65: return .good
        case 65..<70: return .aboveAverage
        case 70..<80: return .average
        case 80..<90: return .belowAverage
        default: return .poor
        }
    }

    // MARK: - HRV Interpretation

    enum HRVLevel: String, Sendable {
        case high = "High"
        case aboveAverage = "Above Average"
        case average = "Average"
        case belowAverage = "Below Average"
        case low = "Low"

        var color: String {
            switch self {
            case .high, .aboveAverage: return "green"
            case .average: return "blue"
            case .belowAverage: return "orange"
            case .low: return "red"
            }
        }
    }

    /// Classify HRV (SDNN in ms). Age-adjusted thresholds.
    /// HRV naturally declines with age; a 50ms SDNN is normal for a 60yo but low for a 25yo.
    static func classifyHRV(_ sdnn: Double, age: Int) -> HRVLevel {
        let thresholds: [Double] // [high, aboveAverage, average, belowAverage] cutoffs
        switch age {
        case ..<30: thresholds = [80, 60, 40, 25]
        case 30..<40: thresholds = [70, 50, 35, 20]
        case 40..<50: thresholds = [60, 40, 28, 18]
        case 50..<60: thresholds = [50, 35, 22, 15]
        case 60..<70: thresholds = [45, 30, 18, 12]
        default: thresholds = [40, 25, 15, 10]
        }

        if sdnn >= thresholds[0] { return .high }
        if sdnn >= thresholds[1] { return .aboveAverage }
        if sdnn >= thresholds[2] { return .average }
        if sdnn >= thresholds[3] { return .belowAverage }
        return .low
    }

    // MARK: - Longevity Impact Summary

    /// Estimate the mortality impact of VO2 max based on published research.
    /// A 1 MET (~3.5 mL/kg/min) increase in fitness is associated with ~15% reduction
    /// in all-cause mortality (Kodama et al., JAMA 2009).
    /// Returns estimated years of life impact relative to "average" fitness.
    static func vo2MaxLongevityImpact(_ vo2max: Double, age: Int, sex: BiologicalSex?) -> Double {
        let level = classifyVO2Max(vo2max, age: age, sex: sex)
        switch level {
        case .superior: return 3.0
        case .excellent: return 2.0
        case .good: return 1.0
        case .fair: return 0.0
        case .poor: return -1.5
        case .veryPoor: return -3.0
        }
    }
}
