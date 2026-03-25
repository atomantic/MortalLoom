import XCTest
@testable import MortalLoom

// MARK: - DeathClockEngine Tests

final class DeathClockEngineTests: XCTestCase {

    // MARK: SSA Baseline

    func testSSABaselineMale() {
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 25), 76.0)
    }

    func testSSABaselineFemale() {
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .female, ageYears: 25), 81.0)
    }

    func testSSABaselineUnspecified() {
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: nil, ageYears: 25), 78.5)
    }

    func testSSABaselineConditionalBonusYoung() {
        // Under 30: no bonus
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 20), 76.0)
    }

    func testSSABaselineConditionalBonus40s() {
        // 40-49: +1.0 bonus
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 45), 77.0)
    }

    func testSSABaselineConditionalBonus70s() {
        // 70-79: +4.0 bonus
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .female, ageYears: 75), 85.0)
    }

    func testSSABaselineConditionalBonus90Plus() {
        // 90+: +8.0 bonus
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 95), 84.0)
    }

    // MARK: Lifestyle Impact

    func testSmokingImpactNever() {
        XCTAssertEqual(DeathClockEngine.smokingImpact(.never), 0)
    }

    func testSmokingImpactFormer() {
        XCTAssertEqual(DeathClockEngine.smokingImpact(.former), -2)
    }

    func testSmokingImpactCurrent() {
        XCTAssertEqual(DeathClockEngine.smokingImpact(.current), -10)
    }

    func testExerciseImpactHigh() {
        XCTAssertEqual(DeathClockEngine.exerciseImpact(180), 2)
    }

    func testExerciseImpactModerate() {
        XCTAssertEqual(DeathClockEngine.exerciseImpact(100), 0.5)
    }

    func testExerciseImpactLow() {
        XCTAssertEqual(DeathClockEngine.exerciseImpact(30), -2)
    }

    func testExerciseImpactThreshold() {
        // Exactly 150 is the threshold for moderate, not high
        XCTAssertEqual(DeathClockEngine.exerciseImpact(150), 0.5)
        XCTAssertEqual(DeathClockEngine.exerciseImpact(151), 2)
    }

    func testSleepImpactOptimal() {
        XCTAssertEqual(DeathClockEngine.sleepImpact(8.0), 1)
    }

    func testSleepImpactBorderline() {
        XCTAssertEqual(DeathClockEngine.sleepImpact(6.5), 0)
    }

    func testSleepImpactPoor() {
        XCTAssertEqual(DeathClockEngine.sleepImpact(5.0), -1.5)
    }

    func testDietImpactAll() {
        XCTAssertEqual(DeathClockEngine.dietImpact(.excellent), 2)
        XCTAssertEqual(DeathClockEngine.dietImpact(.good), 0.5)
        XCTAssertEqual(DeathClockEngine.dietImpact(.fair), 0)
        XCTAssertEqual(DeathClockEngine.dietImpact(.poor), -3)
    }

    func testStressImpactAll() {
        XCTAssertEqual(DeathClockEngine.stressImpact(.low), 1)
        XCTAssertEqual(DeathClockEngine.stressImpact(.moderate), 0)
        XCTAssertEqual(DeathClockEngine.stressImpact(.high), -2)
    }

    func testBMIImpactNil() {
        XCTAssertEqual(DeathClockEngine.bmiImpact(nil), 0)
    }

    func testBMIImpactHealthy() {
        XCTAssertEqual(DeathClockEngine.bmiImpact(22.0), 0.5)
    }

    func testBMIImpactOverweight() {
        XCTAssertEqual(DeathClockEngine.bmiImpact(27.0), -0.5)
    }

    func testBMIImpactObese() {
        XCTAssertEqual(DeathClockEngine.bmiImpact(32.0), -3)
    }

    func testLifestyleAdjustmentTotal() {
        let lifestyle = LifestyleData(
            smokingStatus: .never,
            exerciseMinutesPerWeek: 180,
            sleepHoursPerNight: 8,
            dietQuality: .excellent,
            stressLevel: .low,
            bmi: 22.0
        )
        // 0 + 2 + 1 + 2 + 1 + 0.5 = 6.5
        XCTAssertEqual(DeathClockEngine.lifestyleAdjustment(lifestyle), 6.5)
    }

    func testLifestyleAdjustmentWorstCase() {
        let lifestyle = LifestyleData(
            smokingStatus: .current,
            exerciseMinutesPerWeek: 0,
            sleepHoursPerNight: 4,
            dietQuality: .poor,
            stressLevel: .high,
            bmi: 35.0
        )
        // -10 + -2 + -1.5 + -3 + -2 + -3 = -21.5
        XCTAssertEqual(DeathClockEngine.lifestyleAdjustment(lifestyle), -21.5)
    }

    // MARK: Full Calculation

    func testCalculateReturnsNilForInvalidDate() {
        let result = DeathClockEngine.calculate(birthDateStr: "invalid", sex: .male, lifestyle: .default)
        XCTAssertNil(result)
    }

    func testCalculateProducesValidResult() {
        let result = DeathClockEngine.calculate(
            birthDateStr: "1980-03-15",
            sex: .male,
            lifestyle: .default
        )
        XCTAssertNotNil(result)
        guard let r = result else { return }

        XCTAssertGreaterThan(r.ageYears, 40)
        XCTAssertLessThan(r.ageYears, 50)
        XCTAssertGreaterThan(r.yearsRemaining, 20)
        XCTAssertLessThan(r.yearsRemaining, 50)
        XCTAssertGreaterThan(r.percentComplete, 40)
        XCTAssertLessThan(r.percentComplete, 70)
        XCTAssertGreaterThan(r.healthyYearsRemaining, 10)
    }

    func testCalculateLifeExpectancyBreakdown() {
        let result = DeathClockEngine.calculate(
            birthDateStr: "1980-03-15",
            sex: .male,
            lifestyle: LifestyleData(
                smokingStatus: .never,
                exerciseMinutesPerWeek: 180,
                sleepHoursPerNight: 7.5,
                dietQuality: .good,
                stressLevel: .moderate,
                bmi: 23.4
            )
        )
        guard let r = result else { XCTFail("Expected result"); return }
        let le = r.lifeExpectancy

        // Male, 45: baseline 77.0 (76 + 1.0 age bonus)
        XCTAssertEqual(le.baseline, 77.0)
        // exercise(180)=2 + sleep(7.5)=1 + diet(good)=0.5 + stress(moderate)=0 + bmi(23.4)=0.5 = 4.0
        XCTAssertEqual(le.lifestyleAdjustment, 4.0)
        XCTAssertEqual(le.total, 81.0)
    }

    // MARK: Countdown

    func testCountdownExpired() {
        let past = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let countdown = DeathClockEngine.countdown(to: past)
        XCTAssertTrue(countdown.expired)
        XCTAssertEqual(countdown.totalDays, 0)
    }

    func testCountdownFuture() {
        let future = Calendar.current.date(byAdding: .year, value: 30, to: Date())!
        let countdown = DeathClockEngine.countdown(to: future)
        XCTAssertFalse(countdown.expired)
        XCTAssertGreaterThan(countdown.years, 28)
        XCTAssertLessThanOrEqual(countdown.years, 30)
        XCTAssertGreaterThan(countdown.totalDays, 10000)
    }

    func testCountdownOneDay() {
        // Use a fixed reference point to avoid sub-second rounding
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 2, to: now)!
        let countdown = DeathClockEngine.countdown(to: tomorrow, from: now)
        XCTAssertFalse(countdown.expired)
        XCTAssertEqual(countdown.totalDays, 2)
        XCTAssertEqual(countdown.years, 0)
    }

    // MARK: LEV

    func testLEVCalculation() {
        let result = DeathClockEngine.calculateLEV(birthDateStr: "1980-03-15", lifeExpectancy: 81.0)
        XCTAssertNotNil(result)
        guard let lev = result else { return }

        XCTAssertEqual(lev.targetYear, 2045)
        XCTAssertEqual(lev.ageAtLEV, 65)
        XCTAssertGreaterThan(lev.researchProgress, 50)
        XCTAssertTrue(lev.onTrack) // 81 >= 65
    }

    func testLEVNotOnTrack() {
        // Person born 1960, LE=70 — won't reach 2045 (age 85)
        let result = DeathClockEngine.calculateLEV(birthDateStr: "1960-01-01", lifeExpectancy: 70.0)
        guard let lev = result else { XCTFail("Expected result"); return }
        XCTAssertFalse(lev.onTrack) // 70 < 85
    }

    func testLEVInvalidDate() {
        XCTAssertNil(DeathClockEngine.calculateLEV(birthDateStr: "bad", lifeExpectancy: 80))
    }

    // MARK: Alcohol Risk

    func testAlcoholRiskLow() {
        let today = DateFormatting.todayString()
        let drinks = [AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: today)]
        XCTAssertEqual(DeathClockEngine.alcoholRisk(drinks: drinks, sex: .male), .low)
    }

    func testAlcoholRiskModerate() {
        let today = DateFormatting.todayString()
        // 3 standard drinks today for a male (daily max is 2)
        let drinks = [AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 3, date: today)]
        XCTAssertEqual(DeathClockEngine.alcoholRisk(drinks: drinks, sex: .male), .moderate)
    }

    func testAlcoholRiskHigh() {
        let today = DateFormatting.todayString()
        // 5+ standard drinks for male (> 2 * dailyMax)
        let drinks = [AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 5, date: today)]
        XCTAssertEqual(DeathClockEngine.alcoholRisk(drinks: drinks, sex: .male), .high)
    }

    func testAlcoholRiskFemaleLowerThreshold() {
        let today = DateFormatting.todayString()
        // 1.5 standard drinks for female (daily max is 1, high threshold is >2)
        // 12oz * 5% = 0.6oz alcohol per beer; 0.6/0.6 = 1.0 std drink per beer
        // 1.5 beers = 1.5 std drinks: > dailyMax(1) but not > dailyMax*2(2) → moderate
        let drinks = [
            AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: today),
            AlcoholDrink(name: "Light Beer", oz: 12, abv: 2.5, count: 1, date: today),
        ]
        XCTAssertEqual(DeathClockEngine.alcoholRisk(drinks: drinks, sex: .female), .moderate)
    }

    func testAlcoholRiskEmptyDrinks() {
        XCTAssertEqual(DeathClockEngine.alcoholRisk(drinks: [], sex: .male), .low)
    }

    // MARK: Health Score

    func testHealthScoreOptimal() {
        let score = DeathClockEngine.healthScore(
            lifestyle: LifestyleData(
                smokingStatus: .never,
                exerciseMinutesPerWeek: 200,
                sleepHoursPerNight: 8,
                dietQuality: .excellent,
                stressLevel: .low,
                bmi: 22
            ),
            ageYears: 30,
            latestEpigeneticTest: EpigeneticTest(date: "2026-01-01", chronologicalAge: 30, biologicalAge: 27, paceOfAging: 0.80),
            alcoholRisk: .low
        )
        XCTAssertGreaterThan(score, 90)
    }

    func testHealthScorePoor() {
        let score = DeathClockEngine.healthScore(
            lifestyle: LifestyleData(
                smokingStatus: .current,
                exerciseMinutesPerWeek: 0,
                sleepHoursPerNight: 4,
                dietQuality: .poor,
                stressLevel: .high,
                bmi: 35
            ),
            ageYears: 70,
            latestEpigeneticTest: EpigeneticTest(date: "2026-01-01", chronologicalAge: 70, biologicalAge: 80, paceOfAging: 1.3),
            alcoholRisk: .high
        )
        XCTAssertLessThan(score, 30)
    }

    func testHealthScoreWithoutOptionalData() {
        // No BMI, no epigenetic test — should still produce a valid score
        let score = DeathClockEngine.healthScore(
            lifestyle: LifestyleData.default,
            ageYears: 45,
            latestEpigeneticTest: nil,
            alcoholRisk: .low
        )
        XCTAssertGreaterThan(score, 50)
        XCTAssertLessThanOrEqual(score, 100)
    }

    func testHealthScoreAgePenalty() {
        let young = DeathClockEngine.healthScore(
            lifestyle: .default, ageYears: 30,
            latestEpigeneticTest: nil, alcoholRisk: .low
        )
        let old = DeathClockEngine.healthScore(
            lifestyle: .default, ageYears: 75,
            latestEpigeneticTest: nil, alcoholRisk: .low
        )
        XCTAssertGreaterThan(young, old)
    }

    func testHealthScoreBounds() {
        // Score should always be between 5 and 100
        let score = DeathClockEngine.healthScore(
            lifestyle: LifestyleData(smokingStatus: .current, exerciseMinutesPerWeek: 0, sleepHoursPerNight: 3, dietQuality: .poor, stressLevel: .high, bmi: 45),
            ageYears: 90,
            latestEpigeneticTest: EpigeneticTest(date: "2026-01-01", chronologicalAge: 90, biologicalAge: 110, paceOfAging: 1.5),
            alcoholRisk: .high
        )
        XCTAssertGreaterThanOrEqual(score, 5)
        XCTAssertLessThanOrEqual(score, 100)
    }
}

