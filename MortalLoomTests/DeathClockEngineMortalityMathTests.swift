import XCTest
@testable import MortalLoom

// MARK: - DeathClockEngine Mortality-Math Tests
//
// Targeted coverage for high-stakes mortality branches that the existing
// DeathClockEngineTests / LocationEngineTests suites left untested (issue #42):
//   • educationImpact / incomeImpact — every enum case directly
//   • socioeconomicImpact — a positive half-and-round case (the branches live in LocationEngineTests)
//   • calculateLEVResult — on-track, off-track, and the 5-year (not 10-year) healthy window
//   • healthMetricsAdjustment — empty, single-factor paths, combined, and the [-6,+4] clamp
//   • bmiImpact — the underweight branch (only the 18.5 boundary was pinned before)
//   • sleepImpact — the optimal-ceiling boundaries (9.1 and 6.9)

final class DeathClockEngineMortalityMathTests: XCTestCase {

    /// Fixed "now" so calculateLEVResult math is deterministic across runs.
    private let testNow = DeathClockEngine.dateFromString("2025-01-01")!

    // MARK: educationImpact — every EducationLevel case

    func testEducationImpactNilIsNeutral() {
        XCTAssertEqual(DeathClockEngine.educationImpact(nil), 0.0)
    }

    func testEducationImpactAllCases() {
        XCTAssertEqual(DeathClockEngine.educationImpact(.graduate), 2.0)
        XCTAssertEqual(DeathClockEngine.educationImpact(.bachelors), 1.0)
        XCTAssertEqual(DeathClockEngine.educationImpact(.someCollege), 0.0)
        XCTAssertEqual(DeathClockEngine.educationImpact(.highSchool), -1.0)
        XCTAssertEqual(DeathClockEngine.educationImpact(.noHighSchool), -2.5)
    }

    // MARK: incomeImpact — every IncomeBracket case

    func testIncomeImpactNilIsNeutral() {
        XCTAssertEqual(DeathClockEngine.incomeImpact(nil), 0.0)
    }

    func testIncomeImpactAllCases() {
        XCTAssertEqual(DeathClockEngine.incomeImpact(.q5), 2.5)
        XCTAssertEqual(DeathClockEngine.incomeImpact(.q4), 1.0)
        XCTAssertEqual(DeathClockEngine.incomeImpact(.q3), 0.0)
        XCTAssertEqual(DeathClockEngine.incomeImpact(.q2), -1.5)
        XCTAssertEqual(DeathClockEngine.incomeImpact(.q1), -3.5)
    }

    // MARK: socioeconomicImpact — single-dimension (positive-rounding) path
    //
    // LocationEngineTests already covers socioeconomicImpact's branches (nil,
    // both-nil, education-only, income-only, both-present averaging, and the
    // reachable extremes). This adds only the positive half-and-round case
    // (q5 → 1.25 → 1.3) that complements the existing negative one (q1 → -1.8);
    // the per-case educationImpact/incomeImpact assertions above are the new
    // coverage this file contributes.

    func testSocioeconomicImpactOnlyIncomeHalvedAgainstNeutralEducation() {
        // q5 (+2.5), education missing → treated as 0 → avg = 1.25 → rounds to 1.3
        let profile = SocioeconomicProfile(education: nil, incomeBracket: .q5)
        XCTAssertEqual(DeathClockEngine.socioeconomicImpact(profile), 1.3, accuracy: 0.001)
    }

    // MARK: calculateLEVResult

    /// Build a minimal standard result with a chosen total life expectancy.
    private func standardResult(total: Double) -> DeathClockEngine.DeathClockResult {
        let le = DeathClockEngine.LifeExpectancy(
            baseline: total,
            genomeAdjusted: total,
            lifestyleAdjustment: 0,
            locationAdjustment: 0,
            healthMetricsAdjustment: 0,
            socioeconomicAdjustment: 0,
            total: total
        )
        return DeathClockEngine.DeathClockResult(
            deathDate: Date(),
            lifeExpectancy: le,
            ageYears: 45,
            yearsRemaining: total - 45,
            healthyYearsRemaining: total - 45,
            percentComplete: 0
        )
    }

    func testCalculateLEVResultOnTrackUsesLEVTargetLifespan() {
        // birthYear 1980 → ageAtLEV = 2045 - 1980 = 65. total (85) ≥ 65 → on track.
        let result = DeathClockEngine.calculateLEVResult(
            standardResult: standardResult(total: 85),
            birthDateStr: "1980-01-01",
            now: testNow
        )
        XCTAssertNotNil(result)
        // LEV total is the hypothetical escape-velocity lifespan (120), not the
        // standard total it was built from.
        XCTAssertEqual(result?.lifeExpectancy.total, 120)
    }

