import Foundation

/// Pure eligibility and summary math for blood / plasma / platelet donations.
/// No side effects — every function takes the donation list and (where the
/// answer depends on "now") an injectable clock, so the whole surface is
/// testable without touching storage.
///
/// Deferral windows are per-product (see `DonationType.minimumIntervalDays`).
/// Annual caps are evaluated over a rolling 365 days rather than a calendar
/// year, matching how donor centres actually count.
enum DonationEngine {

    // MARK: - Eligibility

    /// The most recent donation of `type`, or nil if there isn't one.
    /// ISO "yyyy-MM-dd" strings sort lexicographically, so `max` on the raw
    /// string is a correct date comparison.
    static func mostRecent(_ donations: [BloodDonation], type: DonationType) -> BloodDonation? {
        donations.lazy.filter { $0.donationType == type }.max { $0.date < $1.date }
    }

    /// Whole days until the donor is eligible for `type` again. 0 means
    /// eligible now — including the never-donated case, so callers can treat
    /// "0" as "go ahead" without a separate nil check.
    static func daysUntilEligible(
        _ donations: [BloodDonation],
        type: DonationType,
        now: Date = Date()
    ) -> Int {
        guard let last = mostRecent(donations, type: type) else { return 0 }
        return max(0, type.minimumIntervalDays - DateFormatting.daysSince(last.date, now: now))
    }

    // MARK: - Rolling-year counts

    /// Donations inside the last 365 days, optionally filtered to one product.
    /// The window is exclusive at the far edge: a donation exactly 365 days
    /// ago has aged out.
    static func inRollingYear(
        _ donations: [BloodDonation],
        type: DonationType? = nil,
        now: Date = Date()
    ) -> [BloodDonation] {
        let cutoff = DateFormatting.dateString(daysAgo: 365, from: now)
        return donations.filter { $0.date > cutoff && (type == nil || $0.donationType == type) }
    }

    /// How many more donations of `type` the annual cap still allows, given
    /// how many are already inside the rolling year. Never negative — a donor
    /// who somehow logged more than the cap reads as 0 remaining rather than a
    /// nonsensical negative allowance.
    static func remaining(inYear used: Int, type: DonationType) -> Int {
        max(0, type.maxDonationsPerYear - used)
    }

    // MARK: - Volume totals

    static func totalVolumeML(_ donations: [BloodDonation]) -> Int {
        donations.reduce(0) { $0 + $1.volumeML }
    }

    /// Lifetime donation count per product, for the breakdown row. Types with
    /// no donations are omitted so the UI doesn't render empty columns;
    /// ordering follows `DonationType.allCases` so the row is stable.
    static func countsByType(_ donations: [BloodDonation]) -> [(type: DonationType, count: Int)] {
        let counts = donations.reduce(into: [DonationType: Int]()) { tally, donation in
            tally[donation.donationType, default: 0] += 1
        }
        return DonationType.allCases.compactMap { type in
            counts[type].map { (type, $0) }
        }
    }

    /// Format a millilitre total for display — millilitres below a litre,
    /// litres to one decimal above it, so lifetime totals stay readable.
    static func formatVolume(_ ml: Int) -> String {
        ml < 1000 ? "\(ml) mL" : String(format: "%.1f L", Double(ml) / 1000)
    }
}
