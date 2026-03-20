import Foundation

struct AlcoholDrink: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var oz: Double
    var abv: Double
    var count: Int
    var date: String // "YYYY-MM-DD"

    var standardDrinks: Double {
        (oz * Double(count) * (abv / 100)) / 0.6
    }

    var gramsAlcohol: Double {
        oz * Double(count) * (abv / 100) * 29.5735 * 0.789
    }

    init(id: UUID = UUID(), name: String, oz: Double, abv: Double, count: Int = 1, date: String) {
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
}
