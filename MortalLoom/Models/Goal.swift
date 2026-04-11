import Foundation
import SwiftUI

// MARK: - Goal

struct Goal: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String
    var notes: String
    var createdDate: String           // "YYYY-MM-DD"
    var targetDate: String?
    var completedDate: String?
    var checkIns: [GoalCheckIn]
    var milestones: [GoalMilestone]
    var checkInIntervalDays: Int
    var status: GoalStatus
    var priority: GoalPriority
    var parentId: UUID?
    var horizon: GoalHorizon?
    var category: GoalCategory?
    var goalType: GoalType?
    /// Stagnation signal titles the user has explicitly muted for this goal.
    /// StagnationEngine filters out any signal whose title is in this set so
    /// the user can silence a specific nag without disabling alerts entirely.
    var mutedSignals: [String]

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        createdDate: String = DateFormatting.todayString(),
        targetDate: String? = nil,
        completedDate: String? = nil,
        checkIns: [GoalCheckIn] = [],
        milestones: [GoalMilestone] = [],
        checkInIntervalDays: Int = 7,
        status: GoalStatus = .active,
        priority: GoalPriority = .medium,
        parentId: UUID? = nil,
        horizon: GoalHorizon? = nil,
        category: GoalCategory? = nil,
        goalType: GoalType? = nil,
        mutedSignals: [String] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdDate = createdDate
        self.targetDate = targetDate
        self.completedDate = completedDate
        self.checkIns = checkIns
        self.milestones = milestones
        self.checkInIntervalDays = checkInIntervalDays
        self.status = status
        self.priority = priority
        self.parentId = parentId
        self.horizon = horizon
        self.category = category
        self.goalType = goalType
        self.mutedSignals = mutedSignals
    }

    // Back-compat decoder so pre-existing files (without `mutedSignals`) decode.
    private enum CodingKeys: String, CodingKey {
        case id, title, notes, createdDate, targetDate, completedDate, checkIns
        case milestones, checkInIntervalDays, status, priority, parentId
        case horizon, category, goalType, mutedSignals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdDate = try c.decode(String.self, forKey: .createdDate)
        targetDate = try c.decodeIfPresent(String.self, forKey: .targetDate)
        completedDate = try c.decodeIfPresent(String.self, forKey: .completedDate)
        checkIns = try c.decodeIfPresent([GoalCheckIn].self, forKey: .checkIns) ?? []
        milestones = try c.decodeIfPresent([GoalMilestone].self, forKey: .milestones) ?? []
        checkInIntervalDays = try c.decodeIfPresent(Int.self, forKey: .checkInIntervalDays) ?? 7
        status = try c.decodeIfPresent(GoalStatus.self, forKey: .status) ?? .active
        priority = try c.decodeIfPresent(GoalPriority.self, forKey: .priority) ?? .medium
        parentId = try c.decodeIfPresent(UUID.self, forKey: .parentId)
        horizon = try c.decodeIfPresent(GoalHorizon.self, forKey: .horizon)
        category = try c.decodeIfPresent(GoalCategory.self, forKey: .category)
        goalType = try c.decodeIfPresent(GoalType.self, forKey: .goalType)
        mutedSignals = try c.decodeIfPresent([String].self, forKey: .mutedSignals) ?? []
    }

    var progressPercent: Double {
        checkIns.last?.progressPct ?? 0
    }

    var isOverdue: Bool {
        guard let target = targetDate,
              let targetD = DateFormatting.dateFromString(target),
              status == .active else { return false }
        return Date() > targetD
    }

    var daysSinceLastCheckIn: Int {
        DateFormatting.daysSince(checkIns.last?.date ?? createdDate)
    }

    var needsCheckIn: Bool {
        guard status == .active else { return false }
        return daysSinceLastCheckIn >= checkInIntervalDays
    }
}

// MARK: - Check-In

