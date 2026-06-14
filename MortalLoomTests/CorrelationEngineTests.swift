import XCTest
@testable import MortalLoom

// MARK: - CorrelationEngine Tests
//
// Pure-function coverage for the next-day-pairing correlations
// (sauna → recovery, alcohol → sleep, alcohol → breathing) and the shared
// `sleepStagePercent` helper. These correlations pair a "cause" recorded on
// day N with a health metric recorded on day N+1, sum same-day causes, and
// seed zero-cause "contrast" days from relevant next-day metrics.

// Named for the next-day-pairing surface specifically; `CorrelationEngineTests`
// in MortalLoomTests.swift already covers the activity→blood `buildCorrelationData` path.
final class CorrelationEngineNextDayPairingTests: XCTestCase {

    // MARK: - Fixtures

    /// Anchor used to build deterministic "YYYY-MM-DD" strings. All test dates
    /// are expressed as offsets from this so the date arithmetic round-trips
    /// through the same `DateFormatting`/`Calendar.current` the engine uses.
    private let anchor = DateFormatting.dateFromString("2026-06-01")!

    /// The date string `offset` days after the anchor.
    private func day(_ offset: Int) -> String {
        DateFormatting.dateString(
            Calendar.current.date(byAdding: .day, value: offset, to: anchor)!
        )
    }

    private func sauna(_ date: String, minutes: Int) -> SaunaSession {
        SaunaSession(saunaType: .infrared, temperatureF: 140, durationMinutes: minutes, date: date)
    }

    /// Alcohol with a chosen `standardDrinks`. `standardDrinks` is
    /// `(oz * count * abv/100) / 0.6`, so `abv = 60, count = 1` makes
    /// `oz == standardDrinks`.
    private func drink(_ date: String, standardDrinks: Double) -> AlcoholDrink {
        AlcoholDrink(name: "test", oz: standardDrinks, abv: 60, count: 1, date: date)
    }

    private func metric(
        _ date: String,
        hrv: Double? = nil,
        cardioRecovery: Double? = nil,
        sleepHours: Double? = nil,
        sleepDeepHours: Double? = nil,
        sleepRemHours: Double? = nil,
        breathingDisturbances: Double? = nil
    ) -> HealthMetricEntry {
        HealthMetricEntry(
            date: date,
            hrv: hrv,
            sleepHours: sleepHours,
            sleepDeepHours: sleepDeepHours,
            sleepRemHours: sleepRemHours,
            cardioRecovery: cardioRecovery,
            breathingDisturbances: breathingDisturbances
        )
    }

    private func nicotine(_ date: String, mg: Double) -> NicotineEntry {
        NicotineEntry(product: "test", mgPerUnit: mg, count: 1, date: date)
    }

    // MARK: - sleepStagePercent

    func testSleepStagePercent_computesShareOfTotal() {
        XCTAssertEqual(CorrelationEngine.sleepStagePercent(2, of: 8) ?? .nan, 25, accuracy: 0.0001)
    }

    func testSleepStagePercent_nilWhenStageOrTotalMissingOrZero() {
        XCTAssertNil(CorrelationEngine.sleepStagePercent(nil, of: 8))
        XCTAssertNil(CorrelationEngine.sleepStagePercent(2, of: nil))
        XCTAssertNil(CorrelationEngine.sleepStagePercent(2, of: 0))
        XCTAssertNil(CorrelationEngine.sleepStagePercent(2, of: -1))
    }

    // MARK: - saunaRecoveryCorrelation

    func testSaunaRecovery_emptyInputsReturnEmpty() {
        XCTAssertTrue(
            CorrelationEngine.saunaRecoveryCorrelation(
                sessions: [], healthMetrics: [metric(day(1), hrv: 50)]
            ).isEmpty
        )
        XCTAssertTrue(
            CorrelationEngine.saunaRecoveryCorrelation(
                sessions: [sauna(day(0), minutes: 20)], healthMetrics: []
            ).isEmpty
        )
    }

