import XCTest
@testable import MortalLoom

final class GoalVelocityEngineTests: XCTestCase {
    private var now: Date {
        DateFormatting.dateFromString("2026-12-01")!
    }

    private func checkIn(_ date: String, _ progress: Double) -> GoalCheckIn {
        GoalCheckIn(date: date, progressPct: progress)
    }

    func testNormalizesByDaysAndRetainsSignedChanges() {
        let result = GoalVelocityEngine.intervals(checkIns: [
            checkIn("2026-11-22", 30),
            checkIn("2026-11-01", 20),
            checkIn("2026-11-15", 50),
            checkIn("2026-11-29", 30)
        ], now: now)

        XCTAssertEqual(result.map(\.pointsPerWeek), [15, -20, 0])
        XCTAssertEqual(result.map { DateFormatting.dateString($0.end) },
                       ["2026-11-15", "2026-11-22", "2026-11-29"])
    }

    func testCoalescesSameDayAndIgnoresFutureAndInvalidDates() {
        let result = GoalVelocityEngine.intervals(checkIns: [
            checkIn("2026-11-03", 10),
            checkIn("not-a-date", 30),
            checkIn("2026-11-3", 60),
            checkIn("2026-11-03", 20),
            checkIn("2026-11-10", 30),
            checkIn("2026-12-04", 40)
        ], now: now)

        XCTAssertEqual(result.map(\.pointsPerWeek), [10])
        XCTAssertTrue(GoalVelocityEngine.intervals(
            checkIns: [checkIn("2026-11-03", 10), checkIn("2026-11-03", 30)],
            now: now
        ).isEmpty)
    }

    func testOnlyStandardGoalsWithHistoryAppearIncludingLegacyAndCompleted() {
        let history = [checkIn("2026-11-01", 40), checkIn("2026-11-08", 50)]
        let completed = Goal(title: "Completed", checkIns: history, status: .completed, goalType: .standard)
        let legacy = Goal(title: "Legacy", checkIns: history)
        let goals = [
            legacy, completed,
            Goal(title: "An apex", checkIns: history, goalType: .apex),
            Goal(title: "A pillar", checkIns: history, goalType: .subApex),
            Goal(title: "One reading", checkIns: [history[0]], goalType: .standard)
        ]
        XCTAssertEqual(GoalVelocityEngine.series(goals: goals, now: now).map(\.id),
                       [completed.id, legacy.id])
    }

    func testLimitsChartToMostRecentTwelveIntervals() {
        let checkIns = (1...20).map { checkIn(String(format: "2026-11-%02d", $0), Double($0)) }
        let result = GoalVelocityEngine.intervals(checkIns: checkIns, now: now)
        XCTAssertEqual(result.count, 12)
        XCTAssertEqual(result.first.map { DateFormatting.dateString($0.start) }, "2026-11-08")
        XCTAssertEqual(result.last.map { DateFormatting.dateString($0.end) }, "2026-11-20")
    }
}
