import XCTest
@testable import MortalLoom

// MARK: - SleepEngine Tests
//
// Pure-function unit tests for SleepEngine. Each test states a single
// observable behavior with concrete expected values; broken implementations
// should fail at least one test in this file.

final class SleepEngineTests: XCTestCase {

    // MARK: rateDuration

    func testRateDurationVeryShort() {
        XCTAssertEqual(SleepEngine.rateDuration(4.0, age: 40), .veryShort)
        XCTAssertEqual(SleepEngine.rateDuration(4.99, age: 40), .veryShort)
    }

    func testRateDurationShort() {
        XCTAssertEqual(SleepEngine.rateDuration(5.0, age: 40), .short)
        XCTAssertEqual(SleepEngine.rateDuration(5.5, age: 40), .short)
        XCTAssertEqual(SleepEngine.rateDuration(5.99, age: 40), .short)
    }

    func testRateDurationAdequate() {
        XCTAssertEqual(SleepEngine.rateDuration(6.0, age: 40), .adequate)
        XCTAssertEqual(SleepEngine.rateDuration(6.5, age: 40), .adequate)
        XCTAssertEqual(SleepEngine.rateDuration(6.99, age: 40), .adequate)
    }

    func testRateDurationOptimalAdult() {
        XCTAssertEqual(SleepEngine.rateDuration(7.0, age: 40), .optimal)
        XCTAssertEqual(SleepEngine.rateDuration(8.0, age: 40), .optimal)
        XCTAssertEqual(SleepEngine.rateDuration(9.0, age: 40), .optimal)
    }

    func testRateDurationOptimalOlderAdult() {
        // Older adults: optimal ceiling is 8h, not 9h
        XCTAssertEqual(SleepEngine.rateDuration(7.0, age: 70), .optimal)
        XCTAssertEqual(SleepEngine.rateDuration(8.0, age: 70), .optimal)
        // 8.5 for older adult is "good", not "optimal"
        XCTAssertEqual(SleepEngine.rateDuration(8.5, age: 70), .good)
    }

    func testRateDurationOlderAdultAgeBoundary() {
        // 65 is the older-adult threshold
        XCTAssertEqual(SleepEngine.rateDuration(8.5, age: 64), .optimal)
        XCTAssertEqual(SleepEngine.rateDuration(8.5, age: 65), .good)
    }

    func testRateDurationGood() {
        XCTAssertEqual(SleepEngine.rateDuration(9.5, age: 40), .good)
        XCTAssertEqual(SleepEngine.rateDuration(10.0, age: 40), .good)
    }

    func testRateDurationExcessive() {
        XCTAssertEqual(SleepEngine.rateDuration(10.5, age: 40), .excessive)
        XCTAssertEqual(SleepEngine.rateDuration(12.0, age: 40), .excessive)
    }

    // MARK: consistencyScore

    func testConsistencyScoreTooFewNights() {
        // < 3 nights → 0 (insufficient data)
        XCTAssertEqual(SleepEngine.consistencyScore([]), 0)
        XCTAssertEqual(SleepEngine.consistencyScore([7.5]), 0)
        XCTAssertEqual(SleepEngine.consistencyScore([7.5, 8.0]), 0)
    }

    func testConsistencyScorePerfect() {
        // All identical values → CV = 0 → score 100
        XCTAssertEqual(SleepEngine.consistencyScore([8.0, 8.0, 8.0, 8.0, 8.0]), 100, accuracy: 0.001)
    }

    func testConsistencyScoreHighVariation() {
        // Wildly inconsistent → low score
        let score = SleepEngine.consistencyScore([4.0, 9.0, 5.0, 10.0, 4.0])
        XCTAssertLessThan(score, 50)
    }

    func testConsistencyScoreModerateVariation() {
        // Small variation → high but not perfect score
        let score = SleepEngine.consistencyScore([7.5, 8.0, 7.5, 8.0, 7.5])
        XCTAssertGreaterThan(score, 80)
        XCTAssertLessThan(score, 100)
    }

