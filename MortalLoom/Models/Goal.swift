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
        goalType: GoalType? = nil
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
        guard let lastDate = checkIns.last?.date ?? Optional(createdDate),
              let last = DateFormatting.dateFromString(lastDate) else { return 0 }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
    }

    var needsCheckIn: Bool {
        guard status == .active else { return false }
        return daysSinceLastCheckIn >= checkInIntervalDays
    }
}

// MARK: - Check-In

struct GoalCheckIn: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var date: String              // "YYYY-MM-DD"
    var progressPct: Double       // 0-100
    var note: String

    init(id: UUID = UUID(), date: String = DateFormatting.todayString(), progressPct: Double, note: String = "") {
        self.id = id
        self.date = date
        self.progressPct = min(100, max(0, progressPct))
        self.note = note
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