/// A goal check-in — unified model that carries both progress tracking (for
/// standard goals) and reflection content (for apex/sub-apex lifelong goals).
/// The rendering UI branches on goal type and on which fields are populated.
///
/// Standard goals: `progressPct` + `note` are the primary fields.
/// Lifelong goals (apex, sub-apex): `alignmentRating`, `blockers`, `commitments`,
/// and `promptAnswered` capture the reflection. `progressPct` is ignored for
/// lifelong goals since they have no completion percentage.
struct GoalCheckIn: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var date: String              // "YYYY-MM-DD"
    var progressPct: Double       // 0-100 (meaningful for standard goals only)
    var note: String

    // Reflection fields — optional, populated primarily on lifelong goals
    // but not restricted: a standard goal can also carry reflection context.
    var alignmentRating: Int?     // 1-10 self-rating
    var blockers: [String]        // "what's holding me back"
    var commitments: [String]     // "what I'll do this period"
    var promptAnswered: String?   // which guided prompt was answered

    init(
        id: UUID = UUID(),
        date: String = DateFormatting.todayString(),
        progressPct: Double = 0,
        note: String = "",
        alignmentRating: Int? = nil,
        blockers: [String] = [],
        commitments: [String] = [],
        promptAnswered: String? = nil
    ) {
        self.id = id
        self.date = date
        self.progressPct = min(100, max(0, progressPct))
        self.note = note
        self.alignmentRating = alignmentRating.map { min(10, max(1, $0)) }
        self.blockers = blockers
        self.commitments = commitments
        self.promptAnswered = promptAnswered
    }

    /// True when this check-in carries reflection content (alignment rating,
    /// blockers, commitments, or a prompt answer). Used to filter the
    /// Reflections page from progress-only check-ins.
    var isReflection: Bool {
        alignmentRating != nil
            || !blockers.isEmpty
            || !commitments.isEmpty
            || promptAnswered != nil
    }

    // Back-compat decoder: older files may lack the reflection fields.
    private enum CodingKeys: String, CodingKey {
        case id, date, progressPct, note
        case alignmentRating, blockers, commitments, promptAnswered
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        progressPct = try c.decodeIfPresent(Double.self, forKey: .progressPct) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        alignmentRating = try c.decodeIfPresent(Int.self, forKey: .alignmentRating)
        blockers = try c.decodeIfPresent([String].self, forKey: .blockers) ?? []
        commitments = try c.decodeIfPresent([String].self, forKey: .commitments) ?? []
        promptAnswered = try c.decodeIfPresent(String.self, forKey: .promptAnswered)
    }
}

// MARK: - Alignment Scale

/// The 1–10 alignment self-rating scale used across CheckInSheet,
/// WeeklyReviewSheet, Reflections, Pillar Dashboards, Onboarding, and the
/// Widget. Centralised so the labels and colours can't drift out of sync.
enum AlignmentScale {
    static func label(for rating: Int) -> String {
        switch rating {
        case ..<4: "Off track"
        case 4...5: "Drifting"
        case 6...7: "Mostly aligned"
        case 8...9: "On track"
        default:    "Deeply aligned"
        }
    }

    static func color(for rating: Int) -> Color {
        switch rating {
        case ..<4: .danger
        case 4...5: .warning
        case 6...7: .accentColor
        default:    .success
        }
    }

    /// Convert a 0–100 alignment *percentage* (Overview/Widget/Reports style)
    /// to the same 1–10 bucket so labels/colors are reused without duplication.
    static func label(forPercent percent: Double) -> String {
        label(for: Int((percent / 10).rounded()))
    }

    static func color(forPercent percent: Double) -> Color {
        color(for: Int((percent / 10).rounded()))
    }
}

// MARK: - Reflection Prompts

/// Curated reflection prompt library used by guided check-ins and stagnation
/// alerts. Rotates to avoid asking the same thing twice in a row.
enum ReflectionPrompts {
    /// Post-habit daily nudge — shared between the card copy in
    /// `HabitsSection.DailyNudgeCard` and the `GoalCheckIn.promptAnswered`
    /// field so the Reflections journal can attribute the entry correctly.
    static let dailyNudge = "Did today move toward your North Star?"

    static let general: [String] = [
        "What's holding you back right now?",
        "Which tasks or habits are preventing you from moving toward your North Star?",
        "What could you clear from your calendar this week to make room?",
        "What did you give time to last week that didn't serve your North Star?",
        "What's one small thing you could do today that would matter?",
        "Who or what is competing for your attention right now?",
        "If you had one extra hour today, where would it go — and is that the right answer?",
        "What's the most important thing you've done this week toward your goals?"
    ]

    static let monthly: [String] = [
        "Are these still the right goals?",
        "Which life pillar has had the most attention this month? Is that right?",
        "What would you retire from your goals if you could?",
        "What surprised you about your alignment this month?"
    ]

    static let stagnation: [String] = [
        "You haven't touched this in a while. What changed?",
        "Is this goal still alive for you, or is it time to let it go?",
        "What would make it easy to take one small step this week?",
        "What's the smallest version of this goal you could commit to?"
    ]

    /// Pick a prompt avoiding ones already answered recently. Deterministic
    /// given the same inputs so tests are stable.
    static func pick(from pool: [String] = ReflectionPrompts.general,
                     excludingRecent recent: Set<String> = []) -> String {
        let candidates = pool.filter { !recent.contains($0) }
        return candidates.first ?? pool.first ?? ""
    }

    /// Pick the next prompt for a goal, excluding any prompts the user has
    /// answered in their last 5 check-ins on that goal, plus an optional
    /// currently-displayed prompt (for the "rotate" button). Centralises the
    /// rotation pattern repeated across CheckInSheet and WeeklyReviewSheet.
    static func nextPrompt(
        for goal: Goal?,
        excluding current: String? = nil,
        pool: [String] = ReflectionPrompts.general
    ) -> String {
        var recent = Set((goal?.checkIns ?? []).suffix(5).compactMap { $0.promptAnswered })
        if let current { recent.insert(current) }
        return pick(from: pool, excludingRecent: recent)
    }
}

