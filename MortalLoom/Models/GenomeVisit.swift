import Foundation

/// A note captured against a single genome finding during a doctor visit.
/// Created automatically by Visit Mode's `Save & Next` flow, or manually via
/// the detail sheet's `Add to visit notes` button.
///
/// `findingKey` is the rsid for marker/APOE findings, and `"<rsid>:<condition>"`
/// for ClinVar hits where one rsid can implicate multiple conditions.
struct VisitNote: Sendable, Codable, Equatable, Identifiable {
    let id: UUID
    let date: String
    let providerLabel: String?
    let findingKey: String
    var body: String
    var followUp: String?

    init(
        id: UUID = UUID(),
        date: String = DateFormatting.todayString(),
        providerLabel: String? = nil,
        findingKey: String,
        body: String,
        followUp: String? = nil
    ) {
        self.id = id
        self.date = date
        self.providerLabel = providerLabel
        self.findingKey = findingKey
        self.body = body
        self.followUp = followUp
    }
}
