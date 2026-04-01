import Foundation

struct HealthProfile: Codable, Sendable, Equatable {
    var birthDate: String? // "YYYY-MM-DD"
    var biologicalSex: BiologicalSex?
    var lifestyle: LifestyleData
    var countdownMode: CountdownMode
    var levTargetAge: Double // assumed max lifespan if LEV is achieved (default 120)

    enum CodingKeys: String, CodingKey {
        case birthDate, biologicalSex, lifestyle, countdownMode, levTargetAge
    }

    init(birthDate: String? = nil, biologicalSex: BiologicalSex? = nil, lifestyle: LifestyleData, countdownMode: CountdownMode = .standard, levTargetAge: Double = 120) {
        self.birthDate = birthDate
        self.biologicalSex = biologicalSex
        self.lifestyle = lifestyle
        self.countdownMode = countdownMode
        self.levTargetAge = levTargetAge
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate)
        biologicalSex = try c.decodeIfPresent(BiologicalSex.self, forKey: .biologicalSex)
        lifestyle = try c.decode(LifestyleData.self, forKey: .lifestyle)
        countdownMode = try c.decodeIfPresent(CountdownMode.self, forKey: .countdownMode) ?? .standard
        levTargetAge = try c.decodeIfPresent(Double.self, forKey: .levTargetAge) ?? 120
    }
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

enum CountdownMode: String, Codable, Sendable, CaseIterable {
    case standard = "Standard"
    case lev = "LEV"

    var pickerLabel: String { rawValue }
}
