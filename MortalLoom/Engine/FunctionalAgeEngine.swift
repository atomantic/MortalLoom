import Foundation

// MARK: - Functional Age Engine
//
// Synthesizes mobility biomarkers — comfortable walking speed, stair ascent/descent
// speed, and gait asymmetry — into a single age-adjusted "functional age" estimate:
// roughly, the chronological age at which the user's measured mobility would be
// considered typical.
//
// The core idea: gait speed is a validated functional biomarker whose age-normative
// value plateaus through midlife then declines predictably (Bohannon & Williams
// Andrews, Physiotherapy 2011; Studenski et al., JAMA 2011). We compare the measured
// speed to the speed *expected at the user's own age* and convert the surplus/deficit
// into years: walking exactly the age-normal speed reads as on par (functional age ≈
// chronological age), faster reads younger, slower reads older. This age-relative
// framing matters because the curve is flat below the anchor age — a healthy
// 30-year-old at the plateau speed must read as ~30, not penalized to the anchor age.
// Stair speed is treated the same way (it declines faster than level-ground gait
// because it loads lower-limb power, which falls off more steeply with age).
// Asymmetry is a modifier, not an absolute-age source: higher gait asymmetry ages the
// estimate, lower asymmetry rejuvenates it slightly.
//
// All thresholds are heuristic estimates derived from the cited normative data, not
// a clinical instrument — the value is the *relative* delta (younger vs. older than
// your years), surfaced to motivate mobility-preserving behavior.

enum FunctionalAgeEngine {

    // MARK: - Normative model anchors

    /// Age at which the gait/stair speed curves are anchored (the plateau before
    /// age-related decline begins, per Bohannon 2011).
    static let anchorAge: Double = 50

    /// Comfortable walking speed (m/s) at `anchorAge`, and its per-year decline.
    /// Bohannon 2011: pooled comfortable gait speed ≈ 1.40 m/s through midlife,
    /// declining ~0.012 m/s per year thereafter.
    static let anchorWalkingSpeed: Double = 1.40
    static let walkingSpeedDeclinePerYear: Double = 0.012

    /// Stair (ascent/descent) speed (m/s) at `anchorAge`, and its per-year decline.
    /// Stair speed reflects lower-limb power, which declines faster with age than
    /// level-ground gait speed — hence a steeper per-year slope on a lower anchor.
    static let anchorStairSpeed: Double = 0.50
    static let stairSpeedDeclinePerYear: Double = 0.005

    /// Gait asymmetry (%) considered functionally neutral; deviations adjust the
    /// estimate by `asymmetryYearsPerPercent` years per percentage point.
    static let neutralAsymmetry: Double = 4.0
    static let asymmetryYearsPerPercent: Double = 1.0

    // MARK: - Age-normative expected speeds

    /// Age-normative comfortable walking speed (m/s): flat at the plateau through the
    /// anchor age, then declining linearly. Bohannon 2011 finds gait speed roughly
    /// constant through midlife, so below `anchorAge` the expectation is the plateau —
    /// not an extrapolated "faster than plateau" value that would penalize the young.
    static func expectedWalkingSpeed(age: Int) -> Double {
        let years = Double(age)
        guard years > anchorAge else { return anchorWalkingSpeed }
        return anchorWalkingSpeed - (years - anchorAge) * walkingSpeedDeclinePerYear
    }

    /// Age-normative stair speed (m/s), same plateau-then-decline shape as walking.
    static func expectedStairSpeed(age: Int) -> Double {
        let years = Double(age)
        guard years > anchorAge else { return anchorStairSpeed }
        return anchorStairSpeed - (years - anchorAge) * stairSpeedDeclinePerYear
    }

    // MARK: - Component estimates

    /// Functional age implied by a comfortable walking speed (m/s), relative to the
    /// speed expected at `chronologicalAge`: walking the age-normal speed reads as the
    /// user's own age, each `walkingSpeedDeclinePerYear` of surplus reads one year
    /// younger (deficit one year older). Clamped to a plausible adult range.
    static func functionalAgeFromWalkingSpeed(_ metersPerSec: Double, chronologicalAge: Int) -> Double {
        let deficit = expectedWalkingSpeed(age: chronologicalAge) - metersPerSec
        return clampAge(Double(chronologicalAge) + deficit / walkingSpeedDeclinePerYear)
    }

    /// Functional age implied by an average stair speed (m/s), relative to the speed
    /// expected at `chronologicalAge`.
    static func functionalAgeFromStairSpeed(_ metersPerSec: Double, chronologicalAge: Int) -> Double {
        let deficit = expectedStairSpeed(age: chronologicalAge) - metersPerSec
        return clampAge(Double(chronologicalAge) + deficit / stairSpeedDeclinePerYear)
    }