    func testSaunaRecovery_pairsSaunaWithNextDayMetric() {
        let result = CorrelationEngine.saunaRecoveryCorrelation(
            sessions: [sauna(day(0), minutes: 20)],
            healthMetrics: [metric(day(1), hrv: 55, sleepHours: 8, sleepDeepHours: 2, sleepRemHours: 1.6)]
        )
        XCTAssertEqual(result.count, 1)
        let p = result[0]
        XCTAssertEqual(p.date, day(0))
        XCTAssertEqual(p.saunaMinutes, 20)
        XCTAssertEqual(p.nextDayHRV ?? .nan, 55, accuracy: 0.0001)
        XCTAssertEqual(p.nextNightTotalHours ?? .nan, 8, accuracy: 0.0001)
        XCTAssertEqual(p.nextNightDeepPct ?? .nan, 25, accuracy: 0.0001)   // 2 / 8 * 100
        XCTAssertEqual(p.nextNightRemPct ?? .nan, 20, accuracy: 0.0001)    // 1.6 / 8 * 100
    }

    func testSaunaRecovery_sumsMultipleSameDaySessions() {
        let result = CorrelationEngine.saunaRecoveryCorrelation(
            sessions: [sauna(day(0), minutes: 20), sauna(day(0), minutes: 15)],
            healthMetrics: [metric(day(1), hrv: 50)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].saunaMinutes, 35)
    }

    func testSaunaRecovery_skipsSaunaDayWithoutNextDayMetric() {
        // Sauna on day 0; the only metric is far away on day 5. Day 0's next day
        // (day 1) has no metric, so the sauna day produces no point.
        let result = CorrelationEngine.saunaRecoveryCorrelation(
            sessions: [sauna(day(0), minutes: 20)],
            healthMetrics: [metric(day(5), hrv: 48)]
        )
        XCTAssertFalse(result.contains { $0.date == day(0) })
    }

    func testSaunaRecovery_includesZeroActivityContrastDay() {
        // No sauna near day 3, but a relevant metric on day 3 seeds its prior
        // day (day 2) as a zero-sauna contrast point.
        let result = CorrelationEngine.saunaRecoveryCorrelation(
            sessions: [sauna(day(10), minutes: 30)],   // unrelated day, no next-day metric
            healthMetrics: [metric(day(3), hrv: 48, sleepHours: 7, sleepDeepHours: 1.4)]
        )
        let contrast = result.first { $0.date == day(2) }
        XCTAssertNotNil(contrast)
        XCTAssertEqual(contrast?.saunaMinutes, 0)
        XCTAssertEqual(contrast?.nextDayHRV ?? .nan, 48, accuracy: 0.0001)
    }

    func testSaunaRecovery_resultIsSortedByDate() {
        let result = CorrelationEngine.saunaRecoveryCorrelation(
            sessions: [sauna(day(4), minutes: 10), sauna(day(0), minutes: 10), sauna(day(2), minutes: 10)],
            healthMetrics: [metric(day(1), hrv: 50), metric(day(3), hrv: 51), metric(day(5), hrv: 52)]
        )
        XCTAssertEqual(result.map(\.date), [day(0), day(2), day(4)])
        XCTAssertEqual(result.map(\.saunaMinutes), [10, 10, 10])   // values survive the sort
    }

    // MARK: - alcoholSleepCorrelation

    func testAlcoholSleep_emptyInputsReturnEmpty() {
        XCTAssertTrue(
            CorrelationEngine.alcoholSleepCorrelation(
                drinks: [], healthMetrics: [metric(day(1), sleepDeepHours: 1)]
            ).isEmpty
        )
        XCTAssertTrue(
            CorrelationEngine.alcoholSleepCorrelation(
                drinks: [drink(day(0), standardDrinks: 2)], healthMetrics: []
            ).isEmpty
        )
    }

