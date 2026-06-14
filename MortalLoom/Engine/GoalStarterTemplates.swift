import Foundation

// MARK: - Goal Starter Templates

/// A ready-made starter goal the user can pick from when creating a new goal.
/// Templates exist so the non-health pillars (creative, financial,
/// relationship/family, legacy, mastery) feel as first-class as the
/// well-trodden health path: a user whose North Star is creative or
/// relational can start from a concrete, well-shaped goal instead of a blank
/// title field. See GOALS.md → "broaden out-of-the-box support for non-health
/// pillars".
///
/// Distinct from the genome-bridge `GoalTemplate` (Models/GenomeAction.swift),
/// which is a one-off prefill payload tied to a specific DNA finding. These
/// are a curated, category-organized library surfaced by the goal editor's
/// "Start from a template" picker.
struct StarterGoalTemplate: Sendable, Identifiable, Equatable {
    let title: String
    let notes: String
    let category: GoalCategory
    let horizon: GoalHorizon
    /// Suggested concrete steps. Prefilled as editable milestone rows so the
    /// user starts with a skeleton plan, not just a title.
    let milestones: [String]

    /// Stable identity from the unique title so SwiftUI lists/pickers can key
    /// on it. Titles are unique within `GoalStarterTemplates.all`.
    var id: String { title }
}

/// The curated starter-template library, organized by `GoalCategory`. Pure
/// data — no I/O, no side effects — so it's trivially testable and usable from
/// any view. Each non-health category carries several entries so the picker
/// has real depth for creative, financial, relationship, and legacy pillars.
enum GoalStarterTemplates {

    /// All templates for a category, in display order.
    static func templates(for category: GoalCategory) -> [StarterGoalTemplate] {
        all.filter { $0.category == category }
    }

    /// Every template, health first then the out-of-the-box pillars. This is
    /// the single source of truth — `templates(for:)` filters it. Authored in
    /// `GoalCategory.allCases` order so the grouped picker reads top-to-bottom.
    static let all: [StarterGoalTemplate] = [
        // Health
        StarterGoalTemplate(
            title: "Run a half-marathon",
            notes: "Build endurance with a structured plan that ends in a 13.1-mile race.",
            category: .health,
            horizon: .oneYear,
            milestones: ["Run 5K without stopping", "Complete a 10K race",
                         "Finish a 10-mile training run", "Race day: 13.1 miles"]
        ),
        StarterGoalTemplate(
            title: "Reach a healthy body composition",
            notes: "Set a sustainable target for weight and body-fat, reached through diet and strength training.",
            category: .health,
            horizon: .oneYear,
            milestones: ["Set a target weight and body-fat range",
                         "Establish a 3x/week strength routine",
                         "Hit the halfway mark", "Reach and hold the target for a month"]
        ),
        // Creative
        StarterGoalTemplate(
            title: "Write and publish a novel",
            notes: "Take a book from blank page to published — first draft, revision, and release.",
            category: .creative,
            horizon: .threeYear,
            milestones: ["Outline the story", "Finish the first draft",
                         "Complete a full revision", "Publish or query agents"]
        ),
        StarterGoalTemplate(
            title: "Release an album of original music",
            notes: "Write, record, and release a collection of your own songs.",
            category: .creative,
            horizon: .threeYear,
            milestones: ["Write 10 songs", "Demo every track",
                         "Record and mix the album", "Release it to the world"]
        ),
        StarterGoalTemplate(
            title: "Mount a solo art exhibition",
            notes: "Build a body of work and show it publicly.",
            category: .creative,
            horizon: .threeYear,
            milestones: ["Define the theme", "Complete 12 finished pieces",
                         "Secure a venue", "Open the show"]
        ),
        // Family / relationships
        StarterGoalTemplate(
            title: "Establish a weekly family ritual",
            notes: "A recurring time that's protected for the people closest to you — a shared meal, game night, or outing.",
            category: .family,
            horizon: .oneYear,
            milestones: ["Choose the ritual and day", "Hold it 4 weeks running",
                         "Keep it for a full season"]
        ),
        StarterGoalTemplate(
            title: "Plan a meaningful trip with loved ones",
            notes: "A trip built around connection, not just logistics.",
            category: .family,
            horizon: .oneYear,
            milestones: ["Agree on the destination and dates", "Book travel and lodging",
                         "Plan the shared experiences", "Take the trip"]
        ),
        StarterGoalTemplate(
            title: "Reconnect with someone who matters",
            notes: "Rebuild a relationship that has drifted — reach out, follow through, and stay in touch.",
            category: .family,
            horizon: .oneYear,
            milestones: ["Reach out", "Have a real conversation",
                         "Make a recurring plan to stay connected"]
        ),
        // Financial
        StarterGoalTemplate(
            title: "Build a 6-month emergency fund",
            notes: "Save enough liquid cash to cover six months of essential expenses.",
            category: .financial,
            horizon: .oneYear,
            milestones: ["Calculate monthly essentials", "Open a dedicated savings account",
                         "Reach 3 months saved", "Reach 6 months saved"]
        ),
        StarterGoalTemplate(
            title: "Save for a home down payment",
            notes: "Set a target down payment and save toward it on a timeline.",
            category: .financial,
            horizon: .threeYear,
            milestones: ["Set the target amount", "Automate monthly transfers",
                         "Reach the halfway mark", "Hit the full down payment"]
        ),
        StarterGoalTemplate(
            title: "Pay off high-interest debt",
            notes: "Clear the debt that's costing you the most, one balance at a time.",
            category: .financial,
            horizon: .oneYear,
            milestones: ["List all balances and rates", "Pick a payoff strategy",
                         "Clear the first balance", "Become debt-free"]
        ),
        // Legacy
        StarterGoalTemplate(
            title: "Record your life story",
            notes: "Capture the stories, lessons, and memories you want to outlast you — written, recorded, or filmed.",
            category: .legacy,
            horizon: .threeYear,
            milestones: ["Outline the chapters of your life",
                         "Record or write the early years",
                         "Cover the defining moments", "Share it with family"]
        ),
        StarterGoalTemplate(
            title: "Create something that outlives you",
            notes: "A lasting artifact — a book, a garden, a foundation, a body of work — that carries your values forward.",
            category: .legacy,
            horizon: .fiveYear,
            milestones: ["Decide what you want to leave behind",
                         "Make the first lasting contribution",
                         "Build it up over time", "Ensure it can continue without you"]
        ),
        StarterGoalTemplate(
            title: "Write letters for the future",
            notes: "Letters to the people you love, to be read at milestones you may not be there for.",
            category: .legacy,
            horizon: .oneYear,
            milestones: ["List who and which moments", "Write the first letters",
                         "Store them somewhere they'll be found"]
        ),
        // Mastery
        StarterGoalTemplate(
            title: "Reach fluency in a new language",
            notes: "Go from beginner to holding a real conversation.",
            category: .mastery,
            horizon: .threeYear,
            milestones: ["Learn the first 500 words", "Hold a basic conversation",
                         "Consume native media comfortably", "Converse fluently"]
        ),
        StarterGoalTemplate(
            title: "Develop deep expertise in your craft",
            notes: "Move from competent to genuinely expert through deliberate practice.",
            category: .mastery,
            horizon: .fiveYear,
            milestones: ["Map the skills that define mastery",
                         "Establish a deliberate-practice routine",
                         "Get expert feedback", "Teach or ship at an expert level"]
        ),
    ]
}
