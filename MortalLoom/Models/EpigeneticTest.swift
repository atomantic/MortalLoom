import Foundation

struct EpigeneticTest: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var date: String // "YYYY-MM-DD"
    var chronologicalAge: Double
    var biologicalAge: Double
    var paceOfAging: Double? // < 1 is good
    var organScores: [String: Double]? // organ name -> biological age

    init(id: UUID = UUID(), date: String, chronologicalAge: Double, biologicalAge: Double, paceOfAging: Double? = nil, organScores: [String: Double]? = nil) {
        self.id = id; self.date = date; self.chronologicalAge = chronologicalAge; self.biologicalAge = biologicalAge
        self.paceOfAging = paceOfAging; self.organScores = organScores
    }
}
