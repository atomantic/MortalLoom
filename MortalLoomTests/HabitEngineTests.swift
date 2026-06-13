import XCTest
@testable import MortalLoom

// MARK: - HabitEngine Tests
//
// Pure-function coverage for the streak/target-hit/stagnation math over a
// habit's `completions`. Daily cadence buckets by calendar day; weekly cadence
// buckets by ISO week (Monday-anchored). All tests pin `now` to a fixed anchor
// so period bucketing is deterministic regardless of when the suite runs.

final class HabitEngineTests: XCTestCase {

    // MARK: - Fixtures

    /// Fixed "now" so day/week bucketing is stable across runs and timezones.
    private let now = DateFormatting.dateFromString("2026-06-10")!
    private let cal = Calendar.current

    private func habit(
        period: HabitCadencePeriod = .daily,
        target: Int = 1,
        completions: [HabitCompletion] = [],
        archived: Bool = false
    ) -> Habit {
        Habit(
            name: "test",
            cadence: HabitCadence(period: period, target: target),
            archivedDate: archived ? "2026-01-01" : nil,
            completions: completions
        )
    }

    private func completion(_ date: String, count: Int = 1) -> HabitCompletion {
        HabitCompletion(date: date, count: count)
    }

    /// "YYYY-MM-DD" string for `n` days before `now`.
    private func daysAgo(_ n: Int) -> String {
        DateFormatting.dateString(daysAgo: n, from: now)
    }

    /// "YYYY-MM-DD" string `offset` days after `from`.
    private func dateString(_ from: Date, plus offset: Int) -> String {
        DateFormatting.dateString(cal.date(byAdding: .day, value: offset, to: from)!)
    }

    // MARK: - completionsInPeriod

    func testCompletionsInPeriod_dailySumsSameDayCounts() {
        let h = habit(completions: [
            completion(daysAgo(0), count: 1),
            completion(daysAgo(0), count: 2),
            completion(daysAgo(1)),               // different day — excluded
        ])
        XCTAssertEqual(HabitEngine.completionsInPeriod(h, containing: now), 3)
    }

    func testCompletionsInPeriod_weeklyRespectsMondayBoundary() {
        let weekStart = HabitEngine.startOfWeek(now)   // Monday of `now`'s ISO week
        let h = habit(period: .weekly, target: 1, completions: [
            completion(dateString(weekStart, plus: 0)),   // Monday — in week
            completion(dateString(weekStart, plus: 6)),   // Sunday — in week
            completion(dateString(weekStart, plus: -1)),  // previous Sunday — prior week
        ])
        XCTAssertEqual(HabitEngine.completionsInPeriod(h, containing: now), 2)
    }

    // MARK: - currentStreak (daily)

    func testCurrentStreak_dailyConsecutivePeriods() {
        let h = habit(completions: (0..<3).map { completion(daysAgo($0)) })
        XCTAssertEqual(HabitEngine.currentStreak(h, now: now), 3)
    }

    func testCurrentStreak_dailyBreaksOnGap() {
        // Hit today and two days ago, but missed yesterday → streak is just today.
        let h = habit(completions: [completion(daysAgo(0)), completion(daysAgo(2))])
        XCTAssertEqual(HabitEngine.currentStreak(h, now: now), 1)
    }

    func testCurrentStreak_zeroWhenCurrentPeriodMissed() {
        // Yesterday and the day before were hit, but today is not → committed
        // progress is 0 (the streak reflects what's banked, not hope).
        let h = habit(completions: [completion(daysAgo(1)), completion(daysAgo(2))])
        XCTAssertEqual(HabitEngine.currentStreak(h, now: now), 0)
    }

    // MARK: - currentStreak (weekly ISO-Monday)

    func testCurrentStreak_weeklyCadence() {
        let thisWeek = HabitEngine.startOfWeek(now)
        let lastWeek = cal.date(byAdding: .day, value: -7, to: thisWeek)!
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: thisWeek)!

        // 3×/week target: hit this week and last week, miss two weeks ago.
        func threeIn(_ weekStart: Date) -> [HabitCompletion] {
            (0..<3).map { completion(dateString(weekStart, plus: $0)) }
        }
        let comps = threeIn(thisWeek) + threeIn(lastWeek) + [completion(dateString(twoWeeksAgo, plus: 0))]
        let h = habit(period: .weekly, target: 3, completions: comps)
        XCTAssertEqual(HabitEngine.currentStreak(h, now: now), 2)
    }

    // MARK: - targetHitRate

    func testTargetHitRate_dailyWindow() {
        // 7 hits over a 10-day window → 70%.
        let h = habit(completions: (0..<7).map { completion(daysAgo($0)) })
        XCTAssertEqual(HabitEngine.targetHitRate(h, windowDays: 10, now: now), 70, accuracy: 0.0001)
    }

    func testTargetHitRate_zeroWindowReturnsZero() {
        XCTAssertEqual(HabitEngine.targetHitRate(habit(), windowDays: 0, now: now), 0, accuracy: 0.0001)
    }

    func testTargetHitRate_weeklyAllPeriodsHit() {
        let thisWeek = HabitEngine.startOfWeek(now)
        var comps: [HabitCompletion] = []
        for weeksBack in 0...6 {   // cover more than the 28-day window needs
            let ws = cal.date(byAdding: .day, value: -7 * weeksBack, to: thisWeek)!
            comps += (0..<2).map { completion(dateString(ws, plus: $0)) }
        }
        let h = habit(period: .weekly, target: 2, completions: comps)
        XCTAssertEqual(HabitEngine.targetHitRate(h, windowDays: 28, now: now), 100, accuracy: 0.0001)
    }

    func testTargetHitRate_weeklyNoPeriodsHit() {
        let h = habit(period: .weekly, target: 2, completions: [])
        XCTAssertEqual(HabitEngine.targetHitRate(h, windowDays: 28, now: now), 0, accuracy: 0.0001)
    }

    // MARK: - isStagnant

    func testIsStagnant_trueAfterThreeConsecutiveMisses() {
        let h = habit(completions: [])   // no completions → every period missed
        XCTAssertTrue(HabitEngine.isStagnant(h, consecutiveMisses: 3, now: now))
    }

    func testIsStagnant_resetsOnRecentHit() {
        // Hit today → the current period isn't a miss, so not stagnant.
        let h = habit(completions: [completion(daysAgo(0))])
        XCTAssertFalse(HabitEngine.isStagnant(h, consecutiveMisses: 3, now: now))
    }

    func testIsStagnant_falseWhenMissesBelowThreshold() {
        // Missed today and yesterday (2), but hit two days ago → fewer than 3
        // consecutive misses.
        let h = habit(completions: [completion(daysAgo(2))])
        XCTAssertFalse(HabitEngine.isStagnant(h, consecutiveMisses: 3, now: now))
    }

    func testIsStagnant_inactiveHabitNeverStagnant() {
        let h = habit(completions: [], archived: true)
        XCTAssertFalse(HabitEngine.isStagnant(h, consecutiveMisses: 3, now: now))
    }
}
