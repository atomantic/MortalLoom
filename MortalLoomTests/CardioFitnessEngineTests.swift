import XCTest
@testable import MortalLoom

// MARK: - CardioFitnessEngine Tests
//
// Pure-function tests for CardioFitnessEngine classifications and longevity
// impacts. Each test states a single observable behavior with concrete values.

final class CardioFitnessEngineTests: XCTestCase {

    // MARK: - VO2 Max classification

    func testVO2MaxMaleSuperior20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(55, age: 25, sex: .male), .superior)
    }

    func testVO2MaxMaleExcellent20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(48, age: 25, sex: .male), .excellent)
    }

    func testVO2MaxMaleGood20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(43, age: 25, sex: .male), .good)
    }

    func testVO2MaxMaleFair20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(40, age: 25, sex: .male), .fair)
    }

    func testVO2MaxMalePoor20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(35, age: 25, sex: .male), .poor)
    }

    func testVO2MaxMaleVeryPoor20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(20, age: 25, sex: .male), .veryPoor)
    }

    func testVO2MaxMale30sBoundary() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(49, age: 35, sex: .male), .superior)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(48.99, age: 35, sex: .male), .excellent)
    }

    func testVO2MaxMale40sThresholds() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(46, age: 45, sex: .male), .superior)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(41, age: 45, sex: .male), .excellent)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(37, age: 45, sex: .male), .good)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(33, age: 45, sex: .male), .fair)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(28, age: 45, sex: .male), .poor)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(27, age: 45, sex: .male), .veryPoor)
    }

    func testVO2MaxMale50s() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(43, age: 55, sex: .male), .superior)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(35, age: 55, sex: .male), .good)
    }

    func testVO2MaxMale60s() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(40, age: 65, sex: .male), .superior)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(22, age: 65, sex: .male), .poor)
    }

    func testVO2MaxMale70Plus() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(37, age: 75, sex: .male), .superior)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(15, age: 75, sex: .male), .veryPoor)
    }

    func testVO2MaxFemaleThresholdsLowerThanMale() {
        // Female superior at 20s = 44, male = 52
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(44, age: 25, sex: .female), .superior)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(44, age: 25, sex: .male), .good)
    }

    func testVO2MaxFemale30s() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(41, age: 35, sex: .female), .superior)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(36, age: 35, sex: .female), .excellent)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(32, age: 35, sex: .female), .good)
    }

    func testVO2MaxFemale70Plus() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(29, age: 75, sex: .female), .superior)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(13, age: 75, sex: .female), .veryPoor)
    }

    func testVO2MaxNilSexTreatedAsMale() {
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(52, age: 25, sex: nil), .superior)
        XCTAssertEqual(CardioFitnessEngine.classifyVO2Max(43, age: 25, sex: nil), .good)
    }

    // MARK: - FitnessLevel cosmetic properties

    func testFitnessLevelColors() {
        XCTAssertEqual(CardioFitnessEngine.FitnessLevel.superior.color, "green")
        XCTAssertEqual(CardioFitnessEngine.FitnessLevel.excellent.color, "green")
        XCTAssertEqual(CardioFitnessEngine.FitnessLevel.good.color, "blue")
        XCTAssertEqual(CardioFitnessEngine.FitnessLevel.fair.color, "yellow")
        XCTAssertEqual(CardioFitnessEngine.FitnessLevel.poor.color, "orange")
        XCTAssertEqual(CardioFitnessEngine.FitnessLevel.veryPoor.color, "red")
    }

    func testFitnessLevelSystemImagesAreDistinct() {
        let images = [
            CardioFitnessEngine.FitnessLevel.superior.systemImage,
            CardioFitnessEngine.FitnessLevel.excellent.systemImage,
            CardioFitnessEngine.FitnessLevel.good.systemImage,
            CardioFitnessEngine.FitnessLevel.fair.systemImage,
            CardioFitnessEngine.FitnessLevel.poor.systemImage,
            CardioFitnessEngine.FitnessLevel.veryPoor.systemImage
        ]
        XCTAssertEqual(Set(images).count, images.count)
    }

    // MARK: - Resting heart rate classification

    func testRestingHRAthlete() {
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(45), .athlete)
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(49.99), .athlete)
    }

    func testRestingHRExcellent() {
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(50), .excellent)
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(59.9), .excellent)
    }

    func testRestingHRGood() {
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(60), .good)
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(64.99), .good)
    }

    func testRestingHRAboveAverage() {
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(65), .aboveAverage)
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(69.99), .aboveAverage)
    }

    func testRestingHRAverage() {
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(70), .average)
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(79.99), .average)
    }

    func testRestingHRBelowAverage() {
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(80), .belowAverage)
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(89.99), .belowAverage)
    }

    func testRestingHRPoor() {
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(90), .poor)
        XCTAssertEqual(CardioFitnessEngine.classifyRestingHR(120), .poor)
    }

    func testHeartRateZoneColors() {
        XCTAssertEqual(CardioFitnessEngine.HeartRateZone.athlete.color, "green")
        XCTAssertEqual(CardioFitnessEngine.HeartRateZone.excellent.color, "green")
        XCTAssertEqual(CardioFitnessEngine.HeartRateZone.good.color, "blue")
        XCTAssertEqual(CardioFitnessEngine.HeartRateZone.aboveAverage.color, "blue")
        XCTAssertEqual(CardioFitnessEngine.HeartRateZone.average.color, "yellow")
        XCTAssertEqual(CardioFitnessEngine.HeartRateZone.belowAverage.color, "orange")
        XCTAssertEqual(CardioFitnessEngine.HeartRateZone.poor.color, "red")
    }

    // MARK: - HRV classification

    func testHRVHigh20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(80, age: 25), .high)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(120, age: 25), .high)
    }

    func testHRVAboveAverage20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(60, age: 25), .aboveAverage)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(79.9, age: 25), .aboveAverage)
    }

    func testHRVAverage20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(40, age: 25), .average)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(59.9, age: 25), .average)
    }

    func testHRVBelowAverage20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(25, age: 25), .belowAverage)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(39.9, age: 25), .belowAverage)
    }

    func testHRVLow20s() {
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(15, age: 25), .low)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(0, age: 25), .low)
    }

    func testHRVAgeAdjustedThresholds() {
        // Same SDNN of 50 -> different classification by age
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(50, age: 25), .average)        // [80,60,40,25] -> 50 in [40,60)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(50, age: 35), .aboveAverage)   // [70,50,35,20] -> 50 == 50
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(50, age: 55), .high)           // [50,35,22,15] -> 50 == 50
    }

    func testHRV70PlusThresholds() {
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(40, age: 75), .high)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(25, age: 75), .aboveAverage)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(15, age: 75), .average)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(10, age: 75), .belowAverage)
        XCTAssertEqual(CardioFitnessEngine.classifyHRV(5, age: 75), .low)
    }

    func testHRVLevelColors() {
        XCTAssertEqual(CardioFitnessEngine.HRVLevel.high.color, "green")
        XCTAssertEqual(CardioFitnessEngine.HRVLevel.aboveAverage.color, "green")
        XCTAssertEqual(CardioFitnessEngine.HRVLevel.average.color, "blue")
        XCTAssertEqual(CardioFitnessEngine.HRVLevel.belowAverage.color, "orange")
        XCTAssertEqual(CardioFitnessEngine.HRVLevel.low.color, "red")
    }

    // MARK: - Heart rate recovery

    func testRecoveryExcellent() {
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(45), .excellent)
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(40), .excellent)
    }

    func testRecoveryGood() {
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(30), .good)
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(25), .good)
    }

    func testRecoveryNormal() {
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(15), .normal)
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(12), .normal)
    }

    func testRecoveryBelowNormal() {
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(8), .belowNormal)
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(6), .belowNormal)
    }

    func testRecoveryAbnormal() {
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(5), .abnormal)
        XCTAssertEqual(CardioFitnessEngine.classifyRecovery(0), .abnormal)
    }

    func testRecoveryLevelColors() {
        XCTAssertEqual(CardioFitnessEngine.RecoveryLevel.excellent.color, "green")
        XCTAssertEqual(CardioFitnessEngine.RecoveryLevel.good.color, "blue")
        XCTAssertEqual(CardioFitnessEngine.RecoveryLevel.normal.color, "yellow")
        XCTAssertEqual(CardioFitnessEngine.RecoveryLevel.belowNormal.color, "orange")
        XCTAssertEqual(CardioFitnessEngine.RecoveryLevel.abnormal.color, "red")
    }

    func testRecoveryLevelSystemImagesAreDistinct() {
        let images = [
            CardioFitnessEngine.RecoveryLevel.excellent.systemImage,
            CardioFitnessEngine.RecoveryLevel.good.systemImage,
            CardioFitnessEngine.RecoveryLevel.normal.systemImage,
            CardioFitnessEngine.RecoveryLevel.belowNormal.systemImage,
            CardioFitnessEngine.RecoveryLevel.abnormal.systemImage
        ]
        XCTAssertEqual(Set(images).count, images.count)
    }

    func testRecoveryLongevityImpactRangesByLevel() {
        XCTAssertEqual(CardioFitnessEngine.recoveryLongevityImpact(45), 2.0)
        XCTAssertEqual(CardioFitnessEngine.recoveryLongevityImpact(30), 1.0)
        XCTAssertEqual(CardioFitnessEngine.recoveryLongevityImpact(15), 0.0)
        XCTAssertEqual(CardioFitnessEngine.recoveryLongevityImpact(8), -1.0)
        XCTAssertEqual(CardioFitnessEngine.recoveryLongevityImpact(2), -2.0)
    }

    // MARK: - Blood pressure classification

    func testBPNormal() {
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 110, diastolic: 70), .normal)
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 119, diastolic: 79), .normal)
    }

    func testBPElevated() {
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 120, diastolic: 75), .elevated)
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 125, diastolic: 79), .elevated)
    }

    func testBPHighStage1() {
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 130, diastolic: 80), .highStage1)
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 135, diastolic: 85), .highStage1)
        // Diastolic alone can push into stage 1
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 110, diastolic: 82), .highStage1)
    }

    func testBPHighStage2() {
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 140, diastolic: 80), .highStage2)
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 110, diastolic: 92), .highStage2)
    }

    func testBPCrisis() {
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 185, diastolic: 110), .crisis)
        XCTAssertEqual(CardioFitnessEngine.classifyBP(systolic: 130, diastolic: 125), .crisis)
    }

    func testBPCategoryColors() {
        XCTAssertEqual(CardioFitnessEngine.BPCategory.normal.color, "green")
        XCTAssertEqual(CardioFitnessEngine.BPCategory.elevated.color, "yellow")
        XCTAssertEqual(CardioFitnessEngine.BPCategory.highStage1.color, "orange")
        XCTAssertEqual(CardioFitnessEngine.BPCategory.highStage2.color, "red")
        XCTAssertEqual(CardioFitnessEngine.BPCategory.crisis.color, "red")
    }

    func testBPLongevityImpactSpansFullScale() {
        XCTAssertEqual(CardioFitnessEngine.bpLongevityImpact(systolic: 110, diastolic: 70), 1.5)
        XCTAssertEqual(CardioFitnessEngine.bpLongevityImpact(systolic: 122, diastolic: 78), 0.0)
        XCTAssertEqual(CardioFitnessEngine.bpLongevityImpact(systolic: 135, diastolic: 82), -1.5)
        XCTAssertEqual(CardioFitnessEngine.bpLongevityImpact(systolic: 145, diastolic: 95), -3.0)
        XCTAssertEqual(CardioFitnessEngine.bpLongevityImpact(systolic: 200, diastolic: 130), -5.0)
    }

    // MARK: - VO2 Max longevity impact

    func testVO2MaxLongevityImpactSuperior() {
        XCTAssertEqual(CardioFitnessEngine.vo2MaxLongevityImpact(55, age: 25, sex: .male), 3.0)
    }

    func testVO2MaxLongevityImpactExcellent() {
        XCTAssertEqual(CardioFitnessEngine.vo2MaxLongevityImpact(48, age: 25, sex: .male), 2.0)
    }

    func testVO2MaxLongevityImpactGood() {
        XCTAssertEqual(CardioFitnessEngine.vo2MaxLongevityImpact(43, age: 25, sex: .male), 1.0)
    }

    func testVO2MaxLongevityImpactFair() {
        XCTAssertEqual(CardioFitnessEngine.vo2MaxLongevityImpact(40, age: 25, sex: .male), 0.0)
    }

    func testVO2MaxLongevityImpactPoor() {
        XCTAssertEqual(CardioFitnessEngine.vo2MaxLongevityImpact(35, age: 25, sex: .male), -1.5)
    }

    func testVO2MaxLongevityImpactVeryPoor() {
        XCTAssertEqual(CardioFitnessEngine.vo2MaxLongevityImpact(20, age: 25, sex: .male), -3.0)
    }
}
