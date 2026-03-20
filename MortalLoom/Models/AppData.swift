import Foundation

struct AppData: Codable, Sendable {
    var profile: HealthProfile
    var alcoholDrinks: [AlcoholDrink]
    var alcoholPresets: [AlcoholPreset]
    var nicotineEntries: [NicotineEntry]
    var nicotinePresets: [NicotinePreset]
    var bloodTests: [BloodTest]
    var eyeExams: [EyeExam]
    var epigeneticTests: [EpigeneticTest]
    var bodyEntries: [BodyEntry]

    static let empty = AppData(
        profile: HealthProfile(birthDate: nil, biologicalSex: nil, lifestyle: .default),
        alcoholDrinks: [],
        alcoholPresets: AlcoholPreset.defaults,
        nicotineEntries: [],
        nicotinePresets: [],
        bloodTests: [],
        eyeExams: [],
        epigeneticTests: [],
        bodyEntries: []
    )

    init(profile: HealthProfile, alcoholDrinks: [AlcoholDrink], alcoholPresets: [AlcoholPreset],
         nicotineEntries: [NicotineEntry], nicotinePresets: [NicotinePreset],
         bloodTests: [BloodTest], eyeExams: [EyeExam], epigeneticTests: [EpigeneticTest],
         bodyEntries: [BodyEntry] = []) {
        self.profile = profile
        self.alcoholDrinks = alcoholDrinks
        self.alcoholPresets = alcoholPresets
        self.nicotineEntries = nicotineEntries
        self.nicotinePresets = nicotinePresets
        self.bloodTests = bloodTests
        self.eyeExams = eyeExams
        self.epigeneticTests = epigeneticTests
        self.bodyEntries = bodyEntries
    }

    // Support decoding files saved before bodyEntries was added
    enum CodingKeys: String, CodingKey {
        case profile, alcoholDrinks, alcoholPresets, nicotineEntries, nicotinePresets
        case bloodTests, eyeExams, epigeneticTests, bodyEntries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decode(HealthProfile.self, forKey: .profile)
        alcoholDrinks = try c.decode([AlcoholDrink].self, forKey: .alcoholDrinks)
        alcoholPresets = try c.decode([AlcoholPreset].self, forKey: .alcoholPresets)
        nicotineEntries = try c.decode([NicotineEntry].self, forKey: .nicotineEntries)
        nicotinePresets = try c.decode([NicotinePreset].self, forKey: .nicotinePresets)
        bloodTests = try c.decode([BloodTest].self, forKey: .bloodTests)
        eyeExams = try c.decode([EyeExam].self, forKey: .eyeExams)
        epigeneticTests = try c.decode([EpigeneticTest].self, forKey: .epigeneticTests)
        bodyEntries = try c.decodeIfPresent([BodyEntry].self, forKey: .bodyEntries) ?? []
    }
}