// MARK: - Milestone

struct GoalMilestone: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String
    var completed: Bool
    var completedDate: String?

    init(id: UUID = UUID(), title: String, completed: Bool = false, completedDate: String? = nil) {
        self.id = id
        self.title = title
        self.completed = completed
        self.completedDate = completedDate
    }
}

// MARK: - Enums

enum GoalStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active, paused, completed, abandoned
}

enum GoalPriority: String, Codable, Sendable, CaseIterable, Comparable {
    case high, medium, low

    static func < (lhs: GoalPriority, rhs: GoalPriority) -> Bool {
        let order: [GoalPriority] = [.high, .medium, .low]
        let lhsIdx = order.firstIndex(of: lhs) ?? 0
        let rhsIdx = order.firstIndex(of: rhs) ?? 0
        return lhsIdx < rhsIdx
    }
}

// MARK: - Goal Hierarchy Enums

enum GoalHorizon: String, Codable, Sendable, CaseIterable, Equatable {
    case oneYear = "1-year"
    case threeYear = "3-year"
    case fiveYear = "5-year"
    case tenYear = "10-year"
    case twentyYear = "20-year"
    case lifetime = "lifetime"

    var label: String {
        switch self {
        case .oneYear: "1 Year"
        case .threeYear: "3 Years"
        case .fiveYear: "5 Years"
        case .tenYear: "10 Years"
        case .twentyYear: "20 Years"
        case .lifetime: "Lifetime"
        }
    }
}

enum GoalCategory: String, Codable, Sendable, CaseIterable, Equatable {
    case health, creative, family, financial, legacy, mastery

    var label: String {
        switch self {
        case .health: "Health"
        case .creative: "Creative"
        case .family: "Family"
        case .financial: "Financial"
        case .legacy: "Legacy"
        case .mastery: "Mastery"
        }
    }

    var icon: String {
        switch self {
        case .health: "heart.fill"
        case .creative: "lightbulb.fill"
        case .family: "person.2.fill"
        case .financial: "dollarsign.circle.fill"
        case .legacy: "flame.fill"
        case .mastery: "target"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .health: .green
        case .creative: .purple
        case .family: .pink
        case .financial: .yellow
        case .legacy: .orange
        case .mastery: .blue
        }
    }
}

enum GoalType: String, Codable, Sendable, CaseIterable, Equatable {
    case apex, subApex, standard

    var label: String {
        switch self {
        case .apex: "North Star"
        case .subApex: "Life Pillar"
        case .standard: "Goal"
        }
    }

    var icon: String {
        switch self {
        case .apex: "crown.fill"
        case .subApex: "star.fill"
        case .standard: "circle.fill"
        }
    }
}

// MARK: - Collection Helpers

extension Array where Element == Goal {
    /// The user's active North Star goal, if set.
    var activeApex: Goal? {
        first { $0.goalType == .apex && $0.status == .active }
    }

    var activeCount: Int {
        filter { $0.status == .active }.count
    }

    /// Precomputes the effective "latest check-in date" for every active
    /// goal in one pass. Parent goals inherit the newest check-in across
    /// their subtree so callers can suppress overdue nags when sub-goals
    /// are being worked on. Lexicographic string max is safe because the
    /// format is fixed-width ISO "yyyy-MM-dd".
    ///
    /// Result maps goalId → latest date string (own or any active descendant).
    /// Goals with no check-ins in their subtree fall back to `createdDate`.
    func effectiveLatestCheckInDates() -> [UUID: String] {
        var childrenByParent: [UUID: [Goal]] = [:]
        for g in self where g.status == .active {
            guard let pid = g.parentId else { continue }
            childrenByParent[pid, default: []].append(g)
        }
        var result: [UUID: String] = [:]
        func walk(_ goal: Goal) -> String {
            if let cached = result[goal.id] { return cached }
            var latest = goal.checkIns.last?.date ?? goal.createdDate
            for child in childrenByParent[goal.id] ?? [] {
                let childLatest = walk(child)
                if childLatest > latest { latest = childLatest }
            }
            result[goal.id] = latest
            return latest
        }
        for g in self where g.status == .active {
            _ = walk(g)
        }
        return result
    }

    /// One-off convenience; loops should call `effectiveLatestCheckInDates`
    /// once and reuse the map instead of paying O(n) per goal.
    func effectiveDaysSinceLastCheckIn(for goal: Goal) -> Int {
        let latest = effectiveLatestCheckInDates()
        return DateFormatting.daysSince(latest[goal.id] ?? goal.createdDate)
    }

    /// One-off convenience — see `effectiveDaysSinceLastCheckIn(for:)`.
    func effectiveNeedsCheckIn(for goal: Goal) -> Bool {
        guard goal.status == .active else { return false }
        return effectiveDaysSinceLastCheckIn(for: goal) >= goal.checkInIntervalDays
    }
}