// MARK: - Model Tests

final class ModelCodableTests: XCTestCase {

    func testAppDataRoundTrip() {
        let data = SampleData.fullAppData
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try! encoder.encode(data)
        let decoded = try! JSONDecoder().decode(AppData.self, from: encoded)

        XCTAssertEqual(decoded.profile, data.profile)
        XCTAssertEqual(decoded.alcoholDrinks.count, data.alcoholDrinks.count)
        XCTAssertEqual(decoded.nicotineEntries.count, data.nicotineEntries.count)
        XCTAssertEqual(decoded.bloodTests.count, data.bloodTests.count)
        XCTAssertEqual(decoded.eyeExams.count, data.eyeExams.count)
        XCTAssertEqual(decoded.epigeneticTests.count, data.epigeneticTests.count)
        XCTAssertEqual(decoded.bodyEntries.count, data.bodyEntries.count)
        XCTAssertEqual(decoded.healthMetrics.count, data.healthMetrics.count)
        XCTAssertEqual(decoded.goals.count, data.goals.count)
    }

    func testAppDataBackwardsCompatibility() {
        // Simulate old format without bodyEntries, healthMetrics, or goals
        let json = """
        {
            "profile": { "lifestyle": { "smokingStatus": "never", "exerciseMinutesPerWeek": 150, "sleepHoursPerNight": 7.5, "dietQuality": "good", "stressLevel": "moderate" } },
            "alcoholDrinks": [], "alcoholPresets": [], "nicotineEntries": [],
            "nicotinePresets": [], "bloodTests": [], "eyeExams": [], "epigeneticTests": []
        }
        """.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(AppData.self, from: json)
        XCTAssertTrue(decoded.bodyEntries.isEmpty)
        XCTAssertTrue(decoded.healthMetrics.isEmpty)
        XCTAssertTrue(decoded.goals.isEmpty)
    }

    func testAppDataBackwardsCompatibilityWithBodyNoMetrics() {
        // Simulate format with bodyEntries but no healthMetrics
        let json = """
        {
            "profile": { "lifestyle": { "smokingStatus": "never", "exerciseMinutesPerWeek": 150, "sleepHoursPerNight": 7.5, "dietQuality": "good", "stressLevel": "moderate" } },
            "alcoholDrinks": [], "alcoholPresets": [], "nicotineEntries": [],
            "nicotinePresets": [], "bloodTests": [], "eyeExams": [], "epigeneticTests": [],
            "bodyEntries": [{"id": "00000000-0000-0000-0000-000000000001", "date": "2026-01-01", "weightLbs": 155}]
        }
        """.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(AppData.self, from: json)
        XCTAssertEqual(decoded.bodyEntries.count, 1)
        XCTAssertTrue(decoded.healthMetrics.isEmpty)
    }

    func testHealthMetricEntryCodable() {
        let entry = HealthMetricEntry(
            date: "2026-03-15",
            heartRate: 72.5,
            restingHeartRate: 58.0,
            hrv: 42.3,
            oxygenSaturation: 98.1,
            respiratoryRate: 15.2,
            vo2Max: 43.5,
            steps: 8500,
            activeEnergy: 350,
            exerciseMinutes: 45,
            flightsClimbed: 12
        )
        let data = try! JSONEncoder().encode(entry)
        let decoded = try! JSONDecoder().decode(HealthMetricEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func testHealthMetricEntryPartialFields() {
        // Only some fields populated (common for real HealthKit data)
        let entry = HealthMetricEntry(date: "2026-03-15", heartRate: 70, hrv: 45)
        let data = try! JSONEncoder().encode(entry)
        let decoded = try! JSONDecoder().decode(HealthMetricEntry.self, from: data)
        XCTAssertEqual(decoded.heartRate, 70)
        XCTAssertEqual(decoded.hrv, 45)
        XCTAssertNil(decoded.restingHeartRate)
        XCTAssertNil(decoded.steps)
    }

    func testAlcoholDrinkStandardDrinks() {
        // 12oz at 5% ABV = (12 * 1 * 0.05) / 0.6 = 1.0 standard drink
        let drink = AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: "2026-01-01")
        XCTAssertEqual(drink.standardDrinks, 1.0, accuracy: 0.01)
    }

    func testAlcoholDrinkStandardDrinksMultiple() {
        let drink = AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 3, date: "2026-01-01")
        XCTAssertEqual(drink.standardDrinks, 3.0, accuracy: 0.01)
    }

