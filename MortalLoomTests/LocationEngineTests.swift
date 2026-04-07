import XCTest
@testable import MortalLoom

// MARK: - LocationEngine Tests
//
// Pure-function unit tests for LocationEngine. Each test verifies a single
// observable behavior: country deltas, air quality adjustments, the combined
// adjustment, and metadata helpers.

final class LocationEngineTests: XCTestCase {

    // MARK: Country deltas — known values

    func testCountryDeltaUSIsZeroBaseline() {
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("US"), 0.0)
    }

    func testCountryDeltaJapanPositive() {
        // Japan is the gold standard — 5.8y above US average
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("JP"), 5.8, accuracy: 0.001)
    }

    func testCountryDeltaSwitzerlandPositive() {
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("CH"), 4.9, accuracy: 0.001)
    }

    func testCountryDeltaHongKongAtCeiling() {
        // Hong Kong is the highest in the table at 6.0; clamp ceiling is also 6.0
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("HK"), 6.0, accuracy: 0.001)
    }

    // MARK: Country deltas — clamping

    func testCountryDeltaClampsToCeiling() {
        // Even if a future entry exceeds 6.0, it should clamp at +6.0
        XCTAssertLessThanOrEqual(LocationEngine.countryLifeExpectancyDelta("HK"), 6.0)
    }

    func testCountryDeltaClampsToFloor() {
        // India / Pakistan / etc. are stored at -8.0 (already at floor)
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("IN"), -8.0, accuracy: 0.001)
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("PK"), -8.0, accuracy: 0.001)
        // All Sub-Saharan African countries clamp to floor
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("NG"), -8.0, accuracy: 0.001)
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("KE"), -8.0, accuracy: 0.001)
    }

    func testCountryDeltaUnknownCodeIsZero() {
        // Unknown ISO codes return 0 (do not penalize unknown locations)
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("XX"), 0.0)
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta("ZZ"), 0.0)
        XCTAssertEqual(LocationEngine.countryLifeExpectancyDelta(""), 0.0)
    }

    func testCountryDeltaCaseInsensitive() {
        // Lowercase input should normalize to uppercase
        XCTAssertEqual(
            LocationEngine.countryLifeExpectancyDelta("jp"),
            LocationEngine.countryLifeExpectancyDelta("JP")
        )
        XCTAssertEqual(
            LocationEngine.countryLifeExpectancyDelta("us"),
            LocationEngine.countryLifeExpectancyDelta("US")
        )
        XCTAssertEqual(
            LocationEngine.countryLifeExpectancyDelta("Ch"),
            LocationEngine.countryLifeExpectancyDelta("CH")
        )
    }

    // MARK: Air quality adjustments

    func testAirQualityGood() {
        XCTAssertEqual(LocationEngine.airQualityAdjustment(.good), 0.5)
    }

    func testAirQualityModerate() {
        // Moderate is the baseline — no adjustment
        XCTAssertEqual(LocationEngine.airQualityAdjustment(.moderate), 0.0)
    }

    func testAirQualityUnhealthy() {
        XCTAssertEqual(LocationEngine.airQualityAdjustment(.unhealthy), -1.5)
    }

    func testAirQualityHazardous() {
        XCTAssertEqual(LocationEngine.airQualityAdjustment(.hazardous), -3.0)
    }

    func testAirQualityNilIsZero() {
        // nil air quality should not penalize
        XCTAssertEqual(LocationEngine.airQualityAdjustment(nil), 0.0)
    }

    // MARK: Combined location adjustment

    func testLocationAdjustmentNeitherSet() {
        // Neither country nor AQ → 0
        XCTAssertEqual(LocationEngine.locationAdjustment(countryCode: nil, airQuality: nil), 0.0)
    }

    func testLocationAdjustmentJapanGoodAir() {
        // 5.8 (Japan) + 0.5 (good AQ) = 6.3
        XCTAssertEqual(
            LocationEngine.locationAdjustment(countryCode: "JP", airQuality: .good),
            6.3,
            accuracy: 0.001
        )
    }

    func testLocationAdjustmentUSAModerateAir() {
        // 0.0 + 0.0 = 0.0
        XCTAssertEqual(
            LocationEngine.locationAdjustment(countryCode: "US", airQuality: .moderate),
            0.0
        )
    }

    func testLocationAdjustmentClampsCeiling() {
        // Hong Kong (6.0) + good (0.5) = 6.5 — under ceiling of 8.0, no clamp
        XCTAssertEqual(
            LocationEngine.locationAdjustment(countryCode: "HK", airQuality: .good),
            6.5,
            accuracy: 0.001
        )
    }

    func testLocationAdjustmentClampsFloor() {
        // India (-8.0) + hazardous (-3.0) = -11.0 → clamp to -10.0
        XCTAssertEqual(
            LocationEngine.locationAdjustment(countryCode: "IN", airQuality: .hazardous),
            -10.0,
            accuracy: 0.001
        )
    }

    func testLocationAdjustmentRoundedToOneDecimal() {
        // Verify the result is rounded to one decimal place
        let result = LocationEngine.locationAdjustment(countryCode: "JP", airQuality: .good)
        let rounded = (result * 10).rounded() / 10
        XCTAssertEqual(result, rounded, "Result should already be rounded to one decimal place")
    }

    func testLocationAdjustmentUnknownCountry() {
        // Unknown country + nil AQ → 0.0
        XCTAssertEqual(
            LocationEngine.locationAdjustment(countryCode: "ZZ", airQuality: nil),
            0.0
        )
    }

    // MARK: Display names and picker

    func testCountryDisplayNameKnown() {
        XCTAssertEqual(LocationEngine.countryDisplayName("JP"), "Japan")
        XCTAssertEqual(LocationEngine.countryDisplayName("US"), "United States")
        XCTAssertEqual(LocationEngine.countryDisplayName("GB"), "United Kingdom")
    }

    func testCountryDisplayNameCaseInsensitive() {
        XCTAssertEqual(LocationEngine.countryDisplayName("jp"), "Japan")
    }

    func testCountryDisplayNameUnknownReturnsCode() {
        // Unknown codes fall back to the raw code
        XCTAssertEqual(LocationEngine.countryDisplayName("XY"), "XY")
        XCTAssertEqual(LocationEngine.countryDisplayName("ZZ"), "ZZ")
    }

    func testCountriesForPickerIsSortedByDisplayName() {
        let names = LocationEngine.countriesForPicker.map(\.name)
        let sorted = names.sorted()
        XCTAssertEqual(names, sorted, "countriesForPicker should be alphabetical by display name")
    }

    func testCountriesForPickerContainsKnownCountries() {
        let codes = LocationEngine.countriesForPicker.map(\.code)
        XCTAssertTrue(codes.contains("US"))
        XCTAssertTrue(codes.contains("JP"))
        XCTAssertTrue(codes.contains("GB"))
    }
}
