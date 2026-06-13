import XCTest
@testable import MortalLoom

// MARK: - MonthlyReportEngine + MonthlyRethink Tests
//
// Pure-function coverage for the "Monthly rethink card + export" feature
// (issue #48): last-complete-month math, markdown report content (month
// scoping of reflections + alignment), and the end-of-month card scheduling.

final class MonthlyReportEngineTests: XCTestCase {

    // MARK: - Fixtures

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    private func checkIn(date: String, rating: Int? = nil, note: String = "", prompt: String? = nil) -> GoalCheckIn {
        GoalCheckIn(date: date, note: note, alignmentRating: rating, promptAnswered: prompt)
    }

    private func appData(goals: [Goal], habits: [Habit] = []) -> AppData {
        var data = AppData.empty
        data.goals = goals
        data.habits = habits
        return data
    }

    // MARK: - lastCompleteMonth

    func testLastCompleteMonthReturnsPriorMonth() {
        let range = MonthlyReportEngine.lastCompleteMonth(now: date(2026, 6, 13))
        let r = try? XCTUnwrap(range)
        XCTAssertEqual(r?.year, 2026)
        XCTAssertEqual(r?.month, 5)
        XCTAssertEqual(r?.label, "May 2026")
        XCTAssertEqual(r?.startStr, "2026-05-01")
        XCTAssertEqual(r?.endStr, "2026-06-01")
    }

    func testLastCompleteMonthWrapsAcrossYearBoundary() {
        let range = MonthlyReportEngine.lastCompleteMonth(now: date(2026, 1, 5))
        XCTAssertEqual(range?.year, 2025)
        XCTAssertEqual(range?.month, 12)
        XCTAssertEqual(range?.label, "December 2025")
        XCTAssertEqual(range?.startStr, "2025-12-01")
        XCTAssertEqual(range?.endStr, "2026-01-01")
    }

    // MARK: - markdown

    func testMarkdownScopesReflectionsToMonth() {
        let apex = Goal(
            title: "Write a novel",
            checkIns: [
                checkIn(date: "2026-04-25", rating: 6, note: "Previous month — should be excluded"),
                checkIn(date: "2026-05-10", rating: 7, note: "Mid-month reflection", prompt: "Are these still the right goals?"),
                checkIn(date: "2026-05-28", rating: 9, note: "End of month reflection"),
                checkIn(date: "2026-06-02", rating: 4, note: "Next month — should be excluded")
            ],
            status: .active,
            goalType: .apex
        )
        let data = appData(goals: [apex])
        let month = MonthlyReportEngine.lastCompleteMonth(now: date(2026, 6, 13))!
        let md = MonthlyReportEngine.markdown(from: data, month: month, now: date(2026, 6, 13))

        XCTAssertTrue(md.contains("# Monthly Review — May 2026"))
        XCTAssertTrue(md.contains("All data stays on your device"))
        XCTAssertTrue(md.contains("**North Star:** Write a novel"))
        // In-month reflections present, out-of-month excluded.
        XCTAssertTrue(md.contains("Mid-month reflection"))
        XCTAssertTrue(md.contains("End of month reflection"))
        XCTAssertFalse(md.contains("should be excluded"))
        // Average of in-month ratings 7 and 9 = 8.0.
        XCTAssertTrue(md.contains("Average alignment: **8.0 / 10**"))
        // Trend uses chronological first→last (7 → 9).
        XCTAssertTrue(md.contains("7 → 9"))
    }

    func testMarkdownHandlesNoReflections() {
        let apex = Goal(title: "Stay healthy", status: .active, goalType: .apex)
        let data = appData(goals: [apex])
        let month = MonthlyReportEngine.lastCompleteMonth(now: date(2026, 6, 13))!
        let md = MonthlyReportEngine.markdown(from: data, month: month, now: date(2026, 6, 13))

        XCTAssertTrue(md.contains("No alignment reflections recorded this month."))
        XCTAssertTrue(md.contains("No reflections recorded this month."))
        XCTAssertTrue(md.contains("## Habit streaks"))
        XCTAssertTrue(md.contains("No active habits."))
    }

    func testMarkdownAlwaysIncludesAllSections() {
        let data = appData(goals: [])
        let month = MonthlyReportEngine.lastCompleteMonth(now: date(2026, 6, 13))!
        let md = MonthlyReportEngine.markdown(from: data, month: month, now: date(2026, 6, 13))

        XCTAssertTrue(md.contains("## Alignment trend"))
        XCTAssertTrue(md.contains("## Reflections"))
        XCTAssertTrue(md.contains("## What's stalling"))
        XCTAssertTrue(md.contains("## Habit streaks"))
    }
}

// MARK: - MonthlyRethink scheduling

final class MonthlyRethinkSchedulingTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    func testWindowOpensInClosingDaysOnly() {
        // May has 31 days; windowDays = 5 → days 27...31 are in-window.
        XCTAssertFalse(MonthlyRethink.isInEndOfMonthWindow(now: date(2026, 5, 20)))
        XCTAssertFalse(MonthlyRethink.isInEndOfMonthWindow(now: date(2026, 5, 26)))
        XCTAssertTrue(MonthlyRethink.isInEndOfMonthWindow(now: date(2026, 5, 27)))
        XCTAssertTrue(MonthlyRethink.isInEndOfMonthWindow(now: date(2026, 5, 31)))
    }

    func testWindowAccountsForShorterMonths() {
        // February 2026 has 28 days → window is days 24...28.
        XCTAssertFalse(MonthlyRethink.isInEndOfMonthWindow(now: date(2026, 2, 23)))
        XCTAssertTrue(MonthlyRethink.isInEndOfMonthWindow(now: date(2026, 2, 24)))
        XCTAssertTrue(MonthlyRethink.isInEndOfMonthWindow(now: date(2026, 2, 28)))
    }

    func testIsDoneForMonth() {
        let now = date(2026, 5, 28)
        XCTAssertTrue(MonthlyRethink.isDone(forMonthOf: now, lastDate: "2026-05-10"))
        XCTAssertFalse(MonthlyRethink.isDone(forMonthOf: now, lastDate: "2026-04-28"))
        XCTAssertFalse(MonthlyRethink.isDone(forMonthOf: now, lastDate: nil))
    }

    func testIsDueRequiresWindowAndNotDone() {
        // In window, not done this month → due.
        XCTAssertTrue(MonthlyRethink.isDue(now: date(2026, 5, 28), lastDate: "2026-04-28"))
        // In window but already done this month → not due.
        XCTAssertFalse(MonthlyRethink.isDue(now: date(2026, 5, 28), lastDate: "2026-05-27"))
        // Not in window → not due regardless.
        XCTAssertFalse(MonthlyRethink.isDue(now: date(2026, 5, 15), lastDate: nil))
    }
}
