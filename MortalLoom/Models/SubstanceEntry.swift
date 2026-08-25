import Foundation

struct AlcoholDrink: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var oz: Double
    var abv: Double
    /// The number of servings consumed. A `Double` permits partial drinks,
    /// such as half a beer or a shared cocktail.
    var count: Double
    var date: String // "YYYY-MM-DD"

    var standardDrinks: Double {
        (oz * count * (abv / 100)) / 0.6
    }

    var gramsAlcohol: Double {
        oz * count * (abv / 100) * 29.5735 * 0.789
    }

    init(id: UUID = UUID(), name: String, oz: Double, abv: Double, count: Double = 1, date: String) {
        self.id = id; self.name = name; self.oz = oz; self.abv = abv; self.count = count; self.date = date
    }
}

struct AlcoholPreset: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var oz: Double
    var abv: Double

    init(id: UUID = UUID(), name: String, oz: Double, abv: Double) {
        self.id = id; self.name = name; self.oz = oz; self.abv = abv
    }

    static let defaults: [AlcoholPreset] = [
        AlcoholPreset(name: "Modelo Especial (12oz)", oz: 12, abv: 4.4),
        AlcoholPreset(name: "Nitro Guinness (14.9oz)", oz: 14.9, abv: 4.2),
        AlcoholPreset(name: "Old Fashioned (2oz)", oz: 2, abv: 40),
        AlcoholPreset(name: "Guinness 0 (14.9oz)", oz: 14.9, abv: 0.4),
        AlcoholPreset(name: "N/A Beer (12oz)", oz: 12, abv: 0.4),
    ]
}

struct NicotineEntry: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var product: String
    var mgPerUnit: Double
    var count: Int
    var date: String // "YYYY-MM-DD"

    var totalMg: Double { mgPerUnit * Double(count) }

    init(id: UUID = UUID(), product: String, mgPerUnit: Double, count: Int = 1, date: String) {
        self.id = id; self.product = product; self.mgPerUnit = mgPerUnit; self.count = count; self.date = date
    }
}

struct NicotinePreset: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var mgPerUnit: Double

    init(id: UUID = UUID(), name: String, mgPerUnit: Double) {
        self.id = id; self.name = name; self.mgPerUnit = mgPerUnit
    }

    /// Default quick-add presets seeded for new installs. Mirrors the
    /// `AlcoholPreset.defaults` / `SaunaPreset.defaults` pattern so that
    /// `AppData.empty` and fresh-start onboarding start with a useful list
    /// instead of an empty Nicotine tab.
    static let defaults: [NicotinePreset] = [
        NicotinePreset(name: "Stokes Pick 5mg", mgPerUnit: 5),
        NicotinePreset(name: "Zyn 6mg", mgPerUnit: 6),
        NicotinePreset(name: "Zyn 3mg", mgPerUnit: 3),
        NicotinePreset(name: "Lucy 4mg", mgPerUnit: 4),
    ]
}

// MARK: - Sauna

enum SaunaType: String, Codable, Sendable, CaseIterable, Equatable {
    case infrared = "Infrared"
    case steam = "Steam"

    var defaultTempF: Int {
        switch self {
        case .infrared: 140
        case .steam: 175
        }
    }

    var defaultMinutes: Int {
        switch self {
        case .infrared: 25
        case .steam: 15
        }
    }
}

struct SaunaSession: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var saunaType: SaunaType
    var temperatureF: Int
    var durationMinutes: Int
    var date: String // "YYYY-MM-DD"

    init(id: UUID = UUID(), saunaType: SaunaType, temperatureF: Int, durationMinutes: Int, date: String) {
        self.id = id; self.saunaType = saunaType; self.temperatureF = temperatureF
        self.durationMinutes = durationMinutes; self.date = date
    }
}

struct SaunaPreset: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var saunaType: SaunaType
    var temperatureF: Int
    var durationMinutes: Int

    init(id: UUID = UUID(), name: String, saunaType: SaunaType, temperatureF: Int, durationMinutes: Int) {
        self.id = id; self.name = name; self.saunaType = saunaType
        self.temperatureF = temperatureF; self.durationMinutes = durationMinutes
    }

    static let defaults: [SaunaPreset] = [
        SaunaPreset(name: "Infrared (140\u{00B0}F, 25 min)", saunaType: .infrared, temperatureF: 140, durationMinutes: 25),
        SaunaPreset(name: "Steam (175\u{00B0}F, 15 min)", saunaType: .steam, temperatureF: 175, durationMinutes: 15),
    ]
}
