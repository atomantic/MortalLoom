import Foundation

struct HealthProfile: Codable, Sendable, Equatable {
    var birthDate: String? // "YYYY-MM-DD"
    var biologicalSex: BiologicalSex?
    var lifestyle: LifestyleData
    var countdownMode: CountdownMode
    var levTargetAge: Double // assumed max lifespan if LEV is achieved (default 120)
    var locationProfile: LocationProfile?
    var socioeconomic: SocioeconomicProfile?

    enum CodingKeys: String, CodingKey {
        case birthDate, biologicalSex, lifestyle, countdownMode, levTargetAge, locationProfile, socioeconomic
    }

    init(birthDate: String? = nil, biologicalSex: BiologicalSex? = nil, lifestyle: LifestyleData, countdownMode: CountdownMode = .standard, levTargetAge: Double = 120, locationProfile: LocationProfile? = nil, socioeconomic: SocioeconomicProfile? = nil) {
        self.birthDate = birthDate
        self.biologicalSex = biologicalSex
        self.lifestyle = lifestyle
        self.countdownMode = countdownMode
        self.levTargetAge = levTargetAge
        self.locationProfile = locationProfile
        self.socioeconomic = socioeconomic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate)
        biologicalSex = try c.decodeIfPresent(BiologicalSex.self, forKey: .biologicalSex)
        lifestyle = try c.decode(LifestyleData.self, forKey: .lifestyle)
        countdownMode = try c.decodeIfPresent(CountdownMode.self, forKey: .countdownMode) ?? .standard
        levTargetAge = try c.decodeIfPresent(Double.self, forKey: .levTargetAge) ?? 120
        locationProfile = try c.decodeIfPresent(LocationProfile.self, forKey: .locationProfile)
        socioeconomic = try c.decodeIfPresent(SocioeconomicProfile.self, forKey: .socioeconomic)
    }
}

struct SocioeconomicProfile: Codable, Sendable, Equatable {
    var education: EducationLevel?
    var incomeBracket: IncomeBracket?

    init(education: EducationLevel? = nil, incomeBracket: IncomeBracket? = nil) {
        self.education = education
        self.incomeBracket = incomeBracket
    }
}

enum EducationLevel: String, Codable, Sendable, CaseIterable {
    case noHighSchool   = "No HS"
    case highSchool     = "High School"
    case someCollege    = "Some College"
    case bachelors      = "Bachelor's"
    case graduate       = "Graduate"

    var displayName: String {
        switch self {
        case .noHighSchool: return "No High School"
        case .highSchool:   return "High School"
        case .someCollege:  return "Some College"
        case .bachelors:    return "Bachelor's"
        case .graduate:     return "Graduate Degree"
        }
    }
}

enum IncomeBracket: String, Codable, Sendable, CaseIterable {
    case q1 = "Bottom 20%"     // lowest quintile
    case q2 = "Lower-Middle"   // 2nd quintile
    case q3 = "Middle"         // 3rd quintile
    case q4 = "Upper-Middle"   // 4th quintile
    case q5 = "Top 20%"        // highest quintile

    var displayName: String { rawValue }
}

struct LocationProfile: Codable, Sendable, Equatable {
    var countryCode: String?         // ISO 3166-1 alpha-2, e.g. "US", "JP"
    var regionCode: String?          // ISO 3166-2, e.g. "US-CA", "GB-ENG" (nil when unknown)
    var airQuality: AirQualityLevel? // nil = use default (moderate/no adjustment)
    var useAutoDetect: Bool          // whether to auto-detect country via location

    init(countryCode: String? = nil, regionCode: String? = nil, airQuality: AirQualityLevel? = nil, useAutoDetect: Bool = false) {
        self.countryCode = countryCode
        self.regionCode = regionCode
        self.airQuality = airQuality
        self.useAutoDetect = useAutoDetect
    }

    enum CodingKeys: String, CodingKey {
        case countryCode, regionCode, airQuality, useAutoDetect
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode)
        regionCode = try c.decodeIfPresent(String.self, forKey: .regionCode)
        airQuality = try c.decodeIfPresent(AirQualityLevel.self, forKey: .airQuality)
        useAutoDetect = try c.decodeIfPresent(Bool.self, forKey: .useAutoDetect) ?? false
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

    /// Short explainer strings shared by every place the Standard-vs-LEV
    /// toggle appears (Calendar info popover, Settings countdown footnote,
    /// future widget configuration). Keeping them here prevents the copy
    /// from drifting as new surfaces adopt the toggle.
    static let standardBlurb = "Standard: SSA actuarial life expectancy + lifestyle adjustments."
    static let levBlurb = "LEV: Assumes longevity-escape-velocity therapies kick in around 2045 and extend lifespan to your target age."
}
