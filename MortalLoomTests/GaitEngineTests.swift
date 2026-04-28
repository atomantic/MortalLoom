import XCTest
@testable import MortalLoom

// MARK: - GaitEngine Tests
//
// Pure-function tests for walking-speed classification, fall-risk scoring,
// longevity impact mapping, and the metric-aggregating `summarize`.

final class GaitEngineTests: XCTestCase {

    // MARK: - Walking speed classification

    func testWalkingSpeedExcellent() {
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(1.4, age: 40), .excellent)
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(1.3, age: 40), .excellent)
    }

    func testWalkingSpeedGood() {
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(1.2, age: 40), .good)
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(1.1, age: 40), .good)
    }

    func testWalkingSpeedFair() {
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(1.0, age: 40), .fair)
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(0.9, age: 40), .fair)
    }

    func testWalkingSpeedSlow() {
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(0.85, age: 40), .slow)
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(0.7, age: 40), .slow)
    }

    func testWalkingSpeedVerySlow() {
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(0.6, age: 40), .verySlow)
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(0.0, age: 40), .verySlow)
    }

    func testWalkingSpeedSeniorAdjustment() {
        // Age 65+ adds a +0.15 m/s effective bonus, so a 1.2 m/s walker counts
        // as "excellent" at 70 (1.2 + 0.15 = 1.35 ≥ 1.3) but only "good" at 40.
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(1.2, age: 70), .excellent)
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(1.2, age: 40), .good)
    }

    func testWalkingSpeedSeniorAdjustmentVeryLow() {
        // 0.55 m/s in a senior adjusts to 0.7 effective -> still "slow", not very slow
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(0.55, age: 70), .slow)
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(0.4, age: 70), .verySlow)
    }

    func testWalkingSpeedSeniorBoundary() {
        // Age 65 is the cutoff for the senior offset (>= 65 gets the boost)
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(1.2, age: 65), .excellent)
        XCTAssertEqual(GaitEngine.classifyWalkingSpeed(1.2, age: 64), .good)
    }

    // MARK: - WalkingSpeedLevel cosmetics

    func testWalkingSpeedColors() {
        XCTAssertEqual(GaitEngine.WalkingSpeedLevel.excellent.color, "green")
        XCTAssertEqual(GaitEngine.WalkingSpeedLevel.good.color, "blue")
        XCTAssertEqual(GaitEngine.WalkingSpeedLevel.fair.color, "yellow")
        XCTAssertEqual(GaitEngine.WalkingSpeedLevel.slow.color, "orange")
        XCTAssertEqual(GaitEngine.WalkingSpeedLevel.verySlow.color, "red")
    }

    func testWalkingSpeedSystemImagesAreDistinct() {
        let images = [
            GaitEngine.WalkingSpeedLevel.excellent.systemImage,
            GaitEngine.WalkingSpeedLevel.good.systemImage,
            GaitEngine.WalkingSpeedLevel.fair.systemImage,
            GaitEngine.WalkingSpeedLevel.slow.systemImage,
            GaitEngine.WalkingSpeedLevel.verySlow.systemImage
        ]
        XCTAssertEqual(Set(images).count, images.count)
    }

    // MARK: - Fall risk

    func testFallRiskBothNilReturnsLow() {
        XCTAssertEqual(GaitEngine.assessFallRisk(asymmetry: nil, doubleSupport: nil), .low)
    }

    func testFallRiskMinorAsymmetryAlone() {
        // 4% asymmetry → 1pt, no doubleSupport → moderate
        XCTAssertEqual(GaitEngine.assessFallRisk(asymmetry: 4, doubleSupport: nil), .moderate)
    }

    func testFallRiskAsymmetryEscalates() {
        // 7% → 2pts → moderate (need 3 to be elevated)
        XCTAssertEqual(GaitEngine.assessFallRisk(asymmetry: 7, doubleSupport: nil), .moderate)
        // 11% → 3pts → elevated
        XCTAssertEqual(GaitEngine.assessFallRisk(asymmetry: 11, doubleSupport: nil), .elevated)
    }

    func testFallRiskDoubleSupportAlone() {
        XCTAssertEqual(GaitEngine.assessFallRisk(asymmetry: nil, doubleSupport: 28), .moderate)
        XCTAssertEqual(GaitEngine.assessFallRisk(asymmetry: nil, doubleSupport: 32), .moderate)
        XCTAssertEqual(GaitEngine.assessFallRisk(asymmetry: nil, doubleSupport: 40), .elevated)
    }

    func testFallRiskCombinedHigh() {
        // 11% asymmetry (3pt) + 36% double support (3pt) = 6 total → high
        XCTAssertEqual(GaitEngine.assessFallRisk(asymmetry: 11, doubleSupport: 36), .high)
    }

    func testFallRiskJustBelowThreshold() {
        // 3% asym (0pt) + 27% ds (0pt) → low
        XCTAssertEqual(GaitEngine.assessFallRisk(asymmetry: 3, doubleSupport: 27), .low)
    }

    func testFallRiskColors() {
        XCTAssertEqual(GaitEngine.FallRisk.low.color, "green")
        XCTAssertEqual(GaitEngine.FallRisk.moderate.color, "yellow")
        XCTAssertEqual(GaitEngine.FallRisk.elevated.color, "orange")
        XCTAssertEqual(GaitEngine.FallRisk.high.color, "red")
    }

    // MARK: - Longevity impact

    func testWalkingSpeedLongevityImpactMatchesLevel() {
        XCTAssertEqual(GaitEngine.walkingSpeedLongevityImpact(1.4, age: 40), 2.0)
        XCTAssertEqual(GaitEngine.walkingSpeedLongevityImpact(1.2, age: 40), 1.0)
        XCTAssertEqual(GaitEngine.walkingSpeedLongevityImpact(1.0, age: 40), 0.0)
        XCTAssertEqual(GaitEngine.walkingSpeedLongevityImpact(0.8, age: 40), -1.5)
        XCTAssertEqual(GaitEngine.walkingSpeedLongevityImpact(0.5, age: 40), -3.0)
    }

    // MARK: - Summarize

    func testSummarizeEmptyMetrics() {
        let summary = GaitEngine.summarize(metrics: [], age: 40)
        XCTAssertNil(summary.avgWalkingSpeed)
        XCTAssertNil(summary.avgWalkingDistance)
        XCTAssertNil(summary.avgAsymmetry)
        XCTAssertNil(summary.avgDoubleSupport)
        XCTAssertNil(summary.speedLevel)
        XCTAssertEqual(summary.fallRisk, .low)
        XCTAssertNil(summary.longevityYears)
    }

    func testSummarizeAveragesAcrossEntries() {
        let metrics = [
            HealthMetricEntry(date: "2026-01-01", walkingSpeed: 1.0, walkingDistance: 5.0, walkingAsymmetry: 4, walkingDoubleSupport: 28),
            HealthMetricEntry(date: "2026-01-02", walkingSpeed: 1.4, walkingDistance: 7.0, walkingAsymmetry: 6, walkingDoubleSupport: 32)
        ]
        let summary = GaitEngine.summarize(metrics: metrics, age: 40)
        XCTAssertEqual(summary.avgWalkingSpeed ?? .nan, 1.2, accuracy: 0.0001)
        XCTAssertEqual(summary.avgWalkingDistance ?? .nan, 6.0, accuracy: 0.0001)
        XCTAssertEqual(summary.avgAsymmetry ?? .nan, 5.0, accuracy: 0.0001)
        XCTAssertEqual(summary.avgDoubleSupport ?? .nan, 30.0, accuracy: 0.0001)
        XCTAssertEqual(summary.speedLevel, .good)
        // 4% asym (1pt) + 30% ds (1pt) → moderate
        XCTAssertEqual(summary.fallRisk, .moderate)
        XCTAssertEqual(summary.longevityYears, 1.0)
    }

    func testSummarizeIgnoresNilFieldsPerMetric() {
        // Two entries: one with full data, one entirely empty
        let metrics = [
            HealthMetricEntry(date: "2026-01-01", walkingSpeed: 1.3, walkingAsymmetry: 4),
            HealthMetricEntry(date: "2026-01-02") // all nil
        ]
        let summary = GaitEngine.summarize(metrics: metrics, age: 40)
        XCTAssertEqual(summary.avgWalkingSpeed ?? .nan, 1.3, accuracy: 0.0001)
        XCTAssertNil(summary.avgWalkingDistance)
        XCTAssertEqual(summary.avgAsymmetry ?? .nan, 4.0, accuracy: 0.0001)
        XCTAssertNil(summary.avgDoubleSupport)
        XCTAssertEqual(summary.speedLevel, .excellent)
    }

    func testSummarizeSeniorAdjustmentApplies() {
        let metrics = [
            HealthMetricEntry(date: "2026-01-01", walkingSpeed: 1.2)
        ]
        let summary = GaitEngine.summarize(metrics: metrics, age: 70)
        // 1.2 + 0.15 senior offset → 1.35 effective → excellent
        XCTAssertEqual(summary.speedLevel, .excellent)
        XCTAssertEqual(summary.longevityYears, 2.0)
    }

    func testSummarizeFallRiskFromAggregates() {
        let metrics = [
            HealthMetricEntry(date: "2026-01-01", walkingAsymmetry: 12, walkingDoubleSupport: 36),
            HealthMetricEntry(date: "2026-01-02", walkingAsymmetry: 12, walkingDoubleSupport: 36)
        ]
        let summary = GaitEngine.summarize(metrics: metrics, age: 40)
        XCTAssertEqual(summary.fallRisk, .high)
    }
}