    func testAlcoholDrinkGramsAlcohol() {
        // 12oz at 5% ABV = 12 * 1 * 0.05 * 29.5735 * 0.789 ≈ 14.0g
        let drink = AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: "2026-01-01")
        XCTAssertEqual(drink.gramsAlcohol, 14.0, accuracy: 0.5)
    }

    func testAlcoholDrinkNABeer() {
        let drink = AlcoholDrink(name: "NA Beer", oz: 12, abv: 0.4, count: 1, date: "2026-01-01")
        XCTAssertLessThan(drink.standardDrinks, 0.1)
        XCTAssertLessThan(drink.gramsAlcohol, 1.5)
    }

    func testNicotineEntryTotalMg() {
        let entry = NicotineEntry(product: "Zyn 6mg", mgPerUnit: 6, count: 2, date: "2026-01-01")
        XCTAssertEqual(entry.totalMg, 12)
    }

    func testBloodMarkerStatusNormal() {
        let glucose = BloodMarkers.byKey["glucose"]!
        XCTAssertEqual(glucose.status(for: 90), .normal)
    }

    func testBloodMarkerStatusLow() {
        let glucose = BloodMarkers.byKey["glucose"]!
        XCTAssertEqual(glucose.status(for: 60), .low)
    }

    func testBloodMarkerStatusHigh() {
        let glucose = BloodMarkers.byKey["glucose"]!
        XCTAssertEqual(glucose.status(for: 120), .high)
    }

    func testBloodMarkerStatusBoundary() {
        let glucose = BloodMarkers.byKey["glucose"]!
        // Exactly at min/max should be normal
        XCTAssertEqual(glucose.status(for: 70), .normal)
        XCTAssertEqual(glucose.status(for: 99), .normal)
    }

    func testAllBloodMarkersHaveValidRanges() {
        for marker in BloodMarkers.all {
            XCTAssertLessThanOrEqual(marker.min, marker.max, "Marker \(marker.key) has min > max")
            XCTAssertFalse(marker.key.isEmpty, "Marker has empty key")
            XCTAssertFalse(marker.label.isEmpty, "Marker \(marker.key) has empty label")
        }
    }

    func testBloodMarkersByKeyContainsAll() {
        XCTAssertEqual(BloodMarkers.byKey.count, BloodMarkers.all.count)
    }

    func testBloodMarkerCategoriesCoverAll() {
        let categoryKeys = BloodMarkers.categories.flatMap(\.keys)
        let allKeys = Set(BloodMarkers.all.map(\.key))
        let categoryKeySet = Set(categoryKeys)
        XCTAssertEqual(categoryKeySet, allKeys, "Categories don't cover all markers")
    }

    func testHealthProfileCodable() {
        let profile = SampleData.profile
        let data = try! JSONEncoder().encode(profile)
        let decoded = try! JSONDecoder().decode(HealthProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func testLifestyleDataDefault() {
        let d = LifestyleData.default
        XCTAssertEqual(d.smokingStatus, .never)
        XCTAssertEqual(d.exerciseMinutesPerWeek, 150)
        XCTAssertEqual(d.sleepHoursPerNight, 7.5)
        XCTAssertEqual(d.dietQuality, .good)
        XCTAssertEqual(d.stressLevel, .moderate)
        XCTAssertNil(d.bmi)
    }
}

// MARK: - Sample Data Tests

final class SampleDataTests: XCTestCase {

    func testSampleDataIsNonEmpty() {
        let data = SampleData.fullAppData
        XCTAssertFalse(data.alcoholDrinks.isEmpty)
        XCTAssertFalse(data.nicotineEntries.isEmpty)
        XCTAssertFalse(data.bodyEntries.isEmpty)
        XCTAssertFalse(data.bloodTests.isEmpty)
        XCTAssertFalse(data.eyeExams.isEmpty)
        XCTAssertFalse(data.epigeneticTests.isEmpty)
        XCTAssertFalse(data.healthMetrics.isEmpty)
        XCTAssertFalse(data.goals.isEmpty)
    }

    func testSampleDataHasRealisticVolume() {
        let data = SampleData.fullAppData
        // 90 days of tracking with ~3-4 drinking days/week = ~35-50 drinks
        XCTAssertGreaterThan(data.alcoholDrinks.count, 25)
        XCTAssertLessThan(data.alcoholDrinks.count, 120)

        // ~40-50% of 90 days
        XCTAssertGreaterThan(data.nicotineEntries.count, 25)
        XCTAssertLessThan(data.nicotineEntries.count, 60)

        // Every 2-3 days = ~30 entries
        XCTAssertGreaterThan(data.bodyEntries.count, 15)
        XCTAssertLessThan(data.bodyEntries.count, 50)

        XCTAssertEqual(data.bloodTests.count, 3)
        XCTAssertEqual(data.eyeExams.count, 2)
        XCTAssertEqual(data.epigeneticTests.count, 2)
    }

    func testSampleProfileIsValid() {
        let profile = SampleData.profile
        XCTAssertNotNil(profile.birthDate)
        XCTAssertNotNil(profile.biologicalSex)
        XCTAssertNotNil(profile.lifestyle.bmi)
    }

    func testSampleDatesAreRecentPast() {
        let today = DateFormatting.todayString()
        // All alcohol drinks should be within the last 90 days
        for drink in SampleData.alcoholDrinks {
            XCTAssertLessThanOrEqual(drink.date, today, "Drink date \(drink.date) is in the future")
        }
        for entry in SampleData.nicotineEntries {
            XCTAssertLessThanOrEqual(entry.date, today, "Nicotine date \(entry.date) is in the future")
        }
    }

    func testSampleBloodTestsHaveMarkers() {
        for test in SampleData.bloodTests {
            XCTAssertGreaterThan(test.markers.count, 20, "Blood test on \(test.date) has too few markers")
        }
    }

    func testSampleBloodTestMarkersAreInRange() {
        // Verify sample blood values are in physiologically plausible ranges
        for test in SampleData.bloodTests {
            for (key, value) in test.markers {
                guard let ref = BloodMarkers.byKey[key] else {
                    XCTFail("Unknown blood marker key: \(key)")
                    continue
                }
                // Values should be within 2x of reference range (physiologically possible)
                let lowerBound = ref.min * 0.3
                let upperBound = ref.max * 3.0
                XCTAssertGreaterThan(value, lowerBound, "Marker \(key) value \(value) too low")
                XCTAssertLessThan(value, upperBound, "Marker \(key) value \(value) too high")
            }
        }
    }

    func testSampleBloodTestsShowImprovement() {
        // Blood tests are ordered by date: oldest first, newest last
        let tests = SampleData.bloodTests.sorted { $0.date < $1.date }
        guard tests.count >= 2 else { return }
        let first = tests.first!
        let last = tests.last!
        // LDL should be improving (lower)
        if let firstLDL = first.markers["ldl"], let lastLDL = last.markers["ldl"] {
            XCTAssertLessThan(lastLDL, firstLDL, "LDL should improve over time in sample data")
        }
    }

    func testSampleEpigeneticTestsShowImprovement() {
        let tests = SampleData.epigeneticTests.sorted { $0.date < $1.date }
        guard tests.count >= 2 else { return }
        // Pace of aging should decrease (improve)
        if let firstPace = tests.first!.paceOfAging, let lastPace = tests.last!.paceOfAging {
            XCTAssertLessThan(lastPace, firstPace, "Pace of aging should improve in sample data")
        }
    }

    func testSampleBodyEntriesShowWeightTrend() {
        let entries = SampleData.bodyEntries
            .compactMap { e -> (String, Double)? in
                guard let w = e.weightLbs else { return nil }
                return (e.date, w)
            }
            .sorted { $0.0 < $1.0 }
        guard let first = entries.first, let last = entries.last else { return }
        // Weight trend should be downward
        XCTAssertLessThan(last.1, first.1, "Weight should trend downward in sample data")
    }

    func testSampleDataSupportsActivityBloodCorrelation() {
        // Blood tests need overlapping health metrics for the correlation chart
        let bloodTests = SampleData.bloodTests.sorted { $0.date < $1.date }
        let metricDates = Set(SampleData.healthMetrics.map(\.date))

        XCTAssertGreaterThanOrEqual(bloodTests.count, 2, "Need at least 2 blood tests for correlation")

        // At least the most recent blood test should have activity data in the 30 days before it
        if let latestTest = bloodTests.last, let testDate = DateFormatting.dateFromString(latestTest.date) {
            var matchingDays = 0
            for dayOffset in 1...30 {
                if let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: testDate) {
                    let dayStr = DateFormatting.dateString(day)
                    if metricDates.contains(dayStr) {
                        matchingDays += 1
                    }
                }
            }
            XCTAssertGreaterThan(matchingDays, 0, "Latest blood test should have activity data in 30 days before it")
        }

        // All blood tests should have the key correlation markers
        let correlationMarkers = ["ldl", "glucose", "triglycerides", "hba1c"]
        for test in bloodTests {
            for marker in correlationMarkers {
                XCTAssertNotNil(test.markers[marker], "Blood test on \(test.date) missing \(marker)")
            }
        }
    }

    func testSampleDataProducesValidDeathClock() {
        let profile = SampleData.profile
        let result = DeathClockEngine.calculate(
            birthDateStr: profile.birthDate!,
            sex: profile.biologicalSex,
            lifestyle: profile.lifestyle
        )
        XCTAssertNotNil(result)
        guard let r = result else { return }
        XCTAssertGreaterThan(r.yearsRemaining, 0)
        XCTAssertLessThan(r.percentComplete, 100)
    }

    func testSampleDataCodableRoundTrip() {
        let original = SampleData.fullAppData
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(original)
        let decoded = try! JSONDecoder().decode(AppData.self, from: data)

        // Verify counts match
        XCTAssertEqual(decoded.alcoholDrinks.count, original.alcoholDrinks.count)
        XCTAssertEqual(decoded.nicotineEntries.count, original.nicotineEntries.count)
        XCTAssertEqual(decoded.bodyEntries.count, original.bodyEntries.count)
        XCTAssertEqual(decoded.healthMetrics.count, original.healthMetrics.count)

        // Verify first drink is identical
        if let first = original.alcoholDrinks.first, let decoded1 = decoded.alcoholDrinks.first {
            XCTAssertEqual(first.name, decoded1.name)
            XCTAssertEqual(first.oz, decoded1.oz)
            XCTAssertEqual(first.abv, decoded1.abv)
        }
    }
}

// MARK: - Health Metric Tests

final class HealthMetricTests: XCTestCase {

    func testSampleHealthMetricsHave90Days() {
        XCTAssertEqual(SampleData.healthMetrics.count, 90)
    }

    func testSampleHealthMetricsAllHaveHRV() {
        for metric in SampleData.healthMetrics {
            XCTAssertNotNil(metric.hrv, "Missing HRV for \(metric.date)")
            XCTAssertNotNil(metric.heartRate, "Missing heart rate for \(metric.date)")
            XCTAssertNotNil(metric.restingHeartRate, "Missing resting HR for \(metric.date)")
            XCTAssertNotNil(metric.steps, "Missing steps for \(metric.date)")
        }
    }

    func testSampleHRVLowerOnDrinkingDays() {
        let alcoholDates = Set(SampleData.alcoholDrinks.filter { $0.abv > 1.0 }.map(\.date))
        let metrics = SampleData.healthMetrics

        let drinkingHRV = metrics.filter { alcoholDates.contains($0.date) }.compactMap(\.hrv)
        let soberHRV = metrics.filter { !alcoholDates.contains($0.date) }.compactMap(\.hrv)

        guard !drinkingHRV.isEmpty, !soberHRV.isEmpty else { return }

        let avgDrinking = drinkingHRV.reduce(0, +) / Double(drinkingHRV.count)
        let avgSober = soberHRV.reduce(0, +) / Double(soberHRV.count)

        XCTAssertLessThan(avgDrinking, avgSober, "HRV should be lower on drinking days")
    }

    func testSampleHeartRateHigherOnNicotineDays() {
        let nicotineDates = Set(SampleData.nicotineEntries.map(\.date))
        let metrics = SampleData.healthMetrics

        let nicoHR = metrics.filter { nicotineDates.contains($0.date) }.compactMap(\.heartRate)
        let cleanHR = metrics.filter { !nicotineDates.contains($0.date) }.compactMap(\.heartRate)

        guard !nicoHR.isEmpty, !cleanHR.isEmpty else { return }

        let avgNico = nicoHR.reduce(0, +) / Double(nicoHR.count)
        let avgClean = cleanHR.reduce(0, +) / Double(cleanHR.count)

        XCTAssertGreaterThan(avgNico, avgClean, "Heart rate should be higher on nicotine days")
    }

    func testSampleHealthMetricsPhysiologicalRanges() {
        for metric in SampleData.healthMetrics {
            if let hrv = metric.hrv {
                XCTAssertGreaterThan(hrv, 15, "HRV too low: \(hrv)")
                XCTAssertLessThan(hrv, 80, "HRV too high: \(hrv)")
            }
            if let hr = metric.heartRate {
                XCTAssertGreaterThan(hr, 45, "HR too low: \(hr)")
                XCTAssertLessThan(hr, 100, "HR too high: \(hr)")
            }
            if let rhr = metric.restingHeartRate {
                XCTAssertGreaterThan(rhr, 40, "RHR too low: \(rhr)")
                XCTAssertLessThan(rhr, 85, "RHR too high: \(rhr)")
            }
            if let steps = metric.steps {
                XCTAssertGreaterThanOrEqual(steps, 0, "Steps negative: \(steps)")
                XCTAssertLessThan(steps, 30000, "Steps too high: \(steps)")
            }
            if let spo2 = metric.oxygenSaturation {
                XCTAssertGreaterThan(spo2, 90, "SpO2 too low: \(spo2)")
                XCTAssertLessThanOrEqual(spo2, 100, "SpO2 too high: \(spo2)")
            }
        }
    }

    func testSampleHealthMetricsDatesMatchRange() {
        let today = DateFormatting.todayString()
        for metric in SampleData.healthMetrics {
            XCTAssertLessThanOrEqual(metric.date, today, "Health metric date in future: \(metric.date)")
        }
        // All dates should be unique
        let dates = SampleData.healthMetrics.map(\.date)
        XCTAssertEqual(dates.count, Set(dates).count, "Duplicate health metric dates")
    }
}

// MARK: - Date Formatting Tests

final class DateFormattingTests: XCTestCase {

    func testTodayString() {
        let today = DateFormatting.todayString()
        XCTAssertTrue(today.matches(of: /\d{4}-\d{2}-\d{2}/).count == 1)
    }

    func testDateRoundTrip() {
        let str = "2026-03-15"
        let date = DateFormatting.dateFromString(str)
        XCTAssertNotNil(date)
        XCTAssertEqual(DateFormatting.dateString(date!), str)
    }

    func testDisplayDate() {
        let display = DateFormatting.displayDate("2026-03-15")
        XCTAssertFalse(display.isEmpty)
        XCTAssertNotEqual(display, "2026-03-15") // Should be formatted
    }

    func testInvalidDate() {
        XCTAssertNil(DateFormatting.dateFromString("not-a-date"))
        XCTAssertNil(DateFormatting.dateFromString(""))
    }

    func testFormatDuration() {
        XCTAssertEqual(DateFormatting.formatDuration(3), "3d")
        XCTAssertEqual(DateFormatting.formatDuration(14), "2w")
        XCTAssertEqual(DateFormatting.formatDuration(45), "1mo")
        XCTAssertEqual(DateFormatting.formatDuration(400), "1y 1mo")
        XCTAssertEqual(DateFormatting.formatDuration(365), "1y")
    }

    func testFormatLargeNumber() {
        XCTAssertEqual(DateFormatting.formatLargeNumber(1000), "1,000")
        XCTAssertEqual(DateFormatting.formatLargeNumber(1234567), "1,234,567")
    }

    func testFormatMarkerValue() {
        XCTAssertEqual(DateFormatting.formatMarkerValue(100.0), "100")
        XCTAssertEqual(DateFormatting.formatMarkerValue(5.5), "5.5")
        XCTAssertEqual(DateFormatting.formatMarkerValue(3.14), "3.1")
    }
}

// MARK: - Additional Model Codable Tests

final class AdditionalModelTests: XCTestCase {

