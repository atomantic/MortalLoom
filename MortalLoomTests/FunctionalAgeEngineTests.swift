import XCTest
@testable import MortalLoom

// MARK: - FunctionalAgeEngine Tests
//
// Pure-function tests for the age-normative inversion of walking/stair speed, the
// asymmetry modifier, gap classification, and the metric-aggregating `summarize`.

final class FunctionalAgeEngineTests: XCTestCase {

    // MARK: - Walking-speed inversion

    func testWalkingSpeedAtAnchorMapsToAnchorAge() {
        // Anchor speed (1.40 m/s) should invert to the anchor age (50).
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(1.40), 50, accuracy: 0.0001)
    }

    func testFasterWalkingReadsYounger() {
        // +0.12 m/s above anchor = 10 years younger (0.012 m/s per year).
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(1.52), 40, accuracy: 0.0001)
    }

    func testSlowerWalkingReadsOlder() {
        // -0.12 m/s below anchor = 10 years older.
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(1.28), 60, accuracy: 0.0001)
    }

    func testWalkingSpeedEstimateClampsToAdultRange() {
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(5.0), 18, accuracy: 0.0001)
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(0.0), 110, accuracy: 0.0001)
    }

    // MARK: - Stair-speed inversion

    func testStairSpeedAtAnchorMapsToAnchorAge() {
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromStairSpeed(0.50), 50, accuracy: 0.0001)
    }

    func testStairSpeedSteeperSlope() {
        // 0.005 m/s per year: +0.05 m/s = 10 years younger.
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromStairSpeed(0.55), 40, accuracy: 0.0001)
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromStairSpeed(0.45), 60, accuracy: 0.0001)
    }

    // MARK: - Asymmetry modifier

    func testNeutralAsymmetryNoAdjustment() {
        XCTAssertEqual(FunctionalAgeEngine.asymmetryAgeAdjustment(4.0), 0, accuracy: 0.0001)
    }

    func testHigherAsymmetryAgesEstimate() {
        XCTAssertEqual(FunctionalAgeEngine.asymmetryAgeAdjustment(7.0), 3, accuracy: 0.0001)
    }

    func testLowerAsymmetryRejuvenatesEstimate() {
        XCTAssertEqual(FunctionalAgeEngine.asymmetryAgeAdjustment(2.0), -2, accuracy: 0.0001)
    }

    func testAsymmetryAdjustmentIsBounded() {
        XCTAssertEqual(FunctionalAgeEngine.asymmetryAgeAdjustment(50), 10, accuracy: 0.0001)
        XCTAssertEqual(FunctionalAgeEngine.asymmetryAgeAdjustment(-50), -5, accuracy: 0.0001)
    }

    // MARK: - Gap classification

    func testGapClassificationBoundaries() {
        XCTAssertEqual(FunctionalAgeEngine.classify(gapYears: -8), .youthful)
        XCTAssertEqual(FunctionalAgeEngine.classify(gapYears: -7), .youthful)
        XCTAssertEqual(FunctionalAgeEngine.classify(gapYears: -5), .younger)
        XCTAssertEqual(FunctionalAgeEngine.classify(gapYears: -3), .younger)
        XCTAssertEqual(FunctionalAgeEngine.classify(gapYears: 0), .onPar)
        XCTAssertEqual(FunctionalAgeEngine.classify(gapYears: 2.9), .onPar)
        XCTAssertEqual(FunctionalAgeEngine.classify(gapYears: 3), .older)
        XCTAssertEqual(FunctionalAgeEngine.classify(gapYears: 6.9), .older)
        XCTAssertEqual(FunctionalAgeEngine.classify(gapYears: 7), .accelerated)
    }

    func testAgeGapLevelColorsAreDistinct() {
        let colors = [
            FunctionalAgeEngine.AgeGapLevel.youthful.color,
            FunctionalAgeEngine.AgeGapLevel.younger.color,
            FunctionalAgeEngine.AgeGapLevel.onPar.color,
            FunctionalAgeEngine.AgeGapLevel.older.color,
            FunctionalAgeEngine.AgeGapLevel.accelerated.color
        ]
        XCTAssertEqual(Set(colors).count, colors.count)
    }

    // MARK: - estimate()

    func testEstimateReturnsNilWithoutSpeedDomain() {
        // Asymmetry alone cannot anchor an absolute age.
        XCTAssertNil(FunctionalAgeEngine.estimate(
            walkingSpeed: nil, stairSpeedUp: nil, stairSpeedDown: nil,
            asymmetry: 8, chronologicalAge: 50))
    }

    func testEstimateFromWalkingSpeedOnly() {
        let summary = FunctionalAgeEngine.estimate(
            walkingSpeed: 1.28, stairSpeedUp: nil, stairSpeedDown: nil,
            asymmetry: nil, chronologicalAge: 50)
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.functionalAge ?? .nan, 60, accuracy: 0.0001)
        XCTAssertEqual(summary?.gapYears ?? .nan, 10, accuracy: 0.0001)
        XCTAssertEqual(summary?.componentCount, 1)
        XCTAssertEqual(summary?.level, .accelerated)
    }

    func testEstimateAveragesStairUpAndDown() {
        // Stair up 0.55 (→40) and down 0.45 (→60) average to 0.50 (→50).
        let summary = FunctionalAgeEngine.estimate(
            walkingSpeed: nil, stairSpeedUp: 0.55, stairSpeedDown: 0.45,
            asymmetry: nil, chronologicalAge: 50)
        XCTAssertEqual(summary?.functionalAge ?? .nan, 50, accuracy: 0.0001)
        XCTAssertEqual(summary?.avgStairSpeed ?? .nan, 0.50, accuracy: 0.0001)
        XCTAssertEqual(summary?.componentCount, 1)
    }

    func testEstimateBlendsWalkingAndStairThenAdjustsForAsymmetry() {
        // Walking 1.52 → 40, stair 0.55 → 40; base 40. Asymmetry 7 adds +3 → 43.
        let summary = FunctionalAgeEngine.estimate(
            walkingSpeed: 1.52, stairSpeedUp: 0.55, stairSpeedDown: 0.55,
            asymmetry: 7, chronologicalAge: 50)
        XCTAssertEqual(summary?.functionalAge ?? .nan, 43, accuracy: 0.0001)
        XCTAssertEqual(summary?.componentCount, 2)
        XCTAssertEqual(summary?.gapYears ?? .nan, -7, accuracy: 0.0001)
        XCTAssertEqual(summary?.level, .youthful)
    }

    func testEstimateClampsGapToTwentyFiveYears() {
        // Extremely fast walker would invert far below 18, but the ±25-year guard
        // keeps the estimate within 25 years of chronological age.
        let summary = FunctionalAgeEngine.estimate(
            walkingSpeed: 2.0, stairSpeedUp: nil, stairSpeedDown: nil,
            asymmetry: nil, chronologicalAge: 70)
        XCTAssertEqual(summary?.functionalAge ?? .nan, 45, accuracy: 0.0001)
        XCTAssertEqual(summary?.gapYears ?? .nan, -25, accuracy: 0.0001)
    }

    // MARK: - summarize()

    func testSummarizeEmptyReturnsNil() {
        XCTAssertNil(FunctionalAgeEngine.summarize(metrics: [], age: 50))
    }

    func testSummarizeAveragesAcrossEntries() {
        let metrics = [
            HealthMetricEntry(date: "2026-01-01", walkingSpeed: 1.40, stairSpeedUp: 0.50, stairSpeedDown: 0.50),
            HealthMetricEntry(date: "2026-01-02", walkingSpeed: 1.40, stairSpeedUp: 0.50, stairSpeedDown: 0.50)
        ]
        let summary = FunctionalAgeEngine.summarize(metrics: metrics, age: 50)
        XCTAssertEqual(summary?.functionalAge ?? .nan, 50, accuracy: 0.0001)
        XCTAssertEqual(summary?.componentCount, 2)
        XCTAssertEqual(summary?.level, .onPar)
    }
}
