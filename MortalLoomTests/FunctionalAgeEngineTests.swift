import XCTest
@testable import MortalLoom

// MARK: - FunctionalAgeEngine Tests
//
// Pure-function tests for the age-normative inversion of walking/stair speed, the
// asymmetry modifier, gap classification, and the metric-aggregating `summarize`.

final class FunctionalAgeEngineTests: XCTestCase {

    // MARK: - Age-normative expected speeds

    func testExpectedWalkingSpeedPlateausThroughMidlife() {
        // Flat at the plateau (1.40 m/s) at and below the anchor age.
        XCTAssertEqual(FunctionalAgeEngine.expectedWalkingSpeed(age: 30), 1.40, accuracy: 0.0001)
        XCTAssertEqual(FunctionalAgeEngine.expectedWalkingSpeed(age: 50), 1.40, accuracy: 0.0001)
    }

    func testExpectedWalkingSpeedDeclinesAfterAnchor() {
        // 0.012 m/s per year past 50: at 70 → 1.40 − 20·0.012 = 1.16.
        XCTAssertEqual(FunctionalAgeEngine.expectedWalkingSpeed(age: 70), 1.16, accuracy: 0.0001)
    }

    func testExpectedStairSpeedPlateauAndDecline() {
        XCTAssertEqual(FunctionalAgeEngine.expectedStairSpeed(age: 30), 0.50, accuracy: 0.0001)
        XCTAssertEqual(FunctionalAgeEngine.expectedStairSpeed(age: 70), 0.40, accuracy: 0.0001)
    }

    // MARK: - Walking-speed inversion (age-relative)

    func testWalkingAtAgeNormalReadsOwnAge() {
        // Walking the speed expected at one's age reads as that age, not the anchor.
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(1.40, chronologicalAge: 50), 50, accuracy: 0.0001)
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(1.16, chronologicalAge: 70), 70, accuracy: 0.0001)
    }

    func testWalkingUnder50PlateauNotPenalized() {
        // Regression: a healthy 30-year-old at the plateau speed must read ~30,
        // NOT be mapped to the anchor age (50) as if the plateau were a decline.
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(1.40, chronologicalAge: 30), 30, accuracy: 0.0001)
    }

    func testFasterThanAgeNormalReadsYounger() {
        // +0.12 m/s above the age-50 norm = 10 years younger (0.012 m/s per year).
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(1.52, chronologicalAge: 50), 40, accuracy: 0.0001)
    }

    func testSlowerThanAgeNormalReadsOlder() {
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(1.28, chronologicalAge: 50), 60, accuracy: 0.0001)
    }

    func testWalkingSpeedEstimateClampsToAdultRange() {
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(5.0, chronologicalAge: 50), 18, accuracy: 0.0001)
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromWalkingSpeed(0.0, chronologicalAge: 50), 110, accuracy: 0.0001)
    }

    // MARK: - Stair-speed inversion (age-relative)

    func testStairAtAgeNormalReadsOwnAge() {
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromStairSpeed(0.50, chronologicalAge: 50), 50, accuracy: 0.0001)
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromStairSpeed(0.50, chronologicalAge: 30), 30, accuracy: 0.0001)
    }

    func testStairSpeedSteeperSlope() {
        // 0.005 m/s per year: ±0.05 m/s = ±10 years vs the age-50 norm.
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromStairSpeed(0.55, chronologicalAge: 50), 40, accuracy: 0.0001)
        XCTAssertEqual(FunctionalAgeEngine.functionalAgeFromStairSpeed(0.45, chronologicalAge: 50), 60, accuracy: 0.0001)
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

    func testEstimateReturnsNilForUnknownAge() {
        // Birth date not set → userAge defaults to 0; an age-adjusted estimate is
        // meaningless without a reference age, so the card stays hidden.
        XCTAssertNil(FunctionalAgeEngine.estimate(
            walkingSpeed: 1.40, stairSpeedUp: 0.50, stairSpeedDown: 0.50,
            asymmetry: nil, chronologicalAge: 0))
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

    func testEstimateUnder50AtPlateauReadsOnPar() {
        // Regression for the under-50 plateau: a healthy 30-year-old at age-normal
        // mobility must read ~30 / On Par, not be penalized toward the anchor age.
        let summary = FunctionalAgeEngine.estimate(
            walkingSpeed: 1.40, stairSpeedUp: 0.50, stairSpeedDown: 0.50,
            asymmetry: nil, chronologicalAge: 30)
        XCTAssertEqual(summary?.functionalAge ?? .nan, 30, accuracy: 0.0001)
        XCTAssertEqual(summary?.gapYears ?? .nan, 0, accuracy: 0.0001)
        XCTAssertEqual(summary?.level, .onPar)
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

    // MARK: - Citation registration

    func testBohannonCitationIsRegistered() {
        // The Functional Age card's CitationBadge resolves this id through
        // CitationLibrary.resolve, which silently drops ids missing from `all`.
        XCTAssertNotNil(CitationLibrary.all[CitationLibrary.bohannonGaitNorms2011.id])
        XCTAssertEqual(
            CitationLibrary.resolve([CitationLibrary.bohannonGaitNorms2011.id]).count, 1)
    }
}