    func testAlcoholSleep_pairsDrinksWithNextNightSleep() {
        let result = CorrelationEngine.alcoholSleepCorrelation(
            drinks: [drink(day(0), standardDrinks: 3)],
            healthMetrics: [metric(day(1), sleepHours: 8, sleepDeepHours: 1.6, sleepRemHours: 2.0)]
        )
        XCTAssertEqual(result.count, 1)
        let p = result[0]
        XCTAssertEqual(p.date, day(0))
        XCTAssertEqual(p.standardDrinks, 3, accuracy: 0.0001)
        XCTAssertEqual(p.nextNightTotalHours ?? .nan, 8, accuracy: 0.0001)
        XCTAssertEqual(p.nextNightDeepPct ?? .nan, 20, accuracy: 0.0001)   // 1.6 / 8 * 100
        XCTAssertEqual(p.nextNightRemPct ?? .nan, 25, accuracy: 0.0001)    // 2.0 / 8 * 100
    }

    func testAlcoholSleep_sumsMultipleSameDayDrinks() {
        let result = CorrelationEngine.alcoholSleepCorrelation(
            drinks: [drink(day(0), standardDrinks: 1), drink(day(0), standardDrinks: 2)],
            healthMetrics: [metric(day(1), sleepHours: 7, sleepDeepHours: 1.4)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].standardDrinks, 3, accuracy: 0.0001)
    }