    /// Years to add (positive) or subtract (negative) from the speed-derived
    /// estimate based on gait asymmetry. Higher asymmetry ages the estimate.
    /// Bounded so a single noisy metric can't dominate the synthesis.
    static func asymmetryAgeAdjustment(_ asymmetryPercent: Double) -> Double {
        let raw = (asymmetryPercent - neutralAsymmetry) * asymmetryYearsPerPercent
        return min(10, max(-5, raw))
    }

    private static func clampAge(_ age: Double) -> Double {
        min(110, max(18, age))
    }

    // MARK: - Classification

    /// How the functional-age estimate compares to chronological age.
    enum AgeGapLevel: String, Sendable {
        case youthful = "Youthful"
        case younger = "Younger"
        case onPar = "On Par"
        case older = "Older"
        case accelerated = "Accelerated"

        var color: String {
            switch self {
            case .youthful: return "green"
            case .younger: return "blue"
            case .onPar: return "yellow"
            case .older: return "orange"
            case .accelerated: return "red"
            }
        }

        var systemImage: String {
            switch self {
            case .youthful: return "figure.run"
            case .younger: return "figure.walk.motion"
            case .onPar: return "figure.walk"
            case .older: return "figure.walk.arrival"
            case .accelerated: return "exclamationmark.triangle.fill"
            }
        }
    }

    /// Map the gap (functional − chronological, in years) to a level.
    /// Negative gaps mean mobility younger than the user's years.
    static func classify(gapYears: Double) -> AgeGapLevel {
        if gapYears <= -7 { return .youthful }
        if gapYears <= -3 { return .younger }
        if gapYears < 3 { return .onPar }
        if gapYears < 7 { return .older }
        return .accelerated
    }

    // MARK: - Synthesis

    struct FunctionalAgeSummary: Sendable {
        let chronologicalAge: Int
        let functionalAge: Double
        /// functionalAge − chronologicalAge. Negative = younger than your years.
        let gapYears: Double
        let level: AgeGapLevel
        /// Number of absolute-age domains that contributed (walking speed, stair speed).
        let componentCount: Int
        /// Averaged stair speed (ascent/descent combined), surfaced for context.
        let avgStairSpeed: Double?
    }

    /// Build a functional-age estimate from individual biomarker averages.
    /// Returns `nil` when no absolute-age domain (walking or stair speed) is
    /// available — asymmetry alone is only a modifier and can't anchor an age —
    /// or when `chronologicalAge` is unknown (≤ 0, e.g. birth date not yet set):
    /// an *age-adjusted* estimate is meaningless without a real reference age.
    static func estimate(
        walkingSpeed: Double?,
        stairSpeedUp: Double?,
        stairSpeedDown: Double?,
        asymmetry: Double?,
        chronologicalAge: Int
    ) -> FunctionalAgeSummary? {
        guard chronologicalAge > 0 else { return nil }

        var componentAges: [Double] = []

        if let speed = walkingSpeed {
            componentAges.append(functionalAgeFromWalkingSpeed(speed, chronologicalAge: chronologicalAge))
        }

        let avgStair = [stairSpeedUp, stairSpeedDown].compactAverage(\.self)
        if let stair = avgStair {
            componentAges.append(functionalAgeFromStairSpeed(stair, chronologicalAge: chronologicalAge))
        }

        guard !componentAges.isEmpty else { return nil }

        let base = componentAges.reduce(0, +) / Double(componentAges.count)
        let adjustment = asymmetry.map(asymmetryAgeAdjustment) ?? 0
        let estimated = base + adjustment

        // Keep the estimate within ±25 years of chronological age — a single decade's
        // worth of biomarker noise shouldn't claim someone is 30 years younger/older —
        // then clamp to the plausible adult range.
        let chrono = Double(chronologicalAge)
        let withinChronoBounds = min(chrono + 25, max(chrono - 25, estimated))
        // Round to a whole year: sub-year precision is false given the heuristic,
        // and rounding here keeps the displayed age and the displayed gap consistent
        // (gap is derived from this same rounded value).
        let functionalAge = clampAge(withinChronoBounds).rounded()
        let gap = functionalAge - chrono

        return FunctionalAgeSummary(
            chronologicalAge: chronologicalAge,
            functionalAge: functionalAge,
            gapYears: gap,
            level: classify(gapYears: gap),
            componentCount: componentAges.count,
            avgStairSpeed: avgStair
        )
    }

    /// Build a functional-age estimate from recent health metrics by averaging each
    /// biomarker across the supplied entries (nils ignored per field).
    static func summarize(metrics: [HealthMetricEntry], age: Int) -> FunctionalAgeSummary? {
        estimate(
            walkingSpeed: metrics.compactAverage(\.walkingSpeed),
            stairSpeedUp: metrics.compactAverage(\.stairSpeedUp),
            stairSpeedDown: metrics.compactAverage(\.stairSpeedDown),
            asymmetry: metrics.compactAverage(\.walkingAsymmetry),
            chronologicalAge: age
        )
    }
}
