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
// IMPORTANT — measurement context: the speeds we receive come from Apple Health
// (HKQuantityTypeIdentifierWalkingSpeed and the stair-speed types), which are
// *everyday, free-living daily averages* captured across all walking — indoors,
// encumbered, on crowded sidewalks, etc. Those run systematically slower than the
// *clinical comfortable gait speed* the Bohannon/Studenski norms were measured from
// (a short, instrumented "walk at your normal pace" course). Comparing a free-living
// average directly against the ~1.40 m/s clinical plateau therefore over-ages almost
// everyone. We correct for this by shifting the age-normative reference down by a
// documented free-living offset (see `freeLivingWalkingOffset`) before comparing, so
// a normal everyday average reads as on par rather than decades older.
//
// All thresholds are heuristic estimates derived from the cited normative data, not
// a clinical instrument — the value is the *relative* delta (younger vs. older than
// your years), surfaced to motivate mobility-preserving behavior. This is a mobility
// proxy: it is NOT a biological or epigenetic (DNA-methylation) age and should not be
// expected to match one — those measure entirely different biology.

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

    /// Free-living correction (m/s) subtracted from the clinical norm before comparing.
    /// Apple Health's everyday walking-speed average runs ~0.2–0.3 m/s below the
    /// clinical comfortable gait speed the norms were measured from; we use the midpoint
    /// so a typical all-day average reads as on par rather than decades older. Stairs
    /// get a smaller offset — the stair-speed types are sampled while actively climbing,
    /// closer to a deliberate pace, so the free-living gap is narrower.
    static let freeLivingWalkingOffset: Double = 0.25
    static let freeLivingStairOffset: Double = 0.05

    // MARK: - Age-normative expected speeds

    /// Age-normative *everyday-equivalent* comfortable walking speed (m/s): the clinical
    /// curve (flat at the plateau through `anchorAge`, then declining linearly — Bohannon
    /// 2011) shifted down by `freeLivingWalkingOffset` so it can be compared to the
    /// free-living daily average Apple Health reports. Below `anchorAge` the expectation
    /// is the plateau — not an extrapolated "faster than plateau" value that would
    /// penalize the young.
    static func expectedWalkingSpeed(age: Int) -> Double {
        let years = Double(age)
        let clinical = years > anchorAge
            ? anchorWalkingSpeed - (years - anchorAge) * walkingSpeedDeclinePerYear
            : anchorWalkingSpeed
        return clinical - freeLivingWalkingOffset
    }

    /// Age-normative everyday-equivalent stair speed (m/s), same plateau-then-decline
    /// shape as walking, shifted down by `freeLivingStairOffset`.
    static func expectedStairSpeed(age: Int) -> Double {
        let years = Double(age)
        let clinical = years > anchorAge
            ? anchorStairSpeed - (years - anchorAge) * stairSpeedDeclinePerYear
            : anchorStairSpeed
        return clinical - freeLivingStairOffset
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

    /// One mobility signal's contribution to the estimate — surfaced so the UI can
    /// explain *why* the functional age is what it is (which signal drove it, and how
    /// the measured speed compares to the age-normal expectation).
    struct Component: Sendable {
        enum Kind: String, Sendable, Hashable {
            case walkingSpeed = "Walking speed"
            case stairSpeed = "Stair speed"
        }
        let kind: Kind
        /// Measured free-living average speed (m/s).
        let measured: Double
        /// Age-normative everyday-equivalent expected speed at the user's age (m/s).
        let expected: Double
        /// Functional age implied by this signal alone (clamped to the adult range, unrounded).
        let impliedAge: Double
        /// impliedAge − chronological age. Positive = this signal reads older than your years.
        let gapYears: Double
    }

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
        /// Per-signal breakdown driving the estimate, for the "why" UI.
        let components: [Component]
        /// Years added (+) or removed (−) by the gait-asymmetry modifier; 0 when no data.
        let asymmetryAdjustment: Double

        /// The signal pushing the estimate hardest in either direction — the headline driver.
        var primaryDriver: Component? {
            components.max(by: { abs($0.gapYears) < abs($1.gapYears) })
        }
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
        let chrono = Double(chronologicalAge)

        var components: [Component] = []

        if let speed = walkingSpeed {
            let implied = functionalAgeFromWalkingSpeed(speed, chronologicalAge: chronologicalAge)
            components.append(Component(
                kind: .walkingSpeed,
                measured: speed,
                expected: expectedWalkingSpeed(age: chronologicalAge),
                impliedAge: implied,
                gapYears: implied - chrono))
        }

        let avgStair = [stairSpeedUp, stairSpeedDown].compactAverage(\.self)
        if let stair = avgStair {
            let implied = functionalAgeFromStairSpeed(stair, chronologicalAge: chronologicalAge)
            components.append(Component(
                kind: .stairSpeed,
                measured: stair,
                expected: expectedStairSpeed(age: chronologicalAge),
                impliedAge: implied,
                gapYears: implied - chrono))
        }

        guard !components.isEmpty else { return nil }

        let base = components.map(\.impliedAge).reduce(0, +) / Double(components.count)
        let adjustment = asymmetry.map(asymmetryAgeAdjustment) ?? 0
        let estimated = base + adjustment

        // Keep the estimate within ±25 years of chronological age — a single decade's
        // worth of biomarker noise shouldn't claim someone is 30 years younger/older —
        // then clamp to the plausible adult range.
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
            componentCount: components.count,
            avgStairSpeed: avgStair,
            components: components,
            asymmetryAdjustment: adjustment
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
