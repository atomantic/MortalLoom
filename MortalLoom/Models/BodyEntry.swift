import Foundation

struct BodyEntry: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var date: String
    var weightLbs: Double?
    var bodyFatPct: Double?

    init(id: UUID = UUID(), date: String, weightLbs: Double? = nil, bodyFatPct: Double? = nil) {
        self.id = id; self.date = date; self.weightLbs = weightLbs; self.bodyFatPct = bodyFatPct
    }
}
