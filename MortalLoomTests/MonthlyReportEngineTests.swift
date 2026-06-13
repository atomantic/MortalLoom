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

// MARK: - MonthlyRethinkEngine (finish bookkeeping)

final class MonthlyRethinkEngineTests: XCTestCase {

    private func goal(_ title: String, type: GoalType, parent: UUID? = nil) -> Goal {
        Goal(title: title, status: .active, parentId: parent, goalType: type)
    }

    /// apex → [pillar] → [g1, g2] tree.
    private func tree() -> (apex: Goal, pillar: Goal, g1: Goal, g2: Goal) {
        let apex = goal("North Star", type: .apex)
        let pillar = goal("Health", type: .subApex, parent: apex.id)
        let g1 = goal("Run 5k", type: .standard, parent: pillar.id)
        let g2 = goal("Sleep 8h", type: .standard, parent: pillar.id)
        return (apex, pillar, g1, g2)
    }

    func testArchivesNonApexAndAppendsSingleCheckIn() {
        let t = tree()
        let goals = [t.apex, t.pillar, t.g1, t.g2]
        let outcome = MonthlyRethinkEngine.summarize(
            allGoals: goals,
            workingGoals: goals,
            archivedIds: [t.g1.id],
            answer: "Refocusing on sleep.",
            alignmentRating: 7,
            prompt: "Are these still the right goals?",
            checkInDate: "2026-05-31"
        )
        let o = try? XCTUnwrap(outcome)
        // One goal archived → status .abandoned.
        XCTAssertEqual(o?.archivedGoals.count, 1)
        XCTAssertEqual(o?.archivedGoals.first?.id, t.g1.id)
        XCTAssertEqual(o?.archivedGoals.first?.status, .abandoned)
        XCTAssertEqual(o?.archivedCount, 1)
        // Tree has apex + pillar + 2 goals = 4 active; 1 archived → 3 kept.
        XCTAssertEqual(o?.keptCount, 3)
        XCTAssertEqual(o?.editedCount, 0)
        // Exactly one compound check-in appended to the apex.
        XCTAssertEqual(o?.apexToSave.id, t.apex.id)
        XCTAssertEqual(o?.apexToSave.checkIns.count, 1)
        let ci = o?.apexToSave.checkIns.last
        XCTAssertEqual(ci?.alignmentRating, 7)
        XCTAssertEqual(ci?.date, "2026-05-31")
        XCTAssertEqual(ci?.promptAnswered, "Are these still the right goals?")
        XCTAssertEqual(ci?.progressPct, 0)
        XCTAssertTrue(ci?.note.contains("kept 3, edited 0, archived 1") ?? false)
        XCTAssertTrue(ci?.note.contains("Refocusing on sleep.") ?? false)
    }

    func testApexIsNeverArchivedEvenIfRequested() {
        let t = tree()
        let goals = [t.apex, t.pillar, t.g1, t.g2]
        let outcome = MonthlyRethinkEngine.summarize(
            allGoals: goals,
            workingGoals: goals,
            archivedIds: [t.apex.id, t.g2.id],
            answer: "",
            alignmentRating: 5,
            prompt: "x"
        )
        let o = try? XCTUnwrap(outcome)
        // Apex id was in archivedIds but must not be archived.
        XCTAssertFalse(o?.archivedGoals.contains { $0.id == t.apex.id } ?? true)
        XCTAssertEqual(o?.archivedGoals.map(\.id), [t.g2.id])
        XCTAssertEqual(o?.archivedCount, 1)
    }

    func testEditedAndArchivedGoalCountsOnlyAsArchived() {
        let t = tree()
        var editedG1 = t.g1
        editedG1.title = "Run 10k"        // inline-edited
        // g1 is BOTH edited and archived.
        let working = [t.apex, t.pillar, editedG1, t.g2]
        let outcome = MonthlyRethinkEngine.summarize(
            allGoals: [t.apex, t.pillar, t.g1, t.g2],
            workingGoals: working,
            archivedIds: [editedG1.id],
            answer: "",
            alignmentRating: 5,
            prompt: "x"
        )
        let o = try? XCTUnwrap(outcome)
        XCTAssertEqual(o?.archivedCount, 1)
        // g1 was edited but is archived → not double-counted as edited.
        XCTAssertEqual(o?.editedCount, 0)
        // 4 active − 1 archived = 3 kept; counts never exceed tree size.
        XCTAssertEqual(o?.keptCount, 3)
    }

    func testCountsEditedGoal() {
        let t = tree()
        var editedG2 = t.g2
        editedG2.title = "Sleep 9h"
        let working = [t.apex, t.pillar, t.g1, editedG2]
        let outcome = MonthlyRethinkEngine.summarize(
            allGoals: [t.apex, t.pillar, t.g1, t.g2],
            workingGoals: working,
            archivedIds: [],
            answer: "",
            alignmentRating: 5,
            prompt: "x"
        )
        XCTAssertEqual(outcome?.editedCount, 1)
        XCTAssertEqual(outcome?.archivedCount, 0)
        XCTAssertEqual(outcome?.keptCount, 4)
    }

    func testReturnsNilWithoutApex() {
        let pillar = goal("Health", type: .subApex)
        let outcome = MonthlyRethinkEngine.summarize(
            allGoals: [pillar],
            workingGoals: [pillar],
            archivedIds: [],
            answer: "",
            alignmentRating: 5,
            prompt: "x"
        )
        XCTAssertNil(outcome)
    }
}