    func testCalculateLEVResultOffTrackReturnsNil() {
        // total (60) < ageAtLEV (65) → not on track for LEV → nil.
        let result = DeathClockEngine.calculateLEVResult(
            standardResult: standardResult(total: 60),
            birthDateStr: "1980-01-01",
            now: testNow
        )
        XCTAssertNil(result)
    }

    func testCalculateLEVResultUsesFiveYearDeclineWindow() throws {
        // LEV uses the smaller 5-year decline window (declineYearsLEV), not the
        // standard 10. healthyYearsRemaining = yearsRemaining - 5, so the gap
        // between the two reported figures must be exactly 5 years.
        let result = DeathClockEngine.calculateLEVResult(
            standardResult: standardResult(total: 85),
            birthDateStr: "1980-01-01",
            now: testNow
        )
        let r = try XCTUnwrap(result)
        XCTAssertEqual(r.yearsRemaining - r.healthyYearsRemaining, 5.0, accuracy: 0.001)
    }

    func testCalculateLEVResultInvalidBirthDateReturnsNil() {
        XCTAssertNil(DeathClockEngine.calculateLEVResult(
            standardResult: standardResult(total: 85),
            birthDateStr: "not-a-date"
        ))
    }

    // MARK: healthMetricsAdjustment

    func testHealthMetricsAdjustmentEmptyIsZero() {
        XCTAssertEqual(DeathClockEngine.healthMetricsAdjustment([], age: 45, sex: .male), 0)
    }

    func testHealthMetricsAdjustmentOnlyCardio() {
        // cardioRecovery 45 bpm → excellent → +2.0; no gait/breathing data.
        let m = [HealthMetricEntry(date: "2025-01-01", cardioRecovery: 45)]
        XCTAssertEqual(DeathClockEngine.healthMetricsAdjustment(m, age: 45, sex: .male), 2.0, accuracy: 0.001)
    }

    func testHealthMetricsAdjustmentOnlyBreathing() {
        // breathingDisturbances 20/hr → moderate apnea → -1.5; no cardio/gait.
        let m = [HealthMetricEntry(date: "2025-01-01", breathingDisturbances: 20)]
        XCTAssertEqual(DeathClockEngine.healthMetricsAdjustment(m, age: 45, sex: .male), -1.5, accuracy: 0.001)
    }

    func testHealthMetricsAdjustmentCombinedFactorsSum() {
        // cardioRecovery 30 (good +1.0) + breathingDisturbances 5 (mild apnea -0.5) = +0.5
        let m = [HealthMetricEntry(date: "2025-01-01", cardioRecovery: 30, breathingDisturbances: 5)]
        XCTAssertEqual(DeathClockEngine.healthMetricsAdjustment(m, age: 45, sex: .male), 0.5, accuracy: 0.001)
    }

    func testHealthMetricsAdjustmentClampsFloorAtMinusSix() {
        // cardio 3 (abnormal -2.0) + walkingSpeed 0.5 m/s @45 (very slow -3.0)
        // + breathingDisturbances 35 (severe apnea -3.0) = -8.0 → clamped to -6.
        let m = [HealthMetricEntry(
            date: "2025-01-01",
            cardioRecovery: 3,
            walkingSpeed: 0.5,
            breathingDisturbances: 35
        )]
        XCTAssertEqual(DeathClockEngine.healthMetricsAdjustment(m, age: 45, sex: .male), -6.0, accuracy: 0.001)
    }

    func testHealthMetricsAdjustmentCeilingIsPlusFour() {
        // cardio 45 (excellent +2.0) + walkingSpeed 1.4 m/s @45 (excellent +2.0) = +4.0,
        // the maximum positive adjustment (== the +4 ceiling).
        let m = [HealthMetricEntry(date: "2025-01-01", cardioRecovery: 45, walkingSpeed: 1.4)]
        XCTAssertEqual(DeathClockEngine.healthMetricsAdjustment(m, age: 45, sex: .male), 4.0, accuracy: 0.001)
    }

    // MARK: bmiImpact — underweight branch (bmi < 18.5)

    func testBMIImpactUnderweight() {
        // The 18.5 normal-band boundary (+0.5) is already covered in MortalLoomTests;
        // this pins the underweight branch (< 18.5 → -1.5) that was untested.
        XCTAssertEqual(DeathClockEngine.bmiImpact(17.0), -1.5)
        XCTAssertEqual(DeathClockEngine.bmiImpact(18.4), -1.5)
    }

    // MARK: sleepImpact — optimal ceiling boundaries

    func testSleepImpactOptimalCeilingBoundaries() {
        // Just outside the 7–9h optimal band but still ≥ 6h minimum → neutral (0),
        // not the +1 optimal bonus. (The 7.0/9.0 band edges are covered in
        // MortalLoomTests; these pin the just-outside ceiling that was untested.)
        XCTAssertEqual(DeathClockEngine.sleepImpact(9.1), 0)
        XCTAssertEqual(DeathClockEngine.sleepImpact(6.9), 0)
    }
}
