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
}