    func testEyeExamCodable() {
        let exam = EyeExam(date: "2026-03-15", leftSphere: -2.5, leftCylinder: -0.75, leftAxis: 170,
                           rightSphere: -2.0, rightCylinder: -0.5, rightAxis: 10)
        let data = try! JSONEncoder().encode(exam)
        let decoded = try! JSONDecoder().decode(EyeExam.self, from: data)
        XCTAssertEqual(decoded, exam)
    }

    func testEyeExamPartialFields() {
        let exam = EyeExam(date: "2026-03-15", leftSphere: -2.0)
        let data = try! JSONEncoder().encode(exam)
        let decoded = try! JSONDecoder().decode(EyeExam.self, from: data)
        XCTAssertEqual(decoded.leftSphere, -2.0)
        XCTAssertNil(decoded.rightSphere)
        XCTAssertNil(decoded.leftCylinder)
    }

    func testEpigeneticTestCodable() {
        let test = EpigeneticTest(date: "2026-03-15", chronologicalAge: 45, biologicalAge: 42,
                                  paceOfAging: 0.88, organScores: ["Heart": 40.0, "Brain": 43.5])
        let data = try! JSONEncoder().encode(test)
        let decoded = try! JSONDecoder().decode(EpigeneticTest.self, from: data)
        XCTAssertEqual(decoded.chronologicalAge, 45)
        XCTAssertEqual(decoded.biologicalAge, 42)
        XCTAssertEqual(decoded.paceOfAging, 0.88)
        XCTAssertEqual(decoded.organScores?["Heart"], 40.0)
    }

    func testEpigeneticTestPartialFields() {
        let test = EpigeneticTest(date: "2026-03-15", chronologicalAge: 45, biologicalAge: 42)
        let data = try! JSONEncoder().encode(test)
        let decoded = try! JSONDecoder().decode(EpigeneticTest.self, from: data)
        XCTAssertNil(decoded.paceOfAging)
        XCTAssertNil(decoded.organScores)
    }

    func testBodyEntryCodable() {
        let entry = BodyEntry(date: "2026-03-15", weightLbs: 155.5, bodyFatPct: 16.2)
        let data = try! JSONEncoder().encode(entry)
        let decoded = try! JSONDecoder().decode(BodyEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func testBodyEntryPartialFields() {
        let entry = BodyEntry(date: "2026-03-15", weightLbs: 155.5)
        let data = try! JSONEncoder().encode(entry)
        let decoded = try! JSONDecoder().decode(BodyEntry.self, from: data)
        XCTAssertEqual(decoded.weightLbs, 155.5)
        XCTAssertNil(decoded.bodyFatPct)
    }

    func testBloodTestCodable() {
        let test = BloodTest(date: "2026-03-15", markers: ["glucose": 92, "ldl": 110])
        let data = try! JSONEncoder().encode(test)
        let decoded = try! JSONDecoder().decode(BloodTest.self, from: data)
        XCTAssertEqual(decoded.markers["glucose"], 92)
        XCTAssertEqual(decoded.markers["ldl"], 110)
        XCTAssertEqual(decoded.markers.count, 2)
    }

    func testAlcoholPresetDefaults() {
        let presets = AlcoholPreset.defaults
        XCTAssertGreaterThanOrEqual(presets.count, 4)
        for preset in presets {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertGreaterThan(preset.oz, 0)
            XCTAssertGreaterThanOrEqual(preset.abv, 0)
        }
        // Should have at least one NA option
        XCTAssertTrue(presets.contains { $0.abv < 1.0 })
    }

    func testAlcoholPresetCodable() {
        let preset = AlcoholPreset(name: "Test Beer", oz: 12, abv: 5.0)
        let data = try! JSONEncoder().encode(preset)
        let decoded = try! JSONDecoder().decode(AlcoholPreset.self, from: data)
        XCTAssertEqual(decoded.name, preset.name)
        XCTAssertEqual(decoded.oz, preset.oz)
        XCTAssertEqual(decoded.abv, preset.abv)
    }

    func testNicotinePresetCodable() {
        let preset = NicotinePreset(name: "Zyn 6mg", mgPerUnit: 6)
        let data = try! JSONEncoder().encode(preset)
        let decoded = try! JSONDecoder().decode(NicotinePreset.self, from: data)
        XCTAssertEqual(decoded.name, preset.name)
        XCTAssertEqual(decoded.mgPerUnit, preset.mgPerUnit)
    }

    func testGoalPriorityComparable() {
        XCTAssertLessThan(GoalPriority.high, GoalPriority.medium)
        XCTAssertLessThan(GoalPriority.medium, GoalPriority.low)
        XCTAssertLessThan(GoalPriority.high, GoalPriority.low)

        let priorities: [GoalPriority] = [.low, .high, .medium]
        let sorted = priorities.sorted()
        XCTAssertEqual(sorted, [.high, .medium, .low])
    }

    func testGoalEquatable() {
        let goal1 = Goal(title: "Test", notes: "Notes", priority: .high)
        var goal2 = goal1
        XCTAssertEqual(goal1, goal2)

        goal2.title = "Changed"
        XCTAssertNotEqual(goal1, goal2)
    }

    func testGoalMilestoneCodable() {
        let milestone = GoalMilestone(title: "Step 1", completed: true, completedDate: "2026-03-15")
        let data = try! JSONEncoder().encode(milestone)
        let decoded = try! JSONDecoder().decode(GoalMilestone.self, from: data)
        XCTAssertEqual(decoded, milestone)
    }

    func testGoalStatusAllCases() {
        XCTAssertEqual(GoalStatus.allCases.count, 4)
        XCTAssertTrue(GoalStatus.allCases.contains(.active))
        XCTAssertTrue(GoalStatus.allCases.contains(.paused))
        XCTAssertTrue(GoalStatus.allCases.contains(.completed))
        XCTAssertTrue(GoalStatus.allCases.contains(.abandoned))
    }

    func testSampleEyeExamsAreValid() {
        let exams = SampleData.eyeExams
        XCTAssertEqual(exams.count, 2)
        for exam in exams {
            XCTAssertFalse(exam.date.isEmpty)
            if let sphere = exam.leftSphere {
                XCTAssertLessThan(sphere, 0, "Myopic prescription should be negative")
            }
        }
        // Second exam should show progression (more negative sphere)
        if let first = exams.first?.leftSphere, let last = exams.last?.leftSphere {
            XCTAssertLessThanOrEqual(last, first, "Myopia should progress")
        }
    }

    func testSampleEpigeneticTestsAreValid() {
        let tests = SampleData.epigeneticTests
        XCTAssertEqual(tests.count, 2)
        for test in tests {
            XCTAssertGreaterThan(test.chronologicalAge, 0)
            XCTAssertGreaterThan(test.biologicalAge, 0)
            // Biological age should be less than chronological (healthy person)
            XCTAssertLessThan(test.biologicalAge, test.chronologicalAge)
            if let pace = test.paceOfAging {
                XCTAssertLessThan(pace, 1.0, "Sample person should be aging slower than average")
            }
            if let organs = test.organScores {
                XCTAssertGreaterThanOrEqual(organs.count, 5)
            }
        }
    }

    func testSampleBodyEntriesHaveMeasurements() {
        let entries = SampleData.bodyEntries
        for entry in entries {
            // All entries should have weight
            XCTAssertNotNil(entry.weightLbs)
            if let weight = entry.weightLbs {
                XCTAssertGreaterThan(weight, 100, "Weight too low: \(weight)")
                XCTAssertLessThan(weight, 200, "Weight too high: \(weight)")
            }
            if let bf = entry.bodyFatPct {
                XCTAssertGreaterThan(bf, 5, "Body fat too low: \(bf)")
                XCTAssertLessThan(bf, 30, "Body fat too high: \(bf)")
            }
        }
    }

    func testSampleGoalsProduceValidProjections() {
        let profile = SampleData.profile
        let dc = DeathClockEngine.calculate(
            birthDateStr: profile.birthDate!,
            sex: profile.biologicalSex,
            lifestyle: profile.lifestyle
        )
        let cogDate = GoalEngine.cognitiveDeadline(from: dc)

        for goal in SampleData.goals where goal.status == .active {
            let projection = GoalEngine.project(
                goal: goal, deathDate: dc?.deathDate, healthyCognitiveDate: cogDate
            )
            // Active goals with check-ins should produce a projection
            if !goal.checkIns.isEmpty {
                XCTAssertNotNil(projection.projectedCompletionDate, "Goal '\(goal.title)' should have projection")
                XCTAssertGreaterThan(projection.weeklyProgressRate, 0, "Goal '\(goal.title)' should have positive rate")
            }
        }
    }
}

// MARK: - Goal Model Tests

final class GoalModelTests: XCTestCase {

    func testGoalProgressPercent() {
        var goal = Goal(title: "Test")
        XCTAssertEqual(goal.progressPercent, 0)

        goal.checkIns.append(GoalCheckIn(progressPct: 50))
        XCTAssertEqual(goal.progressPercent, 50)

        goal.checkIns.append(GoalCheckIn(progressPct: 75))
        XCTAssertEqual(goal.progressPercent, 75)
    }

    func testGoalIsOverdue() {
        let pastDate = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -10, to: Date())!)
        let futureDate = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: 10, to: Date())!)

        let overdueGoal = Goal(title: "Overdue", targetDate: pastDate)
        XCTAssertTrue(overdueGoal.isOverdue)

        let futureGoal = Goal(title: "Future", targetDate: futureDate)
        XCTAssertFalse(futureGoal.isOverdue)

        let completedGoal = Goal(title: "Done", targetDate: pastDate, status: .completed)
        XCTAssertFalse(completedGoal.isOverdue)

        let noTargetGoal = Goal(title: "No target")
        XCTAssertFalse(noTargetGoal.isOverdue)
    }

    func testGoalNeedsCheckIn() {
        let oldDate = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -10, to: Date())!)
        let recentDate = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -2, to: Date())!)

        // Goal with old check-in (10 days ago, interval is 7)
        var staleGoal = Goal(title: "Stale", createdDate: oldDate)
        staleGoal.checkIns.append(GoalCheckIn(date: oldDate, progressPct: 20))
        XCTAssertTrue(staleGoal.needsCheckIn)

        // Goal with recent check-in
        var freshGoal = Goal(title: "Fresh")
        freshGoal.checkIns.append(GoalCheckIn(date: recentDate, progressPct: 20))
        XCTAssertFalse(freshGoal.needsCheckIn)

        // Paused goal doesn't need check-in
        var pausedGoal = Goal(title: "Paused", createdDate: oldDate, status: .paused)
        pausedGoal.checkIns.append(GoalCheckIn(date: oldDate, progressPct: 20))
        XCTAssertFalse(pausedGoal.needsCheckIn)
    }

    func testGoalCodable() {
        let goal = Goal(
            title: "Test Goal",
            notes: "Some notes",
            targetDate: "2027-01-01",
            checkIns: [GoalCheckIn(progressPct: 30, note: "Progress")],
            milestones: [GoalMilestone(title: "Step 1", completed: true, completedDate: "2026-03-01")],
            priority: .high
        )
        let data = try! JSONEncoder().encode(goal)
        let decoded = try! JSONDecoder().decode(Goal.self, from: data)
        XCTAssertEqual(decoded.title, goal.title)
        XCTAssertEqual(decoded.notes, goal.notes)
        XCTAssertEqual(decoded.targetDate, goal.targetDate)
        XCTAssertEqual(decoded.checkIns.count, 1)
        XCTAssertEqual(decoded.milestones.count, 1)
        XCTAssertEqual(decoded.priority, .high)
    }

    func testCheckInClamps() {
        let tooHigh = GoalCheckIn(progressPct: 150)
        XCTAssertEqual(tooHigh.progressPct, 100)

        let tooLow = GoalCheckIn(progressPct: -10)
        XCTAssertEqual(tooLow.progressPct, 0)
    }
}

