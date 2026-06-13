import Foundation

enum GaitEngine {

    // MARK: - Walking Speed Classification

    /// Functional fitness based on walking speed.
    /// Walking speed is called "the 6th vital sign" — a strong independent predictor of mortality.
    /// Studenski et al., JAMA 2011: Each 0.1 m/s increase in gait speed = 12% lower mortality.
    enum WalkingSpeedLevel: String, Sendable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case slow = "Slow"
        case verySlow = "Very Slow"

        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "yellow"
            case .slow: return "orange"
            case .verySlow: return "red"
            }
        }

        var systemImage: String {
            switch self {
            case .excellent: return "figure.walk.motion"
            case .good: return "figure.walk"
            case .fair: return "figure.stand"
            case .slow: return "exclamationmark.triangle"
            case .verySlow: return "exclamationmark.triangle.fill"
            }
        }
    }

    /// Classify walking speed (m/s). Age-adjusted thresholds.
    /// Normal range: 1.0-1.4 m/s for healthy adults.
    /// <0.8 m/s is associated with significantly increased mortality.
    static func classifyWalkingSpeed(_ metersPerSec: Double, age: Int) -> WalkingSpeedLevel {
        let offset: Double = age >= 65 ? -0.15 : 0
        let adjusted = metersPerSec - offset
        if adjusted >= 1.3 { return .excellent }
        if adjusted >= 1.1 { return .good }
        if adjusted >= 0.9 { return .fair }
        if adjusted >= 0.7 { return .slow }
        return .verySlow
    }

    // MARK: - Fall Risk Assessment

    enum FallRisk: String, Sendable {
        case low = "Low"
        case moderate = "Moderate"
        case elevated = "Elevated"
        case high = "High"

        var color: String {
            switch self {
            case .low: return "green"
            case .moderate: return "yellow"
            case .elevated: return "orange"
            case .high: return "red"
            }
        }
    }

    /// Assess fall risk from gait asymmetry and double support percentage.
    /// Higher asymmetry (>5%) and higher double support (>30%) indicate increased fall risk.
    static func assessFallRisk(asymmetry: Double?, doubleSupport: Double?) -> FallRisk {
        var score = 0
        if let a = asymmetry {
            if a > 10 { score += 3 }
            else if a > 5 { score += 2 }
            else if a > 3 { score += 1 }
        }
        if let ds = doubleSupport {
            if ds > 35 { score += 3 }
            else if ds > 30 { score += 2 }
            else if ds > 27 { score += 1 }
        }
        if score >= 5 { return .high }
        if score >= 3 { return .elevated }
        if score >= 1 { return .moderate }
        return .low
    }

    // MARK: - Longevity Impact

    /// Walking speed longevity impact (years).
    /// Studenski et al., JAMA 2011: survival increases ~12% per 0.1 m/s above reference.
    static func walkingSpeedLongevityImpact(_ metersPerSec: Double, age: Int) -> Double {
        let level = classifyWalkingSpeed(metersPerSec, age: age)
        switch level {
        case .excellent: return 2.0
        case .good: return 1.0
        case .fair: return 0.0
        case .slow: return -1.5
        case .verySlow: return -3.0
        }
    }

    // MARK: - Gait Summary

    struct GaitSummary: Sendable {
        let avgWalkingSpeed: Double?
        let avgWalkingDistance: Double?
        let avgAsymmetry: Double?
        let avgDoubleSupport: Double?
        let speedLevel: WalkingSpeedLevel?
        let fallRisk: FallRisk
        let longevityYears: Double?
    }

    /// Build a gait summary from recent health metrics.
    static func summarize(metrics: [HealthMetricEntry], age: Int) -> GaitSummary {
        let avgSpeed = metrics.compactAverage(\.walkingSpeed)
        let avgDist = metrics.compactAverage(\.walkingDistance)
        let avgAsym = metrics.compactAverage(\.walkingAsymmetry)
        let avgDS = metrics.compactAverage(\.walkingDoubleSupport)

        let speedLevel = avgSpeed.map { classifyWalkingSpeed($0, age: age) }
        let fallRisk = assessFallRisk(asymmetry: avgAsym, doubleSupport: avgDS)
        let longevity = avgSpeed.map { walkingSpeedLongevityImpact($0, age: age) }

        return GaitSummary(
            avgWalkingSpeed: avgSpeed,
            avgWalkingDistance: avgDist,
            avgAsymmetry: avgAsym,
            avgDoubleSupport: avgDS,
            speedLevel: speedLevel,
            fallRisk: fallRisk,
            longevityYears: longevity
        )
    }
}
