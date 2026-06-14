import XCTest
@testable import MortalLoom

// MARK: - Goal Starter Templates Tests
//
// Pure-data tests for the curated starter-template library that gives every
// pillar — not just health — a first-class on-ramp in the goal editor.

final class GoalStarterTemplatesTests: XCTestCase {

    /// Every category must carry at least one starter so the picker never
    /// shows an empty pillar — this is the whole point of the feature.
    func testEveryCategoryHasTemplates() {
        for category in GoalCategory.allCases {
            XCTAssertFalse(
                GoalStarterTemplates.templates(for: category).isEmpty,
                "\(category) has no starter templates"
            )
        }
    }

    /// The non-health pillars are the reason the feature exists; assert they
    /// each carry real depth (more than a single token entry).
    func testNonHealthPillarsHaveDepth() {
        for category: GoalCategory in [.creative, .financial, .family, .legacy] {
            XCTAssertGreaterThanOrEqual(
                GoalStarterTemplates.templates(for: category).count, 2,
                "\(category) should offer multiple starting points"
            )
        }
    }

    /// `all` is the flattened library; it must equal the per-category union
    /// and preserve `GoalCategory.allCases` ordering (health first).
    func testAllFlattensEveryCategoryInOrder() {
        let expected = GoalCategory.allCases.flatMap { GoalStarterTemplates.templates(for: $0) }
        XCTAssertEqual(GoalStarterTemplates.all, expected)
        XCTAssertEqual(GoalStarterTemplates.all.first?.category, GoalCategory.allCases.first)
    }

    /// Titles double as `Identifiable.id`, so a collision would break the
    /// picker's `ForEach`. Assert global uniqueness.
    func testTitlesAreGloballyUnique() {
        let titles = GoalStarterTemplates.all.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "duplicate template titles")
    }

    /// Each template's stored category must match the bucket it lives in, and
    /// content must be non-empty so the prefill is actually useful.
    func testTemplateContentIsWellFormed() {
        for category in GoalCategory.allCases {
            for template in GoalStarterTemplates.templates(for: category) {
                XCTAssertEqual(template.category, category,
                               "\(template.title) filed under the wrong category")
                XCTAssertFalse(template.title.isEmpty)
                XCTAssertFalse(template.notes.isEmpty)
                XCTAssertFalse(template.milestones.isEmpty,
                               "\(template.title) has no starter milestones")
                XCTAssertFalse(template.milestones.contains(where: \.isEmpty),
                               "\(template.title) has a blank milestone")
            }
        }
    }
}