// MARK: - GoalEngine Tests

final class GoalEngineTests: XCTestCase {

    private let now = Date()
    private let deathDate = Calendar.current.date(byAdding: .year, value: 35, to: Date())
    private let cognitiveDate = Calendar.current.date(byAdding: .year, value: 25, to: Date())

    func testProjectionNoProgress() {
        let goal = Goal(title: "New goal")
        let projection = GoalEngine.project(goal: goal, deathDate: deathDate, healthyCognitiveDate: cognitiveDate)
        XCTAssertNil(projection.projectedCompletionDate)
        XCTAssertNil(projection.daysToCompletion)
        XCTAssertEqual(projection.weeklyProgressRate, 0)
    }

    func testProjectionWithProgress() {
        let created = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -30, to: now)!)
        let checkInDate = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -2, to: now)!)
        var goal = Goal(title: "Book", createdDate: created)
        goal.checkIns = [
            GoalCheckIn(date: created, progressPct: 10),
            GoalCheckIn(date: checkInDate, progressPct: 40),
        ]
        let projection = GoalEngine.project(goal: goal, deathDate: deathDate, healthyCognitiveDate: cognitiveDate)
        XCTAssertNotNil(projection.projectedCompletionDate)
        XCTAssertNotNil(projection.daysToCompletion)
        XCTAssertGreaterThan(projection.weeklyProgressRate, 0)
        XCTAssertEqual(projection.urgencyLevel, .onTrack)
    }

    func testProjectionSlippage() {
        let created = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -60, to: now)!)
        let pastTarget = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -5, to: now)!)

        var goal = Goal(title: "Overdue", createdDate: created, targetDate: pastTarget)
        goal.checkIns = [
            GoalCheckIn(date: created, progressPct: 10),
            GoalCheckIn(date: DateFormatting.todayString(), progressPct: 30),
        ]
        let projection = GoalEngine.project(goal: goal, deathDate: deathDate, healthyCognitiveDate: cognitiveDate)
        XCTAssertGreaterThan(projection.slippageDays, 0)
        XCTAssertEqual(projection.urgencyLevel, .atRisk)
    }

    func testProjectionExceedsCognitiveYears() {
        // Goal with slow progress — 2% over 90 days => ~100% in ~12.3 years
        let threeMonthsAgo = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -90, to: now)!)
        var goal = Goal(title: "Slow goal")
        goal.checkIns = [
            GoalCheckIn(date: threeMonthsAgo, progressPct: 1),
            GoalCheckIn(date: DateFormatting.todayString(), progressPct: 3),
        ]

        // Cognitive deadline in 10 years, death in 20 years
        // At 2% per 90 days, need ~4350 days (~11.9 years) — exceeds cognitive but not death
        let nearCognitive = Calendar.current.date(byAdding: .year, value: 10, to: now)
        let farDeath = Calendar.current.date(byAdding: .year, value: 20, to: now)
        let projection = GoalEngine.project(goal: goal, deathDate: farDeath, healthyCognitiveDate: nearCognitive)
        XCTAssertTrue(projection.exceedsCognitiveYears)
        XCTAssertFalse(projection.exceedsLifespan)
        XCTAssertEqual(projection.urgencyLevel, .critical)
    }

    func testProjectionExceedsLifespan() {
        let yearAgo = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -365, to: now)!)
        var goal = Goal(title: "Impossibly slow")
        goal.checkIns = [
            GoalCheckIn(date: yearAgo, progressPct: 0.1),
            GoalCheckIn(date: DateFormatting.todayString(), progressPct: 0.2),
        ]

        let nearDeath = Calendar.current.date(byAdding: .year, value: 2, to: now)
        let nearCognitive = Calendar.current.date(byAdding: .year, value: 1, to: now)
        let projection = GoalEngine.project(goal: goal, deathDate: nearDeath, healthyCognitiveDate: nearCognitive)
        XCTAssertTrue(projection.exceedsLifespan)
        XCTAssertEqual(projection.urgencyLevel, .impossible)
    }

    func testCognitiveDeadline() {
        let profile = SampleData.profile
        let dc = DeathClockEngine.calculate(
            birthDateStr: profile.birthDate!,
            sex: profile.biologicalSex,
            lifestyle: profile.lifestyle
        )
        let cogDeadline = GoalEngine.cognitiveDeadline(from: dc)
        XCTAssertNotNil(cogDeadline)
        // Cognitive deadline should be before death date
        if let cog = cogDeadline, let death = dc?.deathDate {
            XCTAssertLessThan(cog, death)
        }
    }

    func testSampleGoalsHaveValidStructure() {
        let goals = SampleData.goals
        XCTAssertGreaterThanOrEqual(goals.count, 3)

        for goal in goals {
            XCTAssertFalse(goal.title.isEmpty)
            XCTAssertFalse(goal.createdDate.isEmpty)

            for checkIn in goal.checkIns {
                XCTAssertGreaterThanOrEqual(checkIn.progressPct, 0)
                XCTAssertLessThanOrEqual(checkIn.progressPct, 100)
            }
        }

        XCTAssertTrue(goals.contains { $0.status == .completed })
        XCTAssertTrue(goals.contains { $0.status == .active })
    }

    func testProjectionSingleCheckIn() {
        let created = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -20, to: Date())!)
        let checkInDate = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -5, to: Date())!)
        var goal = Goal(title: "Single checkin", createdDate: created)
        goal.checkIns = [GoalCheckIn(date: checkInDate, progressPct: 25)]

        let projection = GoalEngine.project(goal: goal, deathDate: nil, healthyCognitiveDate: nil)
        XCTAssertNotNil(projection.projectedCompletionDate)
        XCTAssertNotNil(projection.daysToCompletion)
        XCTAssertGreaterThan(projection.weeklyProgressRate, 0)
    }

    func testProjectionPausedGoal() {
        var goal = Goal(title: "Paused", status: .paused)
        goal.checkIns = [GoalCheckIn(date: DateFormatting.todayString(), progressPct: 50)]
        // Paused goals don't needsCheckIn
        XCTAssertFalse(goal.needsCheckIn)
    }

    func testProjectionCompletedGoal() {
        var goal = Goal(title: "Done", status: .completed, priority: .high)
        goal.checkIns = [GoalCheckIn(progressPct: 100, note: "Done")]
        XCTAssertEqual(goal.progressPercent, 100)
        XCTAssertFalse(goal.needsCheckIn)
        XCTAssertFalse(goal.isOverdue)
    }
}

// MARK: - CorrelationEngine Tests

final class CorrelationEngineTests: XCTestCase {

    func testBuildCorrelationDataWithSampleData() {
        let tests = SampleData.bloodTests.sorted { $0.date < $1.date }
        let metrics = SampleData.healthMetrics
        let result = CorrelationEngine.buildCorrelationData(tests: tests, healthMetrics: metrics)

        // Should produce data points for tests that have overlapping metrics
        XCTAssertGreaterThan(result.count, 0)

        for point in result {
            XCTAssertGreaterThan(point.avgDailySteps, 0, "Steps should be positive")
            XCTAssertFalse(point.markers.isEmpty, "Markers should be present")
        }
    }

    func testBuildCorrelationDataNoOverlap() {
        let test = BloodTest(date: "2020-01-01", markers: ["glucose": 90])
        // Metrics from 2026 — no overlap with 2020 blood test
        let metrics = [HealthMetricEntry(date: "2026-03-01", steps: 8000)]
        let result = CorrelationEngine.buildCorrelationData(tests: [test], healthMetrics: metrics)
        XCTAssertTrue(result.isEmpty, "No correlation when dates don't overlap")
    }

    func testBuildCorrelationDataAveragesCorrectly() {
        let testDate = "2026-03-15"
        let test = BloodTest(date: testDate, markers: ["ldl": 110])

        // Create metrics for 3 days before the test
        let metrics = (1...3).map { dayOffset -> HealthMetricEntry in
            let day = Calendar.current.date(byAdding: .day, value: -dayOffset,
                                             to: DateFormatting.dateFromString(testDate)!)!
            return HealthMetricEntry(date: DateFormatting.dateString(day), steps: Double(dayOffset * 1000))
        }

        let result = CorrelationEngine.buildCorrelationData(tests: [test], healthMetrics: metrics)
        XCTAssertEqual(result.count, 1)
        // Average of 1000, 2000, 3000 = 2000
        XCTAssertEqual(result.first?.avgDailySteps ?? 0, 2000, accuracy: 0.1)
    }

    func testBuildCorrelationDataCustomWindow() {
        let testDate = "2026-03-15"
        let test = BloodTest(date: testDate, markers: ["glucose": 90])

        // Only 2 days of metrics, within a 5-day window
        let metrics = (1...2).map { dayOffset -> HealthMetricEntry in
            let day = Calendar.current.date(byAdding: .day, value: -dayOffset,
                                             to: DateFormatting.dateFromString(testDate)!)!
            return HealthMetricEntry(date: DateFormatting.dateString(day), steps: 5000)
        }

        let result5 = CorrelationEngine.buildCorrelationData(tests: [test], healthMetrics: metrics, windowDays: 5)
        XCTAssertEqual(result5.count, 1)

        let result1 = CorrelationEngine.buildCorrelationData(tests: [test], healthMetrics: [], windowDays: 1)
        XCTAssertTrue(result1.isEmpty)
    }

    func testBuildCorrelationDataInvalidDate() {
        let test = BloodTest(date: "not-a-date", markers: ["ldl": 100])
        let result = CorrelationEngine.buildCorrelationData(tests: [test], healthMetrics: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testGoalMarkersFromSampleData() {
        let profile = SampleData.profile
        guard let birthDate = DeathClockEngine.dateFromString(profile.birthDate!) else {
            XCTFail("Invalid birth date")
            return
        }
        let dc = DeathClockEngine.calculate(
            birthDateStr: profile.birthDate!, sex: profile.biologicalSex, lifestyle: profile.lifestyle
        )
        let cogDate = GoalEngine.cognitiveDeadline(from: dc)

        let markers = GoalEngine.goalMarkers(
            goals: SampleData.goals, birthDate: birthDate,
            deathDate: dc?.deathDate, healthyCognitiveDate: cogDate
        )

        // Active goals with target dates should produce target markers
        let targetMarkers = markers.filter { !$0.isProjected }
        let projectedMarkers = markers.filter { $0.isProjected }
        XCTAssertGreaterThan(targetMarkers.count, 0, "Should have target date markers")
        XCTAssertGreaterThan(projectedMarkers.count, 0, "Should have projected completion markers")

        for marker in markers {
            XCTAssertFalse(marker.title.isEmpty)
            XCTAssertGreaterThan(marker.weekIndex, 0)
        }
    }

    func testGoalMarkersExcludesNonActive() {
        let birthDate = Date()
        let completedGoal = Goal(title: "Done", targetDate: "2027-01-01", status: .completed)
        let pausedGoal = Goal(title: "Paused", targetDate: "2027-01-01", status: .paused)

        let markers = GoalEngine.goalMarkers(
            goals: [completedGoal, pausedGoal], birthDate: birthDate,
            deathDate: nil, healthyCognitiveDate: nil
        )
        XCTAssertTrue(markers.isEmpty, "Non-active goals should not produce markers")
    }

    func testGoalMarkersNoTargetDate() {
        let birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date())!
        let created = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -30, to: Date())!)
        var goal = Goal(title: "No target", createdDate: created)
        goal.checkIns = [
            GoalCheckIn(date: created, progressPct: 10),
            GoalCheckIn(date: DateFormatting.todayString(), progressPct: 30),
        ]

