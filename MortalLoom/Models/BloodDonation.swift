import Foundation

// MARK: - Donation Type

/// Which blood product was collected. The product drives both the form's
/// default volume and the deferral math in `DonationEngine`, since each one
/// has its own collection volume and minimum interval between donations.
///
/// Raw values are stable codes, deliberately *not* the display strings: they
/// are persisted into the data file and synced across devices, so renaming a
/// label must never make an existing donation undecodable.
enum DonationType: String, Codable, Sendable, CaseIterable, Equatable {
    case wholeBlood
    case plasma
    case platelets

    var label: String {
        switch self {
        case .wholeBlood: "Whole Blood"
        case .plasma: "Plasma"
        case .platelets: "Platelets"
        }
    }

    /// Typical collection volume in millilitres, used to prefill the log form.
    /// Actual draws vary by donor weight and centre, so the field stays editable.
    var defaultVolumeML: Int {
        switch self {
        case .wholeBlood: 500
        case .plasma: 700
        case .platelets: 300
        }
    }

    /// Minimum days between two donations of the *same* product (US Red Cross
    /// guidance). Cross-product deferrals — how long a whole-blood draw defers
    /// a platelet donation, and vice versa — are deliberately not modelled:
    /// they differ between collection centres, and guessing would make the
    /// eligibility readout wrong rather than merely incomplete. The UI labels
    /// this a same-product estimate and points at the donor centre for the
    /// authoritative answer.
    var minimumIntervalDays: Int {
        switch self {
        case .wholeBlood: 56
        case .plasma: 28
        case .platelets: 7
        }
    }

    /// Maximum donations of this product allowed in a rolling 12 months
    /// (US Red Cross guidance).
    var maxDonationsPerYear: Int {
        switch self {
        case .wholeBlood: 6
        case .plasma: 13
        case .platelets: 24
        }
    }

    var icon: String {
        switch self {
        case .wholeBlood: "drop.fill"
        case .plasma: "drop.circle.fill"
        case .platelets: "drop.triangle.fill"
        }
    }
}

// MARK: - Blood Donation

/// One logged donation: what was given, how much, when, and where.
struct BloodDonation: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var donationType: DonationType
    var volumeML: Int
    var date: String // "YYYY-MM-DD"
    /// Free-text collection site. Empty when the user didn't record one.
    var location: String

    init(
        id: UUID = UUID(),
        donationType: DonationType,
        volumeML: Int,
        date: String,
        location: String = ""
    ) {
        self.id = id
        self.donationType = donationType
        self.volumeML = volumeML
        self.date = date
        self.location = location
    }
}