    func testConsistencyScoreZeroMeanGuard() {
        // mean == 0 → 0 (avoids divide-by-zero)
        XCTAssertEqual(SleepEngine.consistencyScore([0, 0, 0, 0]), 0)
    }

    // MARK: daylightConsistencyCorrelation

    /// Build N consecutive HealthMetricEntry days starting from `startDate`,
    /// each with the supplied daylight and sleep values (same length expected).
    private func makeMetrics(startDate: Date, daylight: [Double], sleep: [Double]) -> [HealthMetricEntry] {
        precondition(daylight.count == sleep.count)
        let cal = Calendar.current
        return (0..<daylight.count).map { i in
            let date = cal.date(byAdding: .day, value: i, to: startDate)!
            return HealthMetricEntry(
                date: DateFormatting.dateString(date),
                sleepHours: sleep[i],
                daylightMinutes: daylight[i]
            )
        }
    }

    func testDaylightConsistencyTooFewNightsReturnsEmpty() {
        // 5 valid nights but windowNights=7 → no full window
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let metrics = makeMetrics(
            startDate: start,
            daylight: [60, 60, 60, 60, 60],
            sleep: [8, 8, 8, 8, 8]
        )
        XCTAssertTrue(SleepEngine.daylightConsistencyCorrelation(metrics: metrics).isEmpty)
    }

    func testDaylightConsistencyDropsNightsMissingEitherSignal() {
        // 10 calendar days total but only 6 have BOTH daylight and sleep → no full 7-night window
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let metrics: [HealthMetricEntry] = (0..<10).map { i in
            let dateStr = DateFormatting.dateString(cal.date(byAdding: .day, value: i, to: start)!)
            // Days 0–5 have both; days 6–9 are missing daylight
            if i < 6 {
                return HealthMetricEntry(date: dateStr, sleepHours: 8, daylightMinutes: 60)
            } else {
                return HealthMetricEntry(date: dateStr, sleepHours: 8, daylightMinutes: nil)
            }
        }
        XCTAssertTrue(SleepEngine.daylightConsistencyCorrelation(metrics: metrics).isEmpty)
    }