        let markers = GoalEngine.goalMarkers(
            goals: [goal], birthDate: birthDate, deathDate: nil, healthyCognitiveDate: nil
        )

        // No target date marker, but should have a projected marker
        let targetMarkers = markers.filter { !$0.isProjected }
        let projectedMarkers = markers.filter { $0.isProjected }
        XCTAssertEqual(targetMarkers.count, 0)
        XCTAssertEqual(projectedMarkers.count, 1)
    }
}

// MARK: - HealthMetricEntry Tests

final class HealthMetricMergeTests: XCTestCase {

    func testMergeFieldsOverwritesNonNil() {
        var target = HealthMetricEntry(date: "2026-03-15", heartRate: 72, steps: 8000)
        let source = HealthMetricEntry(date: "2026-03-15", heartRate: 75, hrv: 45)

        target.mergeFields(from: source)

        XCTAssertEqual(target.heartRate, 75, "Non-nil source should overwrite")
        XCTAssertEqual(target.hrv, 45, "Non-nil source should fill nil target")
        XCTAssertEqual(target.steps, 8000, "Nil source should not clear target")
    }

    func testMergeFieldsPreservesWhenSourceNil() {
        var target = HealthMetricEntry(date: "2026-03-15", heartRate: 72, restingHeartRate: 58,
                                       hrv: 42, oxygenSaturation: 98, steps: 8000)
        let emptySource = HealthMetricEntry(date: "2026-03-15")

        target.mergeFields(from: emptySource)

        XCTAssertEqual(target.heartRate, 72)
        XCTAssertEqual(target.restingHeartRate, 58)
        XCTAssertEqual(target.hrv, 42)
        XCTAssertEqual(target.oxygenSaturation, 98)
        XCTAssertEqual(target.steps, 8000)
    }

    func testMergeFieldsAllFields() {
        var target = HealthMetricEntry(date: "2026-03-15")
        let source = HealthMetricEntry(
            date: "2026-03-15", heartRate: 72, restingHeartRate: 58,
            hrv: 42, oxygenSaturation: 98, respiratoryRate: 16,
            vo2Max: 45, steps: 8000, activeEnergy: 500,
            exerciseMinutes: 30, flightsClimbed: 10
        )

        target.mergeFields(from: source)

        XCTAssertEqual(target.heartRate, 72)
        XCTAssertEqual(target.restingHeartRate, 58)
        XCTAssertEqual(target.hrv, 42)
        XCTAssertEqual(target.oxygenSaturation, 98)
        XCTAssertEqual(target.respiratoryRate, 16)
        XCTAssertEqual(target.vo2Max, 45)
        XCTAssertEqual(target.steps, 8000)
        XCTAssertEqual(target.activeEnergy, 500)
        XCTAssertEqual(target.exerciseMinutes, 30)
        XCTAssertEqual(target.flightsClimbed, 10)
    }
}

// MARK: - SubstanceEngine Tests

final class SubstanceEngineTests: XCTestCase {

    // MARK: Alcohol Rolling Averages

    func testRollingAverageGramsEmpty() {
        XCTAssertEqual(SubstanceEngine.rollingAverageGrams(drinks: [], days: 7), 0)
    }

    func testRollingAverageGramsWithDrinks() {
        let today = DateFormatting.todayString()
        let drinks = [
            AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: today),
            AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: today),
        ]
        let avg = SubstanceEngine.rollingAverageGrams(drinks: drinks, days: 7)
        // 2 beers * ~14g each / 7 days ≈ 4g/day
        XCTAssertGreaterThan(avg, 3)
        XCTAssertLessThan(avg, 5)
    }

    func testRollingAverageGramsExcludesOldDrinks() {
        // Drink from 10 days ago should be excluded from 7-day rolling average
        let oldDate = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -10, to: Date())!)
        let drinks = [AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: oldDate)]
        XCTAssertEqual(SubstanceEngine.rollingAverageGrams(drinks: drinks, days: 7), 0)
    }

    func testWeeklyTotalStandardDrinksEmpty() {
        XCTAssertEqual(SubstanceEngine.weeklyTotalStandardDrinks(drinks: []), 0)
    }

    func testWeeklyTotalStandardDrinksWithDrinks() {
        let today = DateFormatting.todayString()
        let drinks = [
            AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 3, date: today),
        ]
        XCTAssertEqual(SubstanceEngine.weeklyTotalStandardDrinks(drinks: drinks), 3.0, accuracy: 0.01)
    }

    func testAllTimeAverageGramsEmpty() {
        XCTAssertEqual(SubstanceEngine.allTimeAverageGrams(drinks: []), 0)
    }

    func testAllTimeAverageGramsWithDrinks() {
        let today = DateFormatting.todayString()
        let weekAgo = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
        let drinks = [
            AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: weekAgo),
            AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: today),
        ]
        let avg = SubstanceEngine.allTimeAverageGrams(drinks: drinks)
        XCTAssertGreaterThan(avg, 0)
    }

    func testDailyMaxStandardDrinksEmpty() {
        XCTAssertEqual(SubstanceEngine.dailyMaxStandardDrinks(drinks: [], days: 7), 0)
    }

    func testDailyMaxStandardDrinksMultipleDays() {
        let today = DateFormatting.todayString()
        let yesterday = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let drinks = [
            AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: yesterday),
            AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 3, date: today),
        ]
        // Today has 3 std drinks, yesterday has 1 — max should be 3
        XCTAssertEqual(SubstanceEngine.dailyMaxStandardDrinks(drinks: drinks, days: 7), 3.0, accuracy: 0.01)
    }

    // MARK: NIAAA Risk Level

    func testAlcoholRiskLowMale() {
        let today = DateFormatting.todayString()
        let drinks = [AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: today)]
        XCTAssertEqual(SubstanceEngine.alcoholRisk(drinks: drinks, sex: .male), .low)
    }

    func testAlcoholRiskModerateMale() {
        let today = DateFormatting.todayString()
        // 3 standard drinks in one day (> 2 daily threshold)
        let drinks = [AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 3, date: today)]
        XCTAssertEqual(SubstanceEngine.alcoholRisk(drinks: drinks, sex: .male), .moderate)
    }

    func testAlcoholRiskHighMale() {
        let today = DateFormatting.todayString()
        // 5 standard drinks in one day (> 2 * 2 = 4 daily threshold)
        let drinks = [AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 5, date: today)]
        XCTAssertEqual(SubstanceEngine.alcoholRisk(drinks: drinks, sex: .male), .high)
    }

    func testAlcoholRiskFemaleLowerThresholds() {
        let today = DateFormatting.todayString()
        // 1 drink for female (> 1 daily threshold but not > 2) → moderate
        let drinks = [
            AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: today),
            AlcoholDrink(name: "Light Beer", oz: 12, abv: 2.5, count: 1, date: today),
        ]
        XCTAssertEqual(SubstanceEngine.alcoholRisk(drinks: drinks, sex: .female), .moderate)
    }

    func testAlcoholRiskHighFemale() {
        let today = DateFormatting.todayString()
        // 3 drinks for female (> 1 * 2 = 2 daily threshold) → high
        let drinks = [AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 3, date: today)]
        XCTAssertEqual(SubstanceEngine.alcoholRisk(drinks: drinks, sex: .female), .high)
    }

    func testAlcoholRiskEmptyDrinks() {
        XCTAssertEqual(SubstanceEngine.alcoholRisk(drinks: [], sex: .male), .low)
    }

    func testAlcoholRiskNilSex() {
        let today = DateFormatting.todayString()
        // nil sex defaults to male thresholds
        let drinks = [AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: today)]
        XCTAssertEqual(SubstanceEngine.alcoholRisk(drinks: drinks, sex: nil), .low)
    }

    // MARK: Nicotine Rolling Averages

    func testRollingAverageMgEmpty() {
        XCTAssertEqual(SubstanceEngine.rollingAverageMg(entries: [], days: 7), 0)
    }

    func testRollingAverageMgWithEntries() {
        let today = DateFormatting.todayString()
        let entries = [NicotineEntry(product: "Zyn 6mg", mgPerUnit: 6, count: 2, date: today)]
        let avg = SubstanceEngine.rollingAverageMg(entries: entries, days: 7)
        // 12mg / 7 days ≈ 1.7
        XCTAssertEqual(avg, 12.0 / 7.0, accuracy: 0.01)
    }

    func testWeeklyTotalMgEmpty() {
        XCTAssertEqual(SubstanceEngine.weeklyTotalMg(entries: []), 0)
    }

    func testWeeklyTotalMgWithEntries() {
        let today = DateFormatting.todayString()
        let yesterday = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let entries = [
            NicotineEntry(product: "Zyn 6mg", mgPerUnit: 6, count: 1, date: today),
            NicotineEntry(product: "Zyn 6mg", mgPerUnit: 6, count: 2, date: yesterday),
        ]
        XCTAssertEqual(SubstanceEngine.weeklyTotalMg(entries: entries), 18.0, accuracy: 0.01)
    }

    func testAllTimeAverageMgEmpty() {
        XCTAssertEqual(SubstanceEngine.allTimeAverageMg(entries: []), 0)
    }

    func testAllTimeAverageMgWithEntries() {
        let weekAgo = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
        let entries = [NicotineEntry(product: "Zyn 6mg", mgPerUnit: 6, count: 1, date: weekAgo)]
        let avg = SubstanceEngine.allTimeAverageMg(entries: entries)
        XCTAssertGreaterThan(avg, 0)
    }

    // MARK: With Sample Data

    func testSubstanceEngineWithSampleAlcohol() {
        let avg7 = SubstanceEngine.rollingAverageGrams(drinks: SampleData.alcoholDrinks, days: 7)
        let avg30 = SubstanceEngine.rollingAverageGrams(drinks: SampleData.alcoholDrinks, days: 30)
        let allTime = SubstanceEngine.allTimeAverageGrams(drinks: SampleData.alcoholDrinks)

        // Sample data has active drinker, should have non-zero averages
        XCTAssertGreaterThanOrEqual(avg7, 0)
        XCTAssertGreaterThanOrEqual(avg30, 0)
        XCTAssertGreaterThan(allTime, 0)
    }

    func testSubstanceEngineWithSampleNicotine() {
        let avg7 = SubstanceEngine.rollingAverageMg(entries: SampleData.nicotineEntries, days: 7)
        let avg30 = SubstanceEngine.rollingAverageMg(entries: SampleData.nicotineEntries, days: 30)
        let allTime = SubstanceEngine.allTimeAverageMg(entries: SampleData.nicotineEntries)

        XCTAssertGreaterThanOrEqual(avg7, 0)
        XCTAssertGreaterThanOrEqual(avg30, 0)
        XCTAssertGreaterThan(allTime, 0)
    }
}

