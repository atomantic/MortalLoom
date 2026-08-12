import XCTest
@testable import MortalLoom

/// Coverage for `DonationEngine` — the eligibility / rolling-year / volume math
/// behind the Blood → Donations tab. Every assertion pins "now" to a fixed date
/// and builds dates relative to it, so the suite can't go red on a calendar
/// boundary.
final class DonationEngineTests: XCTestCase {

    /// Fixed clock: 2026-06-01. All fixtures are expressed as offsets from it.
    private let now: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 1
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    private func dateString(daysAgo: Int) -> String {
        DateFormatting.dateString(daysAgo: daysAgo, from: now)
    }

    private func donation(
        _ type: DonationType,
        daysAgo: Int,
        volumeML: Int? = nil,
        location: String = ""
    ) -> BloodDonation {
        BloodDonation(
            donationType: type,
            volumeML: volumeML ?? type.defaultVolumeML,
            date: dateString(daysAgo: daysAgo),
            location: location
        )
    }

    // MARK: - mostRecent

    func testMostRecentPicksLatestOfMatchingType() {
        let recentPlasma = donation(.plasma, daysAgo: 3)
        let donations = [
            donation(.wholeBlood, daysAgo: 1),
            donation(.plasma, daysAgo: 40),
            recentPlasma,
        ]
        XCTAssertEqual(DonationEngine.mostRecent(donations, type: .plasma)?.id, recentPlasma.id)
    }

    func testMostRecentIsNilWhenTypeNeverDonated() {
        let donations = [donation(.wholeBlood, daysAgo: 10)]
        XCTAssertNil(DonationEngine.mostRecent(donations, type: .platelets))
    }

    // MARK: - Eligibility

    func testNeverDonatedIsEligibleNow() {
        XCTAssertEqual(DonationEngine.daysUntilEligible([], type: .wholeBlood, now: now), 0)
    }

    func testDaysUntilEligibleCountsDownTheDeferralWindow() {
        // Whole blood defers 56 days; 20 days in leaves 36 to go.
        let donations = [donation(.wholeBlood, daysAgo: 20)]
        XCTAssertEqual(DonationEngine.daysUntilEligible(donations, type: .wholeBlood, now: now), 36)
    }

    func testEligibleAgainOnTheIntervalBoundary() {
        // Exactly 56 days later the donor is eligible — not 1 day after.
        let donations = [donation(.wholeBlood, daysAgo: 56)]
        XCTAssertEqual(DonationEngine.daysUntilEligible(donations, type: .wholeBlood, now: now), 0)
    }

    func testPastDeferralNeverGoesNegative() {
        let donations = [donation(.platelets, daysAgo: 200)]
        XCTAssertEqual(DonationEngine.daysUntilEligible(donations, type: .platelets, now: now), 0)
    }

    func testDeferralIsPerProduct() {
        // A whole-blood donation yesterday must not defer plasma or platelets:
        // cross-product deferrals are deliberately not modelled.
        let donations = [donation(.wholeBlood, daysAgo: 1)]
        XCTAssertEqual(DonationEngine.daysUntilEligible(donations, type: .wholeBlood, now: now), 55)
        XCTAssertEqual(DonationEngine.daysUntilEligible(donations, type: .plasma, now: now), 0)
        XCTAssertEqual(DonationEngine.daysUntilEligible(donations, type: .platelets, now: now), 0)
    }

    func testEligibilityUsesMostRecentNotFirstDonation() {
        // An old donation must not make the donor look eligible when a recent
        // one still defers them.
        let donations = [
            donation(.platelets, daysAgo: 90),
            donation(.platelets, daysAgo: 2),
        ]
        XCTAssertEqual(DonationEngine.daysUntilEligible(donations, type: .platelets, now: now), 5)
    }

    // MARK: - Rolling year

