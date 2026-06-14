import XCTest
@testable import MortalLoom

// MARK: - ReflectionPlan Tests
//
// Pure-function coverage for the calendar-component builders behind the
// plan-based notification scheduler (NotificationService.scheduleReflectionPlan).
// Each ritual maps to a different DateComponents shape, and the clamps guard
// against prefs that the calendar can't satisfy (out-of-range hours, a
// day-of-month past 28 that would skip short months).

final class ReflectionPlanTests: XCTestCase {

    // MARK: Daily

    func testDailyComponentsMatchHourEveryDay() {
        let c = ReflectionPlan.dailyComponents(hour: 9)
        XCTAssertEqual(c.hour, 9)
        XCTAssertEqual(c.minute, 0)
        // Daily fires on every day/weekday — so neither is constrained.
        XCTAssertNil(c.weekday)
        XCTAssertNil(c.day)
    }

    // MARK: Weekly

    func testWeeklyComponentsConstrainWeekdayAndHour() {
        let c = ReflectionPlan.weeklyComponents(weekday: 4, hour: 18)
        XCTAssertEqual(c.weekday, 4)
        XCTAssertEqual(c.hour, 18)
        XCTAssertEqual(c.minute, 0)
        XCTAssertNil(c.day)
    }

    // MARK: Monthly

    func testMonthlyComponentsConstrainDayAndHour() {
        let c = ReflectionPlan.monthlyComponents(day: 15, hour: 6)
        XCTAssertEqual(c.day, 15)
        XCTAssertEqual(c.hour, 6)
        XCTAssertEqual(c.minute, 0)
        XCTAssertNil(c.weekday)
    }

    func testMonthlyDayClampedTo28SoEveryMonthFires() {
        // A 31 would silently skip February/April/etc. — clamp to 28.
        XCTAssertEqual(ReflectionPlan.monthlyComponents(day: 31, hour: 0).day, 28)
        XCTAssertEqual(ReflectionPlan.clampMonthDay(31), 28)
        XCTAssertEqual(ReflectionPlan.clampMonthDay(0), 1)
        XCTAssertEqual(ReflectionPlan.clampMonthDay(15), 15)
    }

    // MARK: Clamps

    func testHourClampedToValidRange() {
        XCTAssertEqual(ReflectionPlan.clampHour(-3), 0)
        XCTAssertEqual(ReflectionPlan.clampHour(25), 23)
        XCTAssertEqual(ReflectionPlan.clampHour(13), 13)
        // The builders apply the clamp, not just the helper.
        XCTAssertEqual(ReflectionPlan.dailyComponents(hour: 99).hour, 23)
    }

    func testWeekdayClampedToValidRange() {
        XCTAssertEqual(ReflectionPlan.clampWeekday(0), 1)
        XCTAssertEqual(ReflectionPlan.clampWeekday(9), 7)
        XCTAssertEqual(ReflectionPlan.clampWeekday(3), 3)
        XCTAssertEqual(ReflectionPlan.weeklyComponents(weekday: 0, hour: 0).weekday, 1)
    }
}
