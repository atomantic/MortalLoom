import Foundation

// MARK: - Genome Action

/// A specific actionable suggestion attached to a curated marker, ClinVar hit,
/// or APOE haplotype. Curated declaratively in `Engine/GenomeActionLibrary.swift`.
///
/// The `bridge` is the optional link from the action into the rest of the app —
/// tapping the action's primary CTA in the detail sheet routes through the bridge
/// (open the Add Habit sheet prefilled, jump to the Blood section, etc.).
struct GenomeAction: Sendable, Identifiable {
    let id: String
    let kind: GenomeActionKind
    let title: String
    let detail: String
    let urgency: GenomeActionUrgency
    let conditions: [GenomeActionCondition]
    let bridge: GenomeActionBridge?
    let citationIds: [String]
    let doctorTalkingPoint: String?
}

enum GenomeActionKind: String, Sendable, Codable {
    case bloodTest
    case screening
    case habit
    case lifestyle
    case supplement
    case doctorConsult
    case partnerScreen
    case research

    var label: String {
        switch self {
        case .bloodTest: "Blood test"
        case .screening: "Screening"
        case .habit: "Habit"
        case .lifestyle: "Lifestyle"
        case .supplement: "Supplement"
        case .doctorConsult: "Doctor consult"
        case .partnerScreen: "Partner screening"
        case .research: "Research"
        }
    }

    var icon: String {
        switch self {
        case .bloodTest: "drop.fill"
        case .screening: "stethoscope"
        case .habit: "checkmark.circle"
        case .lifestyle: "figure.walk"
        case .supplement: "pills.fill"
        case .doctorConsult: "person.crop.circle.badge.questionmark"
        case .partnerScreen: "person.2.fill"
        case .research: "book.fill"
        }
    }
}

enum GenomeActionUrgency: String, Sendable, Codable {
    case routine
    case soon
    case prompt

    var label: String {
        switch self {
        case .routine: "Routine"
        case .soon: "Soon"
        case .prompt: "Prompt"
        }
    }
}

/// Predicate that gates when a `GenomeAction` is surfaced for a given finding.
/// `genotypes == nil` means "any non-typical status for this rsid". Otherwise
/// the user's normalized genotype must appear in the list. `minStatus` lets a
/// concern-level action surface for both `.concern` and `.majorConcern`.
struct GenomeActionCondition: Sendable {
    let rsid: String
    let genotypes: [String]?
    let minStatus: GenomeMarkerStatus?

    init(rsid: String, genotypes: [String]? = nil, minStatus: GenomeMarkerStatus? = nil) {
        self.rsid = rsid
        self.genotypes = genotypes
        self.minStatus = minStatus
    }
}

/// How the action's primary CTA routes the user. The view layer interprets the
/// bridge — see `GenomeDetailSheet`.
enum GenomeActionBridge: Sendable {
    case habitTemplate(HabitTemplate)
    case goalTemplate(GoalTemplate)
    case bloodMarkerKey(String)
    case lifestyleField(LifestyleField)
    case external(URL)
}

/// Prefill payload for the existing AddHabit flow when accepting a genome action.
struct HabitTemplate: Sendable {
    let title: String
    let detail: String
    let icon: String
    let category: HabitCategory
    let kind: HabitKind
    let cadence: HabitCadence
}

/// Prefill payload for the existing AddGoal flow when accepting a genome action.
struct GoalTemplate: Sendable {
    let title: String
    let notes: String
    let category: GoalCategory
    let horizon: GoalHorizon
}

/// Lifestyle data field reference for actions that ask the user to change one
/// specific lifestyle input. The Lifestyle view scrolls to the matching row.
enum LifestyleField: String, Sendable {
    case smokingStatus
    case exerciseMinutesPerWeek
    case sleepHoursPerNight
    case dietQuality
    case stressLevel
    case alcoholDrinksPerWeek
}

// MARK: - Action State

/// Per-user, per-action persistent state. Keyed by `"<rsid>:<actionId>"` in
/// `AppData.genomeActionStates`.
struct GenomeActionState: Sendable, Codable, Equatable {
    let key: String
    var status: GenomeActionStatus
    var updatedAt: String
    var note: String?
    var linkedGoalId: UUID?
    var linkedHabitId: UUID?
    var linkedVisitNoteId: UUID?

    init(
        key: String,
        status: GenomeActionStatus = .pending,
        updatedAt: String = DateFormatting.todayString(),
        note: String? = nil,
        linkedGoalId: UUID? = nil,
        linkedHabitId: UUID? = nil,
        linkedVisitNoteId: UUID? = nil
    ) {
        self.key = key
        self.status = status
        self.updatedAt = updatedAt
        self.note = note
        self.linkedGoalId = linkedGoalId
        self.linkedHabitId = linkedHabitId
        self.linkedVisitNoteId = linkedVisitNoteId
    }

    /// Compose the storage key used in `AppData.genomeActionStates`.
    static func key(rsid: String, actionId: String) -> String {
        "\(rsid):\(actionId)"
    }

    /// Is this state effectively "done with this for now" (excluded from the
    /// pending priorities flow)? `discussed` and `done` count; `inProgress`
    /// does not (still surfaces with lower freshness so user can come back).
    var isResolved: Bool {
        status == .discussed || status == .done
    }
}

enum GenomeActionStatus: String, Sendable, Codable, Equatable {
    case pending
    case inProgress = "in_progress"
    case discussed
    case done
    case snoozed
    case dismissed
}

// MARK: - Genetic Evidence (provenance on Habits/Goals)

/// Marks a Habit or Goal as having been suggested by a genome finding. Renders
/// as a "🧬 Suggested by your DNA" banner on the habit/goal detail view.
struct GeneticEvidence: Sendable, Codable, Equatable {
    let rsid: String
    let gene: String
    let reason: String
    let actionId: String
}