    func testAlcoholSleep_skipsDayWithoutNextNightSleep() {
        // Next-day metric carries only HRV, no sleep — not relevant, so the
        // drinking day yields no point and seeds no contrast.
        let result = CorrelationEngine.alcoholSleepCorrelation(
            drinks: [drink(day(0), standardDrinks: 2)],
            healthMetrics: [metric(day(1), hrv: 50)]
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - alcoholBreathingCorrelation

    func testAlcoholBreathing_emptyInputsReturnEmpty() {
        XCTAssertTrue(
            CorrelationEngine.alcoholBreathingCorrelation(
                drinks: [], healthMetrics: [metric(day(1), breathingDisturbances: 5)]
            ).isEmpty
        )
        XCTAssertTrue(
            CorrelationEngine.alcoholBreathingCorrelation(
                drinks: [drink(day(0), standardDrinks: 1)], healthMetrics: []
            ).isEmpty
        )
    }

    func testAlcoholBreathing_pairsDrinksWithNextNightDisturbances() {
        let result = CorrelationEngine.alcoholBreathingCorrelation(
            drinks: [drink(day(0), standardDrinks: 4)],
            healthMetrics: [metric(day(1), breathingDisturbances: 12.5)]
        )
        XCTAssertEqual(result.count, 1)
        let p = result[0]
        XCTAssertEqual(p.date, day(0))
        XCTAssertEqual(p.standardDrinks, 4, accuracy: 0.0001)
        XCTAssertEqual(p.nextNightDisturbances ?? .nan, 12.5, accuracy: 0.0001)
    }

    func testAlcoholBreathing_skipsWhenNoDisturbanceData() {
        // Next-day metric has no breathingDisturbances → not relevant, no point.
        let result = CorrelationEngine.alcoholBreathingCorrelation(
            drinks: [drink(day(0), standardDrinks: 2)],
            healthMetrics: [metric(day(1), sleepHours: 7)]
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - nicotineCardioRecoveryCorrelation

    func testNicotineCardioRecovery_emptyInputsReturnEmpty() {
        XCTAssertTrue(
            CorrelationEngine.nicotineCardioRecoveryCorrelation(
                entries: [], healthMetrics: [metric(day(1), cardioRecovery: 30)]
            ).isEmpty
        )
        XCTAssertTrue(
            CorrelationEngine.nicotineCardioRecoveryCorrelation(
                entries: [nicotine(day(0), mg: 6)], healthMetrics: []
            ).isEmpty
        )
    }

    func testNicotineCardioRecovery_pairsNicotineWithNextDayRecovery() {
        let result = CorrelationEngine.nicotineCardioRecoveryCorrelation(
            entries: [nicotine(day(0), mg: 6)],
            healthMetrics: [metric(day(1), cardioRecovery: 28)]
        )
        XCTAssertEqual(result.count, 1)
        let p = result[0]
        XCTAssertEqual(p.date, day(0))
        XCTAssertEqual(p.nicotineMg, 6, accuracy: 0.0001)
        XCTAssertEqual(p.nextDayCardioRecovery ?? .nan, 28, accuracy: 0.0001)
    }

    func testNicotineCardioRecovery_sumsMultipleSameDayEntries() {
        let result = CorrelationEngine.nicotineCardioRecoveryCorrelation(
            entries: [nicotine(day(0), mg: 6), nicotine(day(0), mg: 3)],
            healthMetrics: [metric(day(1), cardioRecovery: 25)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].nicotineMg, 9, accuracy: 0.0001)
    }

    func testNicotineCardioRecovery_includesZeroNicotineContrastDay() {
        // No nicotine near day 3, but a cardio-recovery metric on day 3 seeds its
        // prior day (day 2) as a zero-nicotine contrast point.
        let result = CorrelationEngine.nicotineCardioRecoveryCorrelation(
            entries: [nicotine(day(10), mg: 6)],   // unrelated day, no next-day metric
            healthMetrics: [metric(day(3), cardioRecovery: 32)]
        )
        let contrast = result.first { $0.date == day(2) }
        XCTAssertNotNil(contrast)
        XCTAssertEqual(contrast?.nicotineMg, 0)
        XCTAssertEqual(contrast?.nextDayCardioRecovery ?? .nan, 32, accuracy: 0.0001)
    }

    func testNicotineCardioRecovery_skipsWhenNoRecoveryData() {
        // Next-day metric carries only HRV, no cardioRecovery → not relevant.
        let result = CorrelationEngine.nicotineCardioRecoveryCorrelation(
            entries: [nicotine(day(0), mg: 6)],
            healthMetrics: [metric(day(1), hrv: 50)]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testNicotineCardioRecovery_resultIsSortedByDate() {
        let result = CorrelationEngine.nicotineCardioRecoveryCorrelation(
            entries: [nicotine(day(4), mg: 6), nicotine(day(0), mg: 3), nicotine(day(2), mg: 9)],
            healthMetrics: [metric(day(1), cardioRecovery: 30), metric(day(3), cardioRecovery: 31), metric(day(5), cardioRecovery: 29)]
        )
        XCTAssertEqual(result.map(\.date), [day(0), day(2), day(4)])
        XCTAssertEqual(result.map(\.nicotineMg), [3, 9, 6])   // values survive the sort
    }

    // MARK: - bmiBreathingCorrelation

    private func bodyEntry(_ date: String, weightLbs: Double) -> BodyEntry {
        BodyEntry(date: date, weightLbs: weightLbs)
    }

    func testBMIBreathing_emptyOrMissingReferenceReturnsEmpty() {
        // No body entries.
        XCTAssertTrue(
            CorrelationEngine.bmiBreathingCorrelation(
                bodyEntries: [], healthMetrics: [metric(day(0), breathingDisturbances: 10)],
                referenceBMI: 30, referenceWeightLbs: 200
            ).isEmpty
        )
        // No breathing-disturbance nights.
        XCTAssertTrue(
            CorrelationEngine.bmiBreathingCorrelation(
                bodyEntries: [bodyEntry(day(0), weightLbs: 200)], healthMetrics: [metric(day(0), sleepHours: 7)],
                referenceBMI: 30, referenceWeightLbs: 200
            ).isEmpty
        )
        // Missing reference BMI / weight (height can't be anchored).
        XCTAssertTrue(
            CorrelationEngine.bmiBreathingCorrelation(
                bodyEntries: [bodyEntry(day(0), weightLbs: 200)], healthMetrics: [metric(day(0), breathingDisturbances: 10)],
                referenceBMI: nil, referenceWeightLbs: 200
            ).isEmpty
        )
        XCTAssertTrue(
            CorrelationEngine.bmiBreathingCorrelation(
                bodyEntries: [bodyEntry(day(0), weightLbs: 200)], healthMetrics: [metric(day(0), breathingDisturbances: 10)],
                referenceBMI: 30, referenceWeightLbs: nil
            ).isEmpty
        )
    }

    func testBMIBreathing_referenceWeighInReproducesStoredBMI() {
        // A weigh-in equal to the reference weight reconstructs the stored BMI exactly.
        let result = CorrelationEngine.bmiBreathingCorrelation(
            bodyEntries: [bodyEntry(day(0), weightLbs: 200)],
            healthMetrics: [metric(day(0), breathingDisturbances: 14)],
            referenceBMI: 30, referenceWeightLbs: 200
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].date, day(0))
        XCTAssertEqual(result[0].bmi, 30, accuracy: 0.0001)
        XCTAssertEqual(result[0].breathingDisturbances, 14, accuracy: 0.0001)
    }

    func testBMIBreathing_scalesBMILinearlyWithWeight() {
        // Height is anchored on (200 lbs, BMI 30); a 180 lb weigh-in scales BMI
        // to 30 × 180/200 = 27.
        let result = CorrelationEngine.bmiBreathingCorrelation(
            bodyEntries: [bodyEntry(day(0), weightLbs: 180), bodyEntry(day(10), weightLbs: 200)],
            healthMetrics: [metric(day(0), breathingDisturbances: 8), metric(day(10), breathingDisturbances: 20)],
            referenceBMI: 30, referenceWeightLbs: 200
        )
        XCTAssertEqual(result.map(\.date), [day(0), day(10)])
        XCTAssertEqual(result[0].bmi, 27, accuracy: 0.0001)
        XCTAssertEqual(result[1].bmi, 30, accuracy: 0.0001)
    }

    func testBMIBreathing_carriesForwardMostRecentWeighIn() {
        // A night with no same-day weigh-in uses the latest weigh-in on or before
        // it: day(5) carries day(0)'s 180 lbs (BMI 27); day(15) carries day(10)'s
        // 200 lbs (BMI 30).
        let result = CorrelationEngine.bmiBreathingCorrelation(
            bodyEntries: [bodyEntry(day(0), weightLbs: 180), bodyEntry(day(10), weightLbs: 200)],
            healthMetrics: [metric(day(5), breathingDisturbances: 9), metric(day(15), breathingDisturbances: 19)],
            referenceBMI: 30, referenceWeightLbs: 200
        )
        XCTAssertEqual(result.map(\.date), [day(5), day(15)])
        XCTAssertEqual(result[0].bmi, 27, accuracy: 0.0001)
        XCTAssertEqual(result[1].bmi, 30, accuracy: 0.0001)
    }

    func testBMIBreathing_dropsNightsBeforeFirstWeighIn() {
        // day(0) precedes the only weigh-in (day(5)) so no weight is known yet.
        let result = CorrelationEngine.bmiBreathingCorrelation(
            bodyEntries: [bodyEntry(day(5), weightLbs: 200)],
            healthMetrics: [metric(day(0), breathingDisturbances: 10), metric(day(5), breathingDisturbances: 12)],
            referenceBMI: 30, referenceWeightLbs: 200
        )
        XCTAssertEqual(result.map(\.date), [day(5)])
        XCTAssertEqual(result[0].bmi, 30, accuracy: 0.0001)
    }

    func testBMIBreathing_resultIsSortedByDate() {
        let result = CorrelationEngine.bmiBreathingCorrelation(
            bodyEntries: [bodyEntry(day(0), weightLbs: 200)],
            healthMetrics: [
                metric(day(4), breathingDisturbances: 5),
                metric(day(1), breathingDisturbances: 6),
                metric(day(2), breathingDisturbances: 7),
            ],
            referenceBMI: 30, referenceWeightLbs: 200
        )
        XCTAssertEqual(result.map(\.date), [day(1), day(2), day(4)])
    }

    func testImpliedHeightInches_invertsBMIFormula() {
        // BMI = 703 × lbs / in², so height = sqrt(703 × lbs / BMI).
        let height = CorrelationEngine.impliedHeightInches(weightLbs: 200, bmi: 30)
        XCTAssertEqual(height ?? .nan, (703.0 * 200 / 30).squareRoot(), accuracy: 0.0001)
        XCTAssertNil(CorrelationEngine.impliedHeightInches(weightLbs: 0, bmi: 30))
        XCTAssertNil(CorrelationEngine.impliedHeightInches(weightLbs: 200, bmi: 0))
    }
}

// MARK: - Exercise → Cardio Recovery (weekly aggregation)
//
// Unlike the next-day-pairing surface above, this correlation buckets health
// metrics by ISO week (Monday-anchored, via `HabitEngine.startOfWeek`) and
// pairs each week's total exercise minutes with that week's average cardio
// recovery. Fixtures build dates relative to a known Monday so same-week vs
// different-week membership is explicit and calendar-independent.
final class CorrelationEngineExerciseCardioRecoveryTests: XCTestCase {

    /// Monday of the week containing a fixed anchor — the engine's own week
    /// bucketing key, so expected week-start strings round-trip through it.
    private let weekZeroMonday = HabitEngine.startOfWeek(DateFormatting.dateFromString("2026-06-01")!)

    /// "YYYY-MM-DD" for `day` (0 = Monday … 6 = Sunday) of week `week` relative
    /// to `weekZeroMonday`. Keeps test dates inside their intended ISO week.
    private func weekDay(week: Int, day: Int) -> String {
        DateFormatting.dateString(
            Calendar.current.date(byAdding: .day, value: week * 7 + day, to: weekZeroMonday)!
        )
    }

    /// Expected week-start string for relative week `week`.
    private func weekStart(_ week: Int) -> String {
        DateFormatting.dateString(
            Calendar.current.date(byAdding: .day, value: week * 7, to: weekZeroMonday)!
        )
    }

    private func metric(_ date: String, exercise: Double? = nil, recovery: Double? = nil) -> HealthMetricEntry {
        HealthMetricEntry(date: date, exerciseMinutes: exercise, cardioRecovery: recovery)
    }

    func testExerciseCardioRecovery_emptyInputReturnsEmpty() {
        XCTAssertTrue(CorrelationEngine.exerciseCardioRecoveryCorrelation(healthMetrics: []).isEmpty)
    }

    func testExerciseCardioRecovery_sumsExerciseAndAveragesRecoveryWithinWeek() {
        let result = CorrelationEngine.exerciseCardioRecoveryCorrelation(healthMetrics: [
            metric(weekDay(week: 0, day: 0), exercise: 30, recovery: 20),
            metric(weekDay(week: 0, day: 2), exercise: 20, recovery: 30),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].date, weekStart(0))
        XCTAssertEqual(result[0].weekExerciseMinutes, 50, accuracy: 0.0001)   // 30 + 20
        XCTAssertEqual(result[0].avgCardioRecovery, 25, accuracy: 0.0001)     // (20 + 30) / 2
    }

    func testExerciseCardioRecovery_excludesWeekWithoutRecoveryReading() {
        // Exercise logged but no cardio-recovery reading → the week has no
        // defined average, so it is dropped.
        let result = CorrelationEngine.exerciseCardioRecoveryCorrelation(healthMetrics: [
            metric(weekDay(week: 0, day: 0), exercise: 45),
        ])
        XCTAssertTrue(result.isEmpty)
    }

    func testExerciseCardioRecovery_includesZeroExerciseContrastWeek() {
        // A recovery reading with no exercise that week is a low-load contrast
        // point, not a dropped week: exercise minutes default to 0.
        let result = CorrelationEngine.exerciseCardioRecoveryCorrelation(healthMetrics: [
            metric(weekDay(week: 0, day: 3), recovery: 22),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].weekExerciseMinutes, 0, accuracy: 0.0001)
        XCTAssertEqual(result[0].avgCardioRecovery, 22, accuracy: 0.0001)
    }

    func testExerciseCardioRecovery_bucketsDistinctWeeksAndSortsByDate() {
        let result = CorrelationEngine.exerciseCardioRecoveryCorrelation(healthMetrics: [
            metric(weekDay(week: 2, day: 1), exercise: 60, recovery: 40),
            metric(weekDay(week: 0, day: 1), exercise: 30, recovery: 20),
            metric(weekDay(week: 1, day: 5), exercise: 90, recovery: 30),
        ])
        XCTAssertEqual(result.map(\.date), [weekStart(0), weekStart(1), weekStart(2)])
        XCTAssertEqual(result.map(\.weekExerciseMinutes), [30, 90, 60])
        XCTAssertEqual(result.map(\.avgCardioRecovery), [20, 30, 40])
    }
}