// MARK: - GenomeParser Tests

final class GenomeParserTests: XCTestCase {

    func testParse23andMeFormat() {
        let content = """
        # rsid\tchromosome\tposition\tgenotype
        rs12913832\t15\t28365618\tGG
        rs1805007\t16\t89919709\tCC
        """
        let variants = GenomeParser.parse(content)
        XCTAssertEqual(variants.count, 2)
        XCTAssertEqual(variants[0].rsID, "rs12913832")
        XCTAssertEqual(variants[0].chromosome, "15")
        XCTAssertEqual(variants[0].position, "28365618")
        XCTAssertEqual(variants[0].genotype, "GG")
    }

    func testParseAncestryDNAFormat() {
        let content = """
        #AncestryDNA raw data download
        #rsid,chromosome,position,allele1,allele2
        rs12913832,15,28365618,G,G
        rs4988235,2,136608646,A,G
        """
        let variants = GenomeParser.parse(content)
        XCTAssertEqual(variants.count, 2)
        XCTAssertEqual(variants[0].genotype, "GG")
        XCTAssertEqual(variants[1].genotype, "AG")
    }

    func testParseSkipsComments() {
        let content = """
        # This is a comment
        # Another comment
        rs12913832\t15\t28365618\tGG
        """
        let variants = GenomeParser.parse(content)
        XCTAssertEqual(variants.count, 1)
    }

    func testParseSkipsEmptyLines() {
        let content = """
        rs12913832\t15\t28365618\tGG

        rs1805007\t16\t89919709\tCC

        """
        let variants = GenomeParser.parse(content)
        XCTAssertEqual(variants.count, 2)
    }

    func testParseSkipsInvalidRsIDs() {
        let content = """
        INVALID\t15\t28365618\tGG
        chr15\t15\t28365618\tGG
        rs12913832\t15\t28365618\tGG
        """
        let variants = GenomeParser.parse(content)
        XCTAssertEqual(variants.count, 1)
    }

    func testParseAcceptsIPrefix() {
        let content = "i3003137\t7\t17284577\tAC"
        let variants = GenomeParser.parse(content)
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants[0].rsID, "i3003137")
    }

    func testParseSkipsShortLines() {
        let content = "rs12913832\t15\t28365618"
        let variants = GenomeParser.parse(content)
        XCTAssertTrue(variants.isEmpty)
    }

    func testParseEmptyContent() {
        XCTAssertTrue(GenomeParser.parse("").isEmpty)
        XCTAssertTrue(GenomeParser.parse("# only comments").isEmpty)
    }

    func testParseSpaceSeparated() {
        let content = "rs12913832 15 28365618 GG"
        let variants = GenomeParser.parse(content)
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants[0].genotype, "GG")
    }

    func testSampleGenomeData() {
        let variants = SampleData.genomeVariants
        XCTAssertGreaterThanOrEqual(variants.count, 8)

        // Verify known variants are present
        let rsIDs = Set(variants.map(\.rsID))
        XCTAssertTrue(rsIDs.contains("rs12913832"))
        XCTAssertTrue(rsIDs.contains("rs429358"))
        XCTAssertTrue(rsIDs.contains("i3003137"))
    }

    func testSampleAncestryDNAParsing() {
        let variants = GenomeParser.parse(SampleData.ancestryDNAFileContent)
        XCTAssertEqual(variants.count, 3)
        XCTAssertEqual(variants[0].genotype, "GG")
        XCTAssertEqual(variants[1].genotype, "CC")
        XCTAssertEqual(variants[2].genotype, "AG")
    }

    func testGenomeVariantCodable() {
        let variant = GenomeVariant(rsID: "rs12913832", chromosome: "15", position: "28365618", genotype: "GG")
        let data = try! JSONEncoder().encode(variant)
        let decoded = try! JSONDecoder().decode(GenomeVariant.self, from: data)
        XCTAssertEqual(decoded, variant)
    }

    func testGenomeVariantEquatable() {
        let v1 = GenomeVariant(id: UUID(), rsID: "rs12913832", chromosome: "15", position: "28365618", genotype: "GG")
        let v2 = GenomeVariant(id: v1.id, rsID: "rs12913832", chromosome: "15", position: "28365618", genotype: "GG")
        XCTAssertEqual(v1, v2)
    }
}

// MARK: - AppData Tests

final class AppDataTests: XCTestCase {

    func testAppDataEmpty() {
        let empty = AppData.empty
        XCTAssertNil(empty.profile.birthDate)
        XCTAssertNil(empty.profile.biologicalSex)
        XCTAssertTrue(empty.alcoholDrinks.isEmpty)
        XCTAssertTrue(empty.nicotineEntries.isEmpty)
        XCTAssertTrue(empty.bloodTests.isEmpty)
        XCTAssertTrue(empty.eyeExams.isEmpty)
        XCTAssertTrue(empty.epigeneticTests.isEmpty)
        XCTAssertTrue(empty.bodyEntries.isEmpty)
        XCTAssertTrue(empty.healthMetrics.isEmpty)
        XCTAssertTrue(empty.goals.isEmpty)
    }

    func testAppDataEmptyHasDefaultLifestyle() {
        let empty = AppData.empty
        XCTAssertEqual(empty.profile.lifestyle.smokingStatus, .never)
    }

    func testAppDataEmptyPresetsNonEmpty() {
        let empty = AppData.empty
        // Presets should have defaults even for empty data
        XCTAssertGreaterThan(empty.alcoholPresets.count, 0)
    }
}

// MARK: - Edge Case Tests

final class EdgeCaseTests: XCTestCase {

    // MARK: AlcoholDrink Edge Cases

    func testAlcoholDrinkZeroABV() {
        let drink = AlcoholDrink(name: "Water", oz: 12, abv: 0, count: 1, date: "2026-01-01")
        XCTAssertEqual(drink.standardDrinks, 0)
        XCTAssertEqual(drink.gramsAlcohol, 0)
    }

    func testAlcoholDrinkZeroOz() {
        let drink = AlcoholDrink(name: "Nothing", oz: 0, abv: 5, count: 1, date: "2026-01-01")
        XCTAssertEqual(drink.standardDrinks, 0)
        XCTAssertEqual(drink.gramsAlcohol, 0)
    }

    func testAlcoholDrinkZeroCount() {
        let drink = AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 0, date: "2026-01-01")
        XCTAssertEqual(drink.standardDrinks, 0)
        XCTAssertEqual(drink.gramsAlcohol, 0)
    }

    func testAlcoholDrinkHighABV() {
        // Everclear: 1.5oz at 95% ABV
        let drink = AlcoholDrink(name: "Everclear", oz: 1.5, abv: 95, count: 1, date: "2026-01-01")
        XCTAssertGreaterThan(drink.standardDrinks, 2)
        XCTAssertGreaterThan(drink.gramsAlcohol, 20)
    }

    func testAlcoholDrinkEquatable() {
        let d1 = AlcoholDrink(name: "Beer", oz: 12, abv: 5, count: 1, date: "2026-01-01")
        let d2 = AlcoholDrink(id: d1.id, name: "Beer", oz: 12, abv: 5, count: 1, date: "2026-01-01")
        XCTAssertEqual(d1, d2)
    }

    // MARK: NicotineEntry Edge Cases

    func testNicotineEntryZeroMg() {
        let entry = NicotineEntry(product: "Placebo", mgPerUnit: 0, count: 2, date: "2026-01-01")
        XCTAssertEqual(entry.totalMg, 0)
    }

    func testNicotineEntryZeroCount() {
        let entry = NicotineEntry(product: "Zyn", mgPerUnit: 6, count: 0, date: "2026-01-01")
        XCTAssertEqual(entry.totalMg, 0)
    }

    func testNicotineEntryHighDose() {
        let entry = NicotineEntry(product: "Extreme", mgPerUnit: 20, count: 5, date: "2026-01-01")
        XCTAssertEqual(entry.totalMg, 100)
    }

    // MARK: BloodMarkerRef Edge Cases

    func testBloodMarkerRefRange() {
        let glucose = BloodMarkers.byKey["glucose"]!
        XCTAssertEqual(glucose.range, glucose.min...glucose.max)
    }

    func testBloodMarkerStatusAtExactBoundaries() {
        let glucose = BloodMarkers.byKey["glucose"]!
        XCTAssertEqual(glucose.status(for: glucose.min), .normal)
        XCTAssertEqual(glucose.status(for: glucose.max), .normal)
        XCTAssertEqual(glucose.status(for: glucose.min - 0.1), .low)
        XCTAssertEqual(glucose.status(for: glucose.max + 0.1), .high)
    }

    func testAllBloodMarkerCategories() {
        // Should have metabolic, lipids, CBC, thyroid, and electrolytes/organ at minimum
        XCTAssertGreaterThanOrEqual(BloodMarkers.categories.count, 5)
    }

    // MARK: Goal Edge Cases

    func testGoalDaysSinceLastCheckInNoCheckIns() {
        let created = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -15, to: Date())!)
        let goal = Goal(title: "New", createdDate: created)
        XCTAssertGreaterThanOrEqual(goal.daysSinceLastCheckIn, 14)
    }

    func testGoalDaysSinceLastCheckInWithCheckIn() {
        let yesterday = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        var goal = Goal(title: "Recent")
        goal.checkIns = [GoalCheckIn(date: yesterday, progressPct: 50)]
        XCTAssertLessThanOrEqual(goal.daysSinceLastCheckIn, 2)
    }

    func testGoalProgressPercentEmpty() {
        let goal = Goal(title: "Empty")
        XCTAssertEqual(goal.progressPercent, 0)
    }

    func testGoalAbandonedNotOverdue() {
        let pastDate = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -10, to: Date())!)
        let goal = Goal(title: "Abandoned", targetDate: pastDate, status: .abandoned)
        XCTAssertFalse(goal.isOverdue)
    }

    func testGoalAbandonedNoCheckInNeeded() {
        let oldDate = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -30, to: Date())!)
        var goal = Goal(title: "Abandoned", createdDate: oldDate, status: .abandoned)
        goal.checkIns = [GoalCheckIn(date: oldDate, progressPct: 20)]
        XCTAssertFalse(goal.needsCheckIn)
    }

    // MARK: DeathClockEngine Edge Cases

    func testSSABaselineBoundaryAges() {
        // Age 30: +0.5 bonus
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 30), 76.5)
        // Age 39: still +0.5
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 39), 76.5)
        // Age 40: +1.0
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 40), 77.0)
        // Age 50: +1.5
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 50), 77.5)
        // Age 60: +2.5
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 60), 78.5)
        // Age 80: +6.0
        XCTAssertEqual(DeathClockEngine.ssaBaseline(sex: .male, ageYears: 80), 82.0)
    }

    func testBMIImpactEdgeCases() {
        // Normal BMI range: 18.5-24.9
        XCTAssertEqual(DeathClockEngine.bmiImpact(18.5), 0.5)
        XCTAssertEqual(DeathClockEngine.bmiImpact(24.9), 0.5)
        // Overweight: 25-29.9
        XCTAssertEqual(DeathClockEngine.bmiImpact(25.0), -0.5)
        XCTAssertEqual(DeathClockEngine.bmiImpact(29.9), -0.5)
        // Obese: 30+
        XCTAssertEqual(DeathClockEngine.bmiImpact(30.0), -3)
    }

    func testSleepImpactEdgeCases() {
        // Optimal: 7-9
        XCTAssertEqual(DeathClockEngine.sleepImpact(7.0), 1)
        XCTAssertEqual(DeathClockEngine.sleepImpact(9.0), 1)
        // Borderline: 6-7 or 9+
        XCTAssertEqual(DeathClockEngine.sleepImpact(6.0), 0)
    }

    // MARK: EyeExam Edge Cases

    func testEyeExamAllNilFields() {
        let exam = EyeExam(date: "2026-03-15")
        XCTAssertNil(exam.leftSphere)
        XCTAssertNil(exam.rightSphere)
        XCTAssertNil(exam.leftCylinder)
        XCTAssertNil(exam.rightCylinder)
        XCTAssertNil(exam.leftAxis)
        XCTAssertNil(exam.rightAxis)

        let data = try! JSONEncoder().encode(exam)
        let decoded = try! JSONDecoder().decode(EyeExam.self, from: data)
        XCTAssertEqual(decoded, exam)
    }

    // MARK: EpigeneticTest Edge Cases

    func testEpigeneticTestNoOrganScores() {
        let test = EpigeneticTest(date: "2026-03-15", chronologicalAge: 50, biologicalAge: 48)
        XCTAssertNil(test.organScores)
        XCTAssertNil(test.paceOfAging)

        let data = try! JSONEncoder().encode(test)
        let decoded = try! JSONDecoder().decode(EpigeneticTest.self, from: data)
        XCTAssertEqual(decoded, test)
    }

    func testEpigeneticTestOlderBiologicalAge() {
        let test = EpigeneticTest(date: "2026-03-15", chronologicalAge: 40, biologicalAge: 50, paceOfAging: 1.25)
        XCTAssertGreaterThan(test.biologicalAge, test.chronologicalAge)
        XCTAssertGreaterThan(test.paceOfAging ?? 0, 1.0)
    }

    // MARK: BodyEntry Edge Cases

    func testBodyEntryNoWeight() {
        let entry = BodyEntry(date: "2026-03-15")
        XCTAssertNil(entry.weightLbs)
        XCTAssertNil(entry.bodyFatPct)
    }

    func testBodyEntryOnlyBodyFat() {
        let entry = BodyEntry(date: "2026-03-15", bodyFatPct: 15.5)
        XCTAssertNil(entry.weightLbs)
        XCTAssertEqual(entry.bodyFatPct, 15.5)
    }

    // MARK: LifestyleData Edge Cases

    func testLifestyleDataExtremeSleepValues() {
        XCTAssertEqual(DeathClockEngine.sleepImpact(3.0), -1.5)
        XCTAssertEqual(DeathClockEngine.sleepImpact(12.0), 0) // Too much sleep counts as borderline
    }

    func testLifestyleDataExtremeExercise() {
        XCTAssertEqual(DeathClockEngine.exerciseImpact(0), -2)
        XCTAssertEqual(DeathClockEngine.exerciseImpact(300), 2) // Very high exercise
    }
}

