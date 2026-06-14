import XCTest
import HealthKit
@testable import MortalLoom

/// Coverage for `HealthKitService` (issue #58). The service wraps a live
/// `HKHealthStore`, so deterministic unit coverage is limited to the parts that
/// don't depend on a device, granted authorization, or recorded samples:
/// availability reporting, the authorization-completion flag's initial state,
/// and the query helpers' graceful empty-result behaviour.
///
/// The query tests use a date range in the far future: even on an authorized
/// store with real history there can be no samples there, so the result is
/// deterministically empty regardless of authorization state. They're guarded
/// on `isAvailable` so they no-op (rather than hang on a continuation) on a
/// platform without HealthKit.
@MainActor
final class HealthKitServiceTests: XCTestCase {

    func testIsAvailableIsStable() {
        let a = HealthKitService.shared.isAvailable
        let b = HealthKitService.shared.isAvailable
        XCTAssertEqual(a, b, "availability must be a stable per-platform value")
    }

    func testAuthorizationRequestNotCompletedBeforeRequest() {
        // No test in this suite calls requestAuthorization() (it would trigger a
        // real, possibly-blocking system prompt), so the flag stays at its
        // initial false until a real auth round-trip sets it.
        XCTAssertFalse(HealthKitService.shared.authorizationRequestCompleted)
    }

    func testDailyStatsEmptyForFutureRange() async {
        guard HealthKitService.shared.isAvailable else { return }
        let from = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 10)   // ~10y out
        let to = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 10 + 60 * 60 * 24 * 7)
        let stats = await HealthKitService.shared.dailyStats(
            for: .stepCount, unit: .count(), aggregation: .sum, from: from, to: to
        )
        XCTAssertTrue(stats.isEmpty)
    }

    func testDailySleepHoursEmptyForFutureRange() async {
        guard HealthKitService.shared.isAvailable else { return }
        let from = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 10)
        let to = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 10 + 60 * 60 * 24 * 7)
        let sleep = await HealthKitService.shared.dailySleepHours(from: from, to: to)
        XCTAssertTrue(sleep.isEmpty)
    }

    func testDailyMindfulMinutesEmptyForFutureRange() async {
        guard HealthKitService.shared.isAvailable else { return }
        let from = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 10)
        let to = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 10 + 60 * 60 * 24 * 7)
        let mindful = await HealthKitService.shared.dailyMindfulMinutes(from: from, to: to)
        XCTAssertTrue(mindful.isEmpty)
    }
}
