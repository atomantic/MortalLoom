import Foundation
import SwiftUI

// MARK: - Habit

/// A tracked habit — health-oriented (build sleep, avoid alcohol) or goal-oriented
/// (write daily, practice music, meditate). Habits optionally link to a parent
/// goal or life pillar so their streak health contributes to alignment rollups.
///
/// Streaks are derived from the `completions` array at read time; there is no
/// cached streak state to fall out of sync with reality.
struct Habit: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var detail: String             // "description" avoids the Swift keyword
    var icon: String               // SF Symbol name
    var colorHex: String           // hex string so Codable stays simple
    var category: HabitCategory
    var kind: HabitKind
    var cadence: HabitCadence
    var parentGoalId: UUID?        // optional link to a Goal (any type) for rollup
    var createdDate: String        // "YYYY-MM-DD"
    var archivedDate: String?      // nil while active
    var completions: [HabitCompletion]
    /// Provenance when the habit was created from a genome finding.
    /// Drives the "🧬 Suggested by your DNA" banner on habit detail views.
    var geneticEvidence: GeneticEvidence?

    init(
        id: UUID = UUID(),
        name: String,
        detail: String = "",
        icon: String = "checkmark.circle",
        colorHex: String = "#4C8BF5",
        category: HabitCategory = .general,
        kind: HabitKind = .positive,
        cadence: HabitCadence = HabitCadence(period: .daily, target: 1),
        parentGoalId: UUID? = nil,
        createdDate: String = DateFormatting.todayString(),
        archivedDate: String? = nil,
        completions: [HabitCompletion] = [],
        geneticEvidence: GeneticEvidence? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.icon = icon
        self.colorHex = colorHex
        self.category = category
        self.kind = kind
        self.cadence = cadence
        self.parentGoalId = parentGoalId
        self.createdDate = createdDate
        self.archivedDate = archivedDate
        self.completions = completions
        self.geneticEvidence = geneticEvidence
    }

    var isActive: Bool { archivedDate == nil }

    /// Hex colour resolved to a SwiftUI Color, with a safe fallback.
    var color: Color { Color(hex: colorHex) ?? .accentColor }

    // Back-compat decoder so pre-existing files (without `geneticEvidence`) decode.
    private enum CodingKeys: String, CodingKey {
        case id, name, detail, icon, colorHex, category, kind, cadence
        case parentGoalId, createdDate, archivedDate, completions, geneticEvidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "checkmark.circle"
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#4C8BF5"
        category = try c.decodeIfPresent(HabitCategory.self, forKey: .category) ?? .general
        kind = try c.decodeIfPresent(HabitKind.self, forKey: .kind) ?? .positive
        cadence = try c.decodeIfPresent(HabitCadence.self, forKey: .cadence) ?? HabitCadence(period: .daily, target: 1)
        parentGoalId = try c.decodeIfPresent(UUID.self, forKey: .parentGoalId)
        createdDate = try c.decode(String.self, forKey: .createdDate)
        archivedDate = try c.decodeIfPresent(String.self, forKey: .archivedDate)
        completions = try c.decodeIfPresent([HabitCompletion].self, forKey: .completions) ?? []
        geneticEvidence = try c.decodeIfPresent(GeneticEvidence.self, forKey: .geneticEvidence)
    }
}

// MARK: - HabitCompletion

struct HabitCompletion: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var date: String               // "YYYY-MM-DD"
    var count: Int                 // 1 for a simple check, or quantified (e.g. "3 cups water")
    var note: String

    init(
        id: UUID = UUID(),
        date: String = DateFormatting.todayString(),
        count: Int = 1,
        note: String = ""
    ) {
        self.id = id
        self.date = date
        self.count = max(1, count)
        self.note = note
    }
}

// MARK: - HabitCategory

enum HabitCategory: String, Codable, Sendable, CaseIterable, Equatable {
    case health        // sleep, hydration, substance-avoidance
    case wellness      // meditation, breathing, journaling
    case creative      // writing, music, art
    case mastery       // skill practice, study
    case family        // family time, relational rituals
    case financial     // saving, budget review
    case legacy        // long-term impact work
    case general

    var label: String {
        switch self {
        case .health: "Health"
        case .wellness: "Wellness"
        case .creative: "Creative"
        case .mastery: "Mastery"
        case .family: "Family"
        case .financial: "Financial"
        case .legacy: "Legacy"
        case .general: "General"
        }
    }

    var icon: String {
        switch self {
        case .health: "heart.fill"
        case .wellness: "leaf.fill"
        case .creative: "lightbulb.fill"
        case .mastery: "target"
        case .family: "person.2.fill"
        case .financial: "dollarsign.circle.fill"
        case .legacy: "flame.fill"
        case .general: "circle.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .health: .green
        case .wellness: .mint
        case .creative: .purple
        case .mastery: .blue
        case .family: .pink
        case .financial: .yellow
        case .legacy: .orange
        case .general: .gray
        }
    }
}

// MARK: - HabitKind

/// Positive habits are things you want to build (meditate daily).
/// Negative habits are things you want to break (no screens after 10pm).
/// Negative habits use the same data model — a "completion" means a successful
/// day/period where you avoided the behaviour.
enum HabitKind: String, Codable, Sendable, CaseIterable, Equatable {
    case positive
    case negative

    var label: String {
        switch self {
        case .positive: "Build"
        case .negative: "Break"
        }
    }

    var icon: String {
        switch self {
        case .positive: "plus.circle.fill"
        case .negative: "minus.circle.fill"
        }
    }
}

// MARK: - HabitCadence

/// A habit's cadence combines a period (daily or weekly) with a target count.
/// A once-daily habit is `HabitCadence(period: .daily, target: 1)`.
/// A "three times a week" habit is `HabitCadence(period: .weekly, target: 3)`.
/// "Drink 3 litres of water a day" is `HabitCadence(period: .daily, target: 3)`.
struct HabitCadence: Codable, Sendable, Equatable {
    var period: HabitCadencePeriod
    var target: Int

    init(period: HabitCadencePeriod = .daily, target: Int = 1) {
        self.period = period
        self.target = max(1, target)
    }

    var label: String {
        switch period {
        case .daily:
            return target == 1 ? "Every day" : "\(target)× per day"
        case .weekly:
            return target == 1 ? "Once a week" : "\(target)× per week"
        }
    }
}

enum HabitCadencePeriod: String, Codable, Sendable, CaseIterable, Equatable {
    case daily
    case weekly
}

// MARK: - Color hex init

extension Color {
    /// Lightweight hex → SwiftUI Color converter. Returns nil on parse failure.
    /// Supports 6-character `#RRGGBB` and 8-character `#RRGGBBAA` forms.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&value) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xff) / 255.0
            g = Double((value >> 8) & 0xff) / 255.0
            b = Double(value & 0xff) / 255.0
            a = 1.0
        } else {
            r = Double((value >> 24) & 0xff) / 255.0
            g = Double((value >> 16) & 0xff) / 255.0
            b = Double((value >> 8) & 0xff) / 255.0
            a = Double(value & 0xff) / 255.0
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Collection Helpers

extension Array where Element == Habit {
    var active: [Habit] { filter { $0.isActive } }

    /// Active habits linked to a given goal (by parentGoalId).
    func linkedTo(goalId: UUID) -> [Habit] {
        filter { $0.isActive && $0.parentGoalId == goalId }
    }
}
