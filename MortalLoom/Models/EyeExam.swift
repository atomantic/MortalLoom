import Foundation

struct EyeExam: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var date: String // "YYYY-MM-DD"
    var leftSphere: Double?
    var leftCylinder: Double?
    var leftAxis: Int?
    var rightSphere: Double?
    var rightCylinder: Double?
    var rightAxis: Int?

    init(id: UUID = UUID(), date: String, leftSphere: Double? = nil, leftCylinder: Double? = nil, leftAxis: Int? = nil, rightSphere: Double? = nil, rightCylinder: Double? = nil, rightAxis: Int? = nil) {
        self.id = id; self.date = date
        self.leftSphere = leftSphere; self.leftCylinder = leftCylinder; self.leftAxis = leftAxis
        self.rightSphere = rightSphere; self.rightCylinder = rightCylinder; self.rightAxis = rightAxis
    }
}
