import Foundation

// MARK: - NIAAA Risk Level

enum NIAAARiskLevel: String, Sendable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
}

// MARK: - SubstanceEngine

enum SubstanceEngine {

    // MARK: - Alcohol

    static func rollingAverageGrams(drinks: [AlcoholDrink], days: Int, now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now)
        let total = drinks.filter { $0.date >= cutoff }.reduce(0.0) { $0 + $1.gramsAlcohol }
        return total / Double(max(1, days))
    }

    static func weeklyTotalStandardDrinks(drinks: [AlcoholDrink], now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now)
        return drinks.filter { $0.date >= cutoff }.reduce(0.0) { $0 + $1.standardDrinks }
    }

    static func allTimeAverageGrams(drinks: [AlcoholDrink], now: Date = Date()) -> Double {
        guard !drinks.isEmpty else { return 0 }
        guard let earliest = drinks.map(\.date).min(),
              let firstDate = DateFormatting.dateFromString(earliest) else { return 0 }
        let dayCount = max(1, Calendar.current.dateComponents([.day], from: firstDate, to: now).day ?? 1)
        let total = drinks.reduce(0.0) { $0 + $1.gramsAlcohol }
        return total / Double(dayCount)
    }

    static func dailyMaxStandardDrinks(drinks: [AlcoholDrink], days: Int, now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now)
        let recent = drinks.filter { $0.date >= cutoff }
        let grouped = Dictionary(grouping: recent, by: \.date)
        return grouped.values.map { dayDrinks in
            dayDrinks.reduce(0.0) { $0 + $1.standardDrinks }
        }.max() ?? 0
    }

    static func niaaaRiskLevel(drinks: [AlcoholDrink], sex: BiologicalSex?, now: Date = Date()) -> NIAAARiskLevel {
        let weeklyStd = weeklyTotalStandardDrinks(drinks: drinks, now: now)
        let dailyMax = dailyMaxStandardDrinks(drinks: drinks, days: 7, now: now)

        let isFemale = sex == .female
        let dailyThreshold: Double = isFemale ? 1.0 : 2.0
        let weeklyThreshold: Double = isFemale ? 7.0 : 14.0

        if weeklyStd > weeklyThreshold || dailyMax > (dailyThreshold * 2) {
            return .high
        } else if weeklyStd > weeklyThreshold * 0.7 || dailyMax > dailyThreshold {
            return .moderate
        }
        return .low
    }

    // MARK: - Nicotine

    static func rollingAverageMg(entries: [NicotineEntry], days: Int, now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now)
        let total = entries.filter { $0.date >= cutoff }.reduce(0.0) { $0 + $1.totalMg }
        return total / Double(max(1, days))
    }

    static func weeklyTotalMg(entries: [NicotineEntry], now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now)
        return entries.filter { $0.date >= cutoff }.reduce(0.0) { $0 + $1.totalMg }
    }

    static func allTimeAverageMg(entries: [NicotineEntry], now: Date = Date()) -> Double {
        guard !entries.isEmpty else { return 0 }
        guard let earliest = entries.map(\.date).min(),
              let firstDate = DateFormatting.dateFromString(earliest) else { return 0 }
        let dayCount = max(1, Calendar.current.dateComponents([.day], from: firstDate, to: now).day ?? 1)
        let total = entries.reduce(0.0) { $0 + $1.totalMg }
        return total / Double(dayCount)
    }
}
