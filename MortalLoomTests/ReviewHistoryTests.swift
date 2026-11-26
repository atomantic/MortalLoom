import XCTest
@testable import MortalLoom

final class ReviewHistoryTests: XCTestCase {
    private let calendar = ReviewHistory.calendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    private func date(_ key: String) throws -> Date {
        try XCTUnwrap(ReviewHistory.parseDay(key, formatter: ReviewHistory.dayFormatter(calendar: calendar)))
    }

    func testDailyStreakCalendarGroupsLogsAndKeepsLocalDayAcrossDST() throws {
        let habit = Habit(name: "Read", cadence: .init(period: .daily, target: 2), createdDate: "2026-03-07",
                          completions: [.init(date: "2026-03-06", count: 4),
                                        .init(date: "2026-03-08"),
                                        .init(date: "2026-03-09"),
                                        .init(date: "2026-03-09"),
                                        .init(date: "2026-03-10", count: 9)])
        let cells = HabitStreakCalendar.periods(for: habit, now: try date("2026-03-09"), calendar: calendar)
        XCTAssertEqual(cells.count, 42)
        let recent = Array(cells.suffix(4))
        XCTAssertEqual(recent.map(\.isTracked), [false, true, true, true])
        XCTAssertEqual(recent.map(\.count), [0, 0, 1, 2])
        XCTAssertEqual(recent.map(\.meetsTarget), [false, false, false, true])
        XCTAssertEqual(recent.last?.start, try date("2026-03-09"))
        XCTAssertEqual(recent[3].start.timeIntervalSince(recent[2].start), 23 * 60 * 60)
    }

    func testMidnightDSTTransitionDoesNotLosePriorDayLogs() throws {
        let calendar = ReviewHistory.calendar(timeZone: TimeZone(identifier: "America/Sao_Paulo")!)
        let formatter = ReviewHistory.dayFormatter(calendar: calendar)
        let now = try XCTUnwrap(ReviewHistory.parseDay("2018-11-04", formatter: formatter))
        XCTAssertEqual(calendar.component(.hour, from: calendar.startOfDay(for: now)), 1)
        let habit = Habit(name: "Walk", createdDate: "2018-11-01",
                          completions: [.init(date: "2018-11-03"), .init(date: "2018-11-04")])
        let cells = HabitStreakCalendar.periods(for: habit, now: now, calendar: calendar)
        XCTAssertEqual(Array(cells.suffix(2)).map(\.count), [1, 1])
    }

    func testWeeklyCalendarUsesMondayAndDoesNotCountFutureEntries() throws {
        let habit = Habit(name: "Practice", cadence: .init(period: .weekly, target: 3), createdDate: "2025-12-22",
                          completions: [.init(date: "2025-12-28", count: 2),
                                        .init(date: "2025-12-29"),
                                        .init(date: "2026-01-01", count: 2),
                                        .init(date: "2026-01-02", count: 5)])
        let cells = HabitStreakCalendar.periods(for: habit, now: try date("2026-01-01"), calendar: calendar)
        XCTAssertEqual(cells.count, 16)
        XCTAssertEqual(cells.last?.start, try date("2025-12-29"))
        XCTAssertEqual(Array(cells.suffix(2)).map(\.count), [2, 3])
        XCTAssertEqual(Array(cells.suffix(2)).map(\.meetsTarget), [false, true])
    }

    func testYearReviewRestrictsRecordsAndEscapesUserAuthoredMarkdown() throws {
        var data = AppData.empty
        data.goals = [Goal(title: "Learn *piano*", createdDate: "2024-12-31", completedDate: "2026-01-01",
                           checkIns: [.init(date: "2024-12-31", note: "Prior year", alignmentRating: 5),
                                      .init(date: "2025-01-01", progressPct: 20),
                                      .init(date: "2025-12-31", note: "Private diary\n![image](https://example.test/img)",
                                            alignmentRating: 8, blockers: ["Travel"], commitments: ["Practice"]),
                                      .init(date: "2026-01-01", note: "Next year", alignmentRating: 9)])]
        data.habits = [Habit(name: "Practice", createdDate: "2024-12-29", archivedDate: "2026-01-01",
                            completions: [.init(date: "2025-01-01"), .init(date: "2025-01-01", count: 2),
                                          .init(date: "2025-02-30", count: 17), .init(date: "2026-01-01", count: 4)])]
        let now = try date("2026-01-01")
        XCTAssertEqual(YearlyReviewEngine.availableYears(from: data, now: now, calendar: calendar), [2026, 2025, 2024])
        let report = YearlyReviewEngine.markdown(from: data, year: 2025, now: now, calendar: calendar)
        XCTAssertTrue(report.contains("Yearly Review — 2025"))
        XCTAssertTrue(report.contains("0 created · 0 completed · 2 check-ins"))
        XCTAssertTrue(report.contains("Practice: 3 completions across 1 day"))
        XCTAssertTrue(report.contains("2025-12-31 · Learn \\*piano\\*"))
        XCTAssertTrue(report.contains("Alignment: 8/10"))
        XCTAssertTrue(report.contains("Private diary \\!\\[image\\]"))
        XCTAssertTrue(report.contains("Blocker: Travel"))
        XCTAssertTrue(report.contains("Commitment: Practice"))
        XCTAssertFalse(report.contains("Prior year"))
        XCTAssertFalse(report.contains("Next year"))
        XCTAssertFalse(report.contains("2026-01-01"))
        XCTAssertFalse(report.contains("![image]"))
    }

    func testCurrentYearReviewExcludesFutureDatesAndHandlesNoData() throws {
        var data = AppData.empty
        data.goals = [Goal(title: "Future", createdDate: "2027-01-01",
                           checkIns: [.init(date: "2026-06-02", note: "Future note", alignmentRating: 4)])]
        let now = try date("2026-06-01")
        XCTAssertEqual(YearlyReviewEngine.availableYears(from: data, now: now, calendar: calendar), [2026])
        let report = YearlyReviewEngine.markdown(from: data, year: 2026, now: now, calendar: calendar)
        XCTAssertTrue(report.contains("Year to date through 2026-06-01."))
        XCTAssertTrue(report.contains("No habit completions recorded."))
        XCTAssertTrue(report.contains("No reflections recorded."))
        XCTAssertFalse(report.contains("Future"))
    }
}