    func testDaylightConsistencyProducesOneWindowPerEndNight() {
        // 10 valid nights, windowNights=7 → 4 sliding windows (ending at indices 6, 7, 8, 9)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let metrics = makeMetrics(
            startDate: start,
            daylight: Array(repeating: 60.0, count: 10),
            sleep: Array(repeating: 8.0, count: 10)
        )
        let points = SleepEngine.daylightConsistencyCorrelation(metrics: metrics, windowNights: 7)
        XCTAssertEqual(points.count, 4)
        // Every window has identical 8h sleep → perfect consistency (100)
        for p in points {
            XCTAssertEqual(p.consistency, 100, accuracy: 0.001)
            XCTAssertEqual(p.avgDaylightMinutes, 60, accuracy: 0.001)
            XCTAssertEqual(p.nightsInWindow, 7)
        }
    }

    func testDaylightConsistencyWindowNightsGuardRejectsTooSmall() {
        // windowNights < 3 returns empty (consistencyScore needs ≥3 nights)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let metrics = makeMetrics(
            startDate: start,
            daylight: Array(repeating: 60.0, count: 10),
            sleep: Array(repeating: 8.0, count: 10)
        )
        XCTAssertTrue(SleepEngine.daylightConsistencyCorrelation(metrics: metrics, windowNights: 2).isEmpty)
    }

    func testDaylightConsistencyWindowSpansMoreThanWindowNightsCalendarDays() {
        // 8 calendar days: nights 0,1,2 then a 4-day gap then nights 7,8,9,10,11
        // = 8 valid nights total; one 7-night window spanning 11 calendar days.
        // Documents the "by count of qualifying nights, not calendar span" semantics.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let metrics: [HealthMetricEntry] = (0..<12).map { i in
            let dateStr = DateFormatting.dateString(cal.date(byAdding: .day, value: i, to: start)!)
            let hasData = i < 3 || i >= 7
            return HealthMetricEntry(
                date: dateStr,
                sleepHours: hasData ? 8 : nil,
                daylightMinutes: hasData ? 60 : nil
            )
        }
        let points = SleepEngine.daylightConsistencyCorrelation(metrics: metrics, windowNights: 7)
        // 8 qualifying nights → 8 - 7 + 1 = 2 windows
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first?.nightsInWindow, 7)
    }

    func testDaylightConsistencyCoefficientRequiresThreePoints() {
        // <3 points → nil
        let p1 = SleepEngine.DaylightConsistencyPoint(endDate: Date(), avgDaylightMinutes: 30, consistency: 80, nightsInWindow: 7)
        let p2 = SleepEngine.DaylightConsistencyPoint(endDate: Date(), avgDaylightMinutes: 60, consistency: 90, nightsInWindow: 7)
        XCTAssertNil(SleepEngine.daylightConsistencyCorrelationCoefficient([p1, p2]))
    }

    func testDaylightConsistencyCoefficientZeroVarianceReturnsNil() {
        // All-identical daylight → x-variance is 0 → nil (no correlation defined)
        let pts = (0..<5).map { i in
            SleepEngine.DaylightConsistencyPoint(
                endDate: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i * 86_400)),
                avgDaylightMinutes: 60,
                consistency: Double(50 + i * 10),
                nightsInWindow: 7
            )
        }
        XCTAssertNil(SleepEngine.daylightConsistencyCorrelationCoefficient(pts))
    }

    func testDaylightConsistencyCoefficientPerfectPositive() {
        // Linear daylight & consistency → r = +1.0
        let pts = (0..<5).map { i in
            SleepEngine.DaylightConsistencyPoint(
                endDate: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i * 86_400)),
                avgDaylightMinutes: Double(30 + i * 10),
                consistency: Double(40 + i * 10),
                nightsInWindow: 7
            )
        }
        let r = SleepEngine.daylightConsistencyCorrelationCoefficient(pts)
        XCTAssertEqual(r ?? 0, 1.0, accuracy: 0.001)
    }

    func testDaylightConsistencyCoefficientPerfectNegative() {
        // Daylight ↑, consistency ↓ → r = -1.0
        let pts = (0..<5).map { i in
            SleepEngine.DaylightConsistencyPoint(
                endDate: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i * 86_400)),
                avgDaylightMinutes: Double(30 + i * 10),
                consistency: Double(90 - i * 10),
                nightsInWindow: 7
            )
        }
        let r = SleepEngine.daylightConsistencyCorrelationCoefficient(pts)
        XCTAssertEqual(r ?? 0, -1.0, accuracy: 0.001)
    }

    // MARK: rollingAverage

    func testRollingAverageEmpty() {
        XCTAssertNil(SleepEngine.rollingAverage([], days: 7))
    }

    func testRollingAverage7Days() {
        // 10 nights, take last 7
        let nights: [Double] = [6, 6, 6, 7, 7, 7, 8, 8, 8, 8]
        let avg = SleepEngine.rollingAverage(nights, days: 7)
        // Last 7 values are [7, 7, 7, 8, 8, 8, 8], which sum to 53.
        XCTAssertEqual(avg ?? 0, 53.0 / 7.0, accuracy: 0.001)
    }

    func testRollingAverageFewerNightsThanDays() {
        let nights = [7.5, 8.0, 7.5]
        let avg = SleepEngine.rollingAverage(nights, days: 30)
        // suffix(30) on a 3-element array returns all 3
        XCTAssertEqual(avg ?? 0, (7.5 + 8.0 + 7.5) / 3.0, accuracy: 0.001)
    }

    // MARK: sleepDebt

    func testSleepDebtSurplus() {
        XCTAssertEqual(SleepEngine.sleepDebt([9, 9, 9]), 3.0)
    }

    func testSleepDebtDeficit() {
        XCTAssertEqual(SleepEngine.sleepDebt([6, 6, 6]), -6.0)
    }

    func testSleepDebtAtTarget() {
        XCTAssertEqual(SleepEngine.sleepDebt([8, 8, 8]), 0.0)
    }

    func testSleepDebtCustomTarget() {
        // 7h target, three 9h nights = +6h
        XCTAssertEqual(SleepEngine.sleepDebt([9, 9, 9], targetHours: 7), 6.0)
    }

    func testSleepDebtEmpty() {
        XCTAssertEqual(SleepEngine.sleepDebt([]), 0)
    }

    // MARK: longevityImpact

    func testLongevityImpactVeryShort() {
        XCTAssertEqual(SleepEngine.longevityImpact(averageHours: 4.5), -3.0)
    }

    func testLongevityImpactShort() {
        XCTAssertEqual(SleepEngine.longevityImpact(averageHours: 5.5), -1.5)
    }

    func testLongevityImpactBelowOptimal() {
        XCTAssertEqual(SleepEngine.longevityImpact(averageHours: 6.5), -0.5)
    }

    func testLongevityImpactOptimal() {
        XCTAssertEqual(SleepEngine.longevityImpact(averageHours: 7.5), 1.0)
        XCTAssertEqual(SleepEngine.longevityImpact(averageHours: 7.0), 1.0)
        XCTAssertEqual(SleepEngine.longevityImpact(averageHours: 8.0), 1.0)
    }

    func testLongevityImpactSlightlyExcessive() {
        // 8..<9 → 0.5
        XCTAssertEqual(SleepEngine.longevityImpact(averageHours: 8.5), 0.5)
    }

    func testLongevityImpactExcessive() {
        // 9..<10 → -1.0
        XCTAssertEqual(SleepEngine.longevityImpact(averageHours: 9.5), -1.0)
    }

    func testLongevityImpactVeryExcessive() {
        // 10+ → -2.0
        XCTAssertEqual(SleepEngine.longevityImpact(averageHours: 11.0), -2.0)
    }

    // MARK: rateDeepSleep / rateRemSleep

    func testRateDeepSleepExcellent() {
        XCTAssertEqual(SleepEngine.rateDeepSleep(deepPct: 22), .excellent)
        XCTAssertEqual(SleepEngine.rateDeepSleep(deepPct: 20), .excellent)
    }

    func testRateDeepSleepGood() {
        XCTAssertEqual(SleepEngine.rateDeepSleep(deepPct: 15), .good)
        XCTAssertEqual(SleepEngine.rateDeepSleep(deepPct: 19.99), .good)
    }

    func testRateDeepSleepFair() {
        XCTAssertEqual(SleepEngine.rateDeepSleep(deepPct: 10), .fair)
        XCTAssertEqual(SleepEngine.rateDeepSleep(deepPct: 14.99), .fair)
    }

    func testRateDeepSleepPoor() {
        XCTAssertEqual(SleepEngine.rateDeepSleep(deepPct: 9), .poor)
        XCTAssertEqual(SleepEngine.rateDeepSleep(deepPct: 0), .poor)
    }

    func testRateRemSleepExcellent() {
        XCTAssertEqual(SleepEngine.rateRemSleep(remPct: 22), .excellent)
        XCTAssertEqual(SleepEngine.rateRemSleep(remPct: 30), .excellent)
    }

    func testRateRemSleepGood() {
        XCTAssertEqual(SleepEngine.rateRemSleep(remPct: 18), .good)
        XCTAssertEqual(SleepEngine.rateRemSleep(remPct: 21.99), .good)
    }

    func testRateRemSleepFair() {
        XCTAssertEqual(SleepEngine.rateRemSleep(remPct: 13), .fair)
        XCTAssertEqual(SleepEngine.rateRemSleep(remPct: 17.99), .fair)
    }

    func testRateRemSleepPoor() {
        XCTAssertEqual(SleepEngine.rateRemSleep(remPct: 12), .poor)
        XCTAssertEqual(SleepEngine.rateRemSleep(remPct: 0), .poor)
    }

    // MARK: classifyApneaRisk

    func testClassifyApneaRiskNormal() {
        XCTAssertEqual(SleepEngine.classifyApneaRisk(0), .normal)
        XCTAssertEqual(SleepEngine.classifyApneaRisk(4.99), .normal)
    }

    func testClassifyApneaRiskMild() {
        XCTAssertEqual(SleepEngine.classifyApneaRisk(5.0), .mild)
        XCTAssertEqual(SleepEngine.classifyApneaRisk(14.99), .mild)
    }

    func testClassifyApneaRiskModerate() {
        XCTAssertEqual(SleepEngine.classifyApneaRisk(15.0), .moderate)
        XCTAssertEqual(SleepEngine.classifyApneaRisk(29.99), .moderate)
    }

    func testClassifyApneaRiskSevere() {
        XCTAssertEqual(SleepEngine.classifyApneaRisk(30.0), .severe)
        XCTAssertEqual(SleepEngine.classifyApneaRisk(60.0), .severe)
    }

    // MARK: apneaLongevityImpact

    func testApneaLongevityImpactNormal() {
        XCTAssertEqual(SleepEngine.apneaLongevityImpact(2), 0)
    }

    func testApneaLongevityImpactMild() {
        XCTAssertEqual(SleepEngine.apneaLongevityImpact(10), -0.5)
    }

    func testApneaLongevityImpactModerate() {
        XCTAssertEqual(SleepEngine.apneaLongevityImpact(20), -1.5)
    }

    func testApneaLongevityImpactSevere() {
        XCTAssertEqual(SleepEngine.apneaLongevityImpact(40), -3.0)
    }

    // MARK: enhancedLongevityImpact

    func testEnhancedLongevityImpactWithoutStages() {
        // No stage data — falls back to base longevity impact
        XCTAssertEqual(SleepEngine.enhancedLongevityImpact(averageHours: 7.5, stageBreakdown: nil), 1.0)
    }

    func testEnhancedLongevityImpactExcellentStages() {
        let stages = SleepEngine.SleepStageBreakdown(
            avgDeepHours: 1.6, avgRemHours: 1.8, avgCoreHours: 4.0,
            deepPct: 22, remPct: 24, corePct: 54,
            deepQuality: .excellent, remQuality: .excellent,
            totalNights: 7
        )
        // Optimal hours (7.5 → +1.0) + excellent deep (+0.3) + excellent rem (+0.2) = 1.5
        XCTAssertEqual(SleepEngine.enhancedLongevityImpact(averageHours: 7.5, stageBreakdown: stages), 1.5, accuracy: 0.001)
    }

    func testEnhancedLongevityImpactPoorStages() {
        let stages = SleepEngine.SleepStageBreakdown(
            avgDeepHours: 0.5, avgRemHours: 0.5, avgCoreHours: 6.5,
            deepPct: 6, remPct: 6, corePct: 88,
            deepQuality: .poor, remQuality: .poor,
            totalNights: 7
        )
        // Optimal hours (7.5 → +1.0) - poor deep (-0.7) - poor rem (-0.5) = -0.2
        XCTAssertEqual(SleepEngine.enhancedLongevityImpact(averageHours: 7.5, stageBreakdown: stages), -0.2, accuracy: 0.001)
    }

    func testEnhancedLongevityImpactMaximumReachableValue() {
        let stages = SleepEngine.SleepStageBreakdown(
            avgDeepHours: 1.6, avgRemHours: 1.8, avgCoreHours: 4.0,
            deepPct: 22, remPct: 24, corePct: 54,
            deepQuality: .excellent, remQuality: .excellent,
            totalNights: 7
        )
        // Current best-case inputs: optimal hours (7.5 → +1.0)
        // plus excellent deep (+0.3) and excellent rem (+0.2) = 1.5.
        // Documents the maximum reachable value with current scoring weights.
        let result = SleepEngine.enhancedLongevityImpact(averageHours: 7.5, stageBreakdown: stages)
        XCTAssertEqual(result, 1.5, accuracy: 0.001)
    }

    func testEnhancedLongevityImpactClampedLow() {
        let stages = SleepEngine.SleepStageBreakdown(
            avgDeepHours: 0.2, avgRemHours: 0.2, avgCoreHours: 3.6,
            deepPct: 5, remPct: 5, corePct: 90,
            deepQuality: .poor, remQuality: .poor,
            totalNights: 7
        )
        // Very short hours (-3.0) + poor deep (-0.7) + poor rem (-0.5) = -4.2 → clamped to -4.0
        let result = SleepEngine.enhancedLongevityImpact(averageHours: 4.0, stageBreakdown: stages)
        XCTAssertEqual(result, -4.0, accuracy: 0.001)
    }

    // MARK: stageBreakdown

    func testStageBreakdownNoStages() {
        // Metrics without sleep stage data → nil
        let metrics = [
            HealthMetricEntry(date: "2026-04-01", sleepHours: 7.5),
            HealthMetricEntry(date: "2026-04-02", sleepHours: 8.0)
        ]
        XCTAssertNil(SleepEngine.stageBreakdown(metrics: metrics))
    }

    func testStageBreakdownWithStages() {
        let metrics = [
            HealthMetricEntry(
                date: "2026-04-01", sleepHours: 8.0,
                sleepDeepHours: 1.6, sleepRemHours: 1.6, sleepCoreHours: 4.8
            ),
            HealthMetricEntry(
                date: "2026-04-02", sleepHours: 8.0,
                sleepDeepHours: 1.6, sleepRemHours: 1.6, sleepCoreHours: 4.8
            )
        ]
        let summary = SleepEngine.stageBreakdown(metrics: metrics)
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.avgDeepHours ?? 0, 1.6, accuracy: 0.001)
        XCTAssertEqual(summary?.avgRemHours ?? 0, 1.6, accuracy: 0.001)
        XCTAssertEqual(summary?.deepPct ?? 0, 20.0, accuracy: 0.1)
        XCTAssertEqual(summary?.remPct ?? 0, 20.0, accuracy: 0.1)
        XCTAssertEqual(summary?.totalNights, 2)
        XCTAssertEqual(summary?.deepQuality, .excellent)
        XCTAssertEqual(summary?.remQuality, .good)
    }

    // MARK: summarize

    func testSummarizeEmptyInput() {
        let summary = SleepEngine.summarize(sleepHours: [], age: 40)
        XCTAssertEqual(summary.averageDuration, 0)
        XCTAssertEqual(summary.totalNights, 0)
        XCTAssertNil(summary.avg7Day)
        XCTAssertNil(summary.avg30Day)
        XCTAssertNil(summary.apneaRisk)
    }

    func testSummarizeOptimalSleep() {
        let nights: [Double] = Array(repeating: 8.0, count: 14)
        let summary = SleepEngine.summarize(sleepHours: nights, age: 40)
        XCTAssertEqual(summary.averageDuration, 8.0)
        XCTAssertEqual(summary.rating, .optimal)
        XCTAssertEqual(summary.totalNights, 14)
        XCTAssertEqual(summary.longevityYears, 1.0)
        XCTAssertEqual(summary.consistency, 100, accuracy: 0.001)
        XCTAssertEqual(summary.debt, 0)
    }

    func testSummarizeWithBreathingDisturbances() {
        let metrics = [
            HealthMetricEntry(date: "2026-04-01", breathingDisturbances: 20),
            HealthMetricEntry(date: "2026-04-02", breathingDisturbances: 22),
            HealthMetricEntry(date: "2026-04-03", breathingDisturbances: 18)
        ]
        let summary = SleepEngine.summarize(sleepHours: [7.5, 7.5, 7.5], age: 40, metrics: metrics)
        XCTAssertEqual(summary.apneaRisk, .moderate) // avg 20 events/h
        XCTAssertEqual(summary.avgBreathingDisturbances ?? 0, 20.0, accuracy: 0.001)
    }
}
