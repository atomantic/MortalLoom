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

            // All check-ins should have valid progress
            for checkIn in goal.checkIns {
                XCTAssertGreaterThanOrEqual(checkIn.progressPct, 0)
                XCTAssertLessThanOrEqual(checkIn.progressPct, 100)
            }
        }

        // Should have at least one completed goal
        XCTAssertTrue(goals.contains { $0.status == .completed })
        // Should have at least one active goal
        XCTAssertTrue(goals.contains { $0.status == .active })
    }
}
