import Foundation

struct HealthProfile: Codable, Sendable, Equatable {
    var birthDate: String? // "YYYY-MM-DD"
    var biologicalSex: BiologicalSex?
    var lifestyle: LifestyleData
}

enum BiologicalSex: String, Codable, Sendable, CaseIterable {
    case male, female
}

struct LifestyleData: Codable, Sendable, Equatable {
    var smokingStatus: SmokingStatus
    var exerciseMinutesPerWeek: Int
    var sleepHoursPerNight: Double
    var dietQuality: DietQuality
    var stressLevel: StressLevel
    var bmi: Double?

    static let `default` = LifestyleData(
        smokingStatus: .never,
        exerciseMinutesPerWeek: 150,
        sleepHoursPerNight: 7.5,
        dietQuality: .good,
        stressLevel: .moderate,
        bmi: nil
    )
}

enum SmokingStatus: String, Codable, Sendable, CaseIterable {
    case never, former, current
}

enum DietQuality: String, Codable, Sendable, CaseIterable {
    case excellent, good, fair, poor
}

enum StressLevel: String, Codable, Sendable, CaseIterable {
    case low, moderate, high
}