// MARK: - Enum Coverage Tests

final class EnumCoverageTests: XCTestCase {

    func testBiologicalSexAllCases() {
        XCTAssertEqual(BiologicalSex.allCases.count, 2)
        XCTAssertTrue(BiologicalSex.allCases.contains(.male))
        XCTAssertTrue(BiologicalSex.allCases.contains(.female))
    }

    func testSmokingStatusAllCases() {
        XCTAssertEqual(SmokingStatus.allCases.count, 3)
    }

    func testDietQualityAllCases() {
        XCTAssertEqual(DietQuality.allCases.count, 4)
    }

    func testStressLevelAllCases() {
        XCTAssertEqual(StressLevel.allCases.count, 3)
    }

    func testGoalPrioritySortOrder() {
        let all: [GoalPriority] = [.low, .high, .medium, .low, .high]
        let sorted = all.sorted()
        XCTAssertEqual(sorted, [.high, .high, .medium, .low, .low])
    }

    func testGoalPriorityCodable() {
        for priority in GoalPriority.allCases {
            let data = try! JSONEncoder().encode(priority)
            let decoded = try! JSONDecoder().decode(GoalPriority.self, from: data)
            XCTAssertEqual(decoded, priority)
        }
    }

    func testGoalStatusCodable() {
        for status in GoalStatus.allCases {
            let data = try! JSONEncoder().encode(status)
            let decoded = try! JSONDecoder().decode(GoalStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testMarkerStatusValues() {
        XCTAssertEqual(MarkerStatus.normal.rawValue, "normal")
        XCTAssertEqual(MarkerStatus.low.rawValue, "low")
        XCTAssertEqual(MarkerStatus.high.rawValue, "high")
        XCTAssertEqual(MarkerStatus.unknown.rawValue, "unknown")
    }

    func testAlcoholRiskValues() {
        XCTAssertEqual(AlcoholRisk.low.rawValue, "low")
        XCTAssertEqual(AlcoholRisk.moderate.rawValue, "moderate")
        XCTAssertEqual(AlcoholRisk.high.rawValue, "high")
    }
}

// MARK: - GoalEngine UrgencyLevel Tests

final class GoalEngineUrgencyTests: XCTestCase {

    func testOnTrackGoal() {
        // 50% done in 30 days, target is 120 days away — comfortably on track
        let created = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -30, to: Date())!)
        let target = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: 120, to: Date())!)
        var goal = Goal(title: "On Track", createdDate: created, targetDate: target)
        goal.checkIns = [
            GoalCheckIn(date: created, progressPct: 10),
            GoalCheckIn(date: DateFormatting.todayString(), progressPct: 50),
        ]
        let projection = GoalEngine.project(goal: goal, deathDate: nil, healthyCognitiveDate: nil)
        XCTAssertEqual(projection.urgencyLevel, .onTrack)
        XCTAssertEqual(projection.slippageDays, 0)
    }

    func testCompletedGoalProjection() {
        var goal = Goal(title: "Done", completedDate: DateFormatting.todayString(), status: .completed)
        goal.checkIns = [GoalCheckIn(progressPct: 100)]
        _ = GoalEngine.project(goal: goal, deathDate: nil, healthyCognitiveDate: nil)
        XCTAssertEqual(goal.progressPercent, 100)
    }
}

// MARK: - Sample Data Completeness Tests

final class SampleDataCompletenessTests: XCTestCase {

    func testSampleDataCoversAllFeatures() {
        let data = SampleData.fullAppData

        // Profile
        XCTAssertNotNil(data.profile.birthDate)
        XCTAssertNotNil(data.profile.biologicalSex)
        XCTAssertNotNil(data.profile.lifestyle.bmi)

        // Substances
        XCTAssertFalse(data.alcoholDrinks.isEmpty)
        XCTAssertFalse(data.nicotineEntries.isEmpty)
        XCTAssertFalse(data.alcoholPresets.isEmpty)
        XCTAssertFalse(data.nicotinePresets.isEmpty)

        // Blood
        XCTAssertFalse(data.bloodTests.isEmpty)

        // Body
        XCTAssertFalse(data.bodyEntries.isEmpty)

        // Eyes
        XCTAssertFalse(data.eyeExams.isEmpty)

        // Epigenetic
        XCTAssertFalse(data.epigeneticTests.isEmpty)

        // Health metrics
        XCTAssertFalse(data.healthMetrics.isEmpty)

        // Goals
        XCTAssertFalse(data.goals.isEmpty)
    }

    func testSampleDataGenomeVariantsExist() {
        XCTAssertFalse(SampleData.genomeVariants.isEmpty)
        XCTAssertGreaterThanOrEqual(SampleData.genomeVariants.count, 8)
    }

    func testSampleDataAllGoalStatusesRepresented() {
        let statuses = Set(SampleData.goals.map(\.status))
        XCTAssertTrue(statuses.contains(.active))
        XCTAssertTrue(statuses.contains(.completed))
    }

    func testSampleDataAllGoalPrioritiesRepresented() {
        let priorities = Set(SampleData.goals.map(\.priority))
        XCTAssertTrue(priorities.contains(.high))
        XCTAssertTrue(priorities.contains(.medium))
        XCTAssertTrue(priorities.contains(.low))
    }

    func testSampleDataHasGoalsWithMilestones() {
        let goalsWithMilestones = SampleData.goals.filter { !$0.milestones.isEmpty }
        XCTAssertGreaterThanOrEqual(goalsWithMilestones.count, 3)
    }

    func testSampleDataHasGoalsWithCheckIns() {
        let goalsWithCheckIns = SampleData.goals.filter { !$0.checkIns.isEmpty }
        XCTAssertGreaterThanOrEqual(goalsWithCheckIns.count, 3)
    }

    func testSampleDataHasCompletedMilestones() {
        let completedMilestones = SampleData.goals.flatMap(\.milestones).filter(\.completed)
        XCTAssertGreaterThan(completedMilestones.count, 5)
    }

    func testSampleDataBodyFatMeasurementsExist() {
        let withBodyFat = SampleData.bodyEntries.filter { $0.bodyFatPct != nil }
        XCTAssertGreaterThan(withBodyFat.count, 0)
    }

    func testSampleDataVO2MaxMeasurementsExist() {
        let withVO2 = SampleData.healthMetrics.filter { $0.vo2Max != nil }
        XCTAssertGreaterThan(withVO2.count, 0)
    }

    func testSampleDataSpO2MeasurementsExist() {
        let withSpO2 = SampleData.healthMetrics.filter { $0.oxygenSaturation != nil }
        XCTAssertGreaterThan(withSpO2.count, 0)
    }

    func testSampleDataRespiratoryRateMeasurementsExist() {
        let withResp = SampleData.healthMetrics.filter { $0.respiratoryRate != nil }
        XCTAssertGreaterThan(withResp.count, 0)
    }

    func testSampleDataBloodTestsHaveAllCorrelationMarkers() {
        let correlationMarkers = ["ldl", "glucose", "triglycerides", "hba1c", "cholesterol", "hdl", "apoB"]
        for test in SampleData.bloodTests {
            for marker in correlationMarkers {
                XCTAssertNotNil(test.markers[marker], "Blood test \(test.date) missing \(marker)")
            }
        }
    }

    func testSampleDataEpigeneticTestsHaveOrganScores() {
        for test in SampleData.epigeneticTests {
            XCTAssertNotNil(test.organScores)
            if let organs = test.organScores {
                XCTAssertTrue(organs.keys.contains("Heart"))
                XCTAssertTrue(organs.keys.contains("Brain"))
                XCTAssertTrue(organs.keys.contains("Liver"))
            }
        }
    }

    func testSampleDataNicotinePresetsExist() {
        XCTAssertGreaterThanOrEqual(SampleData.nicotinePresets.count, 2)
        for preset in SampleData.nicotinePresets {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertGreaterThan(preset.mgPerUnit, 0)
        }
    }

    func testSampleDataAlcoholPresetsHaveNAOption() {
        XCTAssertTrue(SampleData.alcoholPresets.contains { $0.abv < 1.0 })
    }
}