    func testRollingYearExcludesOlderThan365Days() {
        let donations = [
            donation(.wholeBlood, daysAgo: 400),
            donation(.wholeBlood, daysAgo: 365),
            donation(.wholeBlood, daysAgo: 364),
            donation(.wholeBlood, daysAgo: 1),
        ]
        XCTAssertEqual(DonationEngine.inRollingYear(donations, now: now).count, 2)
    }

    func testRollingYearFiltersByTypeWhenGiven() {
        let donations = [
            donation(.wholeBlood, daysAgo: 10),
            donation(.plasma, daysAgo: 20),
            donation(.plasma, daysAgo: 30),
        ]
        XCTAssertEqual(DonationEngine.inRollingYear(donations, type: .plasma, now: now).count, 2)
        XCTAssertEqual(DonationEngine.inRollingYear(donations, now: now).count, 3)
    }

    func testRemainingCountsAgainstTheCap() {
        // Whole blood caps at 6 per rolling year.
        let donations = (1...4).map { donation(.wholeBlood, daysAgo: $0 * 60) }
        let used = DonationEngine.inRollingYear(donations, type: .wholeBlood, now: now).count
        XCTAssertEqual(DonationEngine.remaining(inYear: used, type: .wholeBlood), 2)
    }

    func testRemainingClampsAtZero() {
        // Over the cap (however it happened) reads as 0 remaining, not negative.
        XCTAssertEqual(DonationEngine.remaining(inYear: 8, type: .wholeBlood), 0)
    }

    func testAgedOutDonationsFreeUpAnnualAllowance() {
        let donations = [
            donation(.wholeBlood, daysAgo: 500),
            donation(.wholeBlood, daysAgo: 100),
        ]
        let used = DonationEngine.inRollingYear(donations, type: .wholeBlood, now: now).count
        XCTAssertEqual(DonationEngine.remaining(inYear: used, type: .wholeBlood), 5)
    }

    // MARK: - Volume

    func testTotalVolumeSumsEveryDonation() {
        let donations = [
            donation(.wholeBlood, daysAgo: 10, volumeML: 500),
            donation(.plasma, daysAgo: 20, volumeML: 700),
        ]
        XCTAssertEqual(DonationEngine.totalVolumeML(donations), 1200)
    }

    func testRollingYearVolumeIgnoresAgedOutDonations() {
        let donations = [
            donation(.wholeBlood, daysAgo: 400, volumeML: 500),
            donation(.wholeBlood, daysAgo: 30, volumeML: 480),
        ]
        let inYear = DonationEngine.inRollingYear(donations, now: now)
        XCTAssertEqual(DonationEngine.totalVolumeML(inYear), 480)
    }

    func testFormatVolumeSwitchesToLitresAtOneThousand() {
        XCTAssertEqual(DonationEngine.formatVolume(0), "0 mL")
        XCTAssertEqual(DonationEngine.formatVolume(500), "500 mL")
        XCTAssertEqual(DonationEngine.formatVolume(999), "999 mL")
        XCTAssertEqual(DonationEngine.formatVolume(1000), "1.0 L")
        XCTAssertEqual(DonationEngine.formatVolume(2450), "2.5 L")
    }

    // MARK: - Breakdown

    func testCountsByTypeOmitsUndonatedProducts() {
        let donations = [
            donation(.wholeBlood, daysAgo: 10),
            donation(.wholeBlood, daysAgo: 80),
            donation(.platelets, daysAgo: 20),
        ]
        let counts = DonationEngine.countsByType(donations)
        XCTAssertEqual(counts.count, 2)
        XCTAssertEqual(counts.first?.type, .wholeBlood)
        XCTAssertEqual(counts.first?.count, 2)
        XCTAssertEqual(counts.last?.type, .platelets)
        XCTAssertEqual(counts.last?.count, 1)
    }

    func testCountsByTypeIsEmptyWithoutDonations() {
        XCTAssertTrue(DonationEngine.countsByType([]).isEmpty)
    }
}
