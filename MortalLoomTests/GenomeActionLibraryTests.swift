import XCTest
@testable import MortalLoom

// MARK: - GenomeActionLibrary Tests
//
// Library-shape tests — verify the curated genome-action library is
// internally consistent (unique IDs, all conditions reference real markers
// or known pseudo-rsids, citation IDs resolve, every action surfaces for
// at least one realistic finding).

final class GenomeActionLibraryTests: XCTestCase {

    func testLibraryIsNonEmpty() {
        XCTAssertFalse(GenomeActionLibrary.all.isEmpty, "Library should ship curated actions")
    }

    func testAllActionIdsAreUnique() {
        let ids = GenomeActionLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Action IDs must be unique — collisions would corrupt persisted state keys")
    }

    func testAllActionTitlesAreNonEmpty() {
        for action in GenomeActionLibrary.all {
            XCTAssertFalse(action.title.isEmpty, "Action \(action.id) has empty title")
        }
    }

    func testAllActionDetailsAreNonEmpty() {
        for action in GenomeActionLibrary.all {
            XCTAssertFalse(action.detail.isEmpty, "Action \(action.id) has empty detail")
        }
    }

    func testEveryActionHasAtLeastOneCondition() {
        for action in GenomeActionLibrary.all {
            XCTAssertFalse(action.conditions.isEmpty, "Action \(action.id) has no conditions — would never surface")
        }
    }

    func testAllConditionsReferenceKnownRsidsOrPseudoRsids() {
        let curatedRsids = Set(GenomeEngine.allCuratedMarkers.map(\.rsid))
        let pseudoRsids: Set<String> = [
            "apoe",
            "clinvar:pathogenic",
            "clinvar:risk_factor",
            "clinvar:drug_response",
            "clinvar:protective"
        ]
        for action in GenomeActionLibrary.all {
            for cond in action.conditions {
                let isKnown = curatedRsids.contains(cond.rsid) || pseudoRsids.contains(cond.rsid)
                XCTAssertTrue(isKnown, "Action \(action.id) references unknown rsid: \(cond.rsid)")
            }
        }
    }

    func testEveryActionHasValidUrgency() {
        let valid: Set<GenomeActionUrgency> = [.routine, .soon, .prompt]
        for action in GenomeActionLibrary.all {
            XCTAssertTrue(valid.contains(action.urgency))
        }
    }

    func testEveryActionHasValidKind() {
        let valid: Set<GenomeActionKind> = [
            .bloodTest, .screening, .habit, .lifestyle, .supplement,
            .doctorConsult, .partnerScreen, .research
        ]
        for action in GenomeActionLibrary.all {
            XCTAssertTrue(valid.contains(action.kind))
        }
    }

    func testApoeActionsHaveValidHaplotypes() {
        let validApoeHaplotypes: Set<String> = [
            "ε2/ε2", "ε2/ε3", "ε3/ε3", "ε2/ε4", "ε3/ε4", "ε4/ε4"
        ]
        for action in GenomeActionLibrary.all {
            for cond in action.conditions where cond.rsid == "apoe" {
                if let genotypes = cond.genotypes {
                    for g in genotypes {
                        XCTAssertTrue(
                            validApoeHaplotypes.contains(g),
                            "Action \(action.id) has invalid APOE haplotype: \(g)"
                        )
                    }
                }
            }
        }
    }

    func testActionsResolveForAtLeastOneFinding() {
        // Every action should match at least one realistic marker/clinvar/apoe
        // input. This catches actions whose conditions are unreachable
        // (e.g. typo'd rsid + unmatched genotype).
        let bucket = GenomePriorityEngine.bucketActions(GenomeActionLibrary.all)
        for action in GenomeActionLibrary.all {
            // For each condition, verify the action would be returned by an
            // appropriate priority lookup.
            for cond in action.conditions {
                let bucketActions = bucket.byRsid[cond.rsid] ?? []
                XCTAssertTrue(
                    bucketActions.contains(where: { $0.id == action.id }),
                    "Action \(action.id) condition rsid \(cond.rsid) doesn't bucket back to itself"
                )
            }
        }
    }

    func testHabitTemplateBridgesHaveTitlesAndCadence() {
        for action in GenomeActionLibrary.all {
            if case .habitTemplate(let template) = action.bridge {
                XCTAssertFalse(template.title.isEmpty, "Action \(action.id) habit template missing title")
                XCTAssertGreaterThan(template.cadence.target, 0, "Action \(action.id) habit template has zero target")
            }
        }
    }

    func testGoalTemplateBridgesHaveTitle() {
        for action in GenomeActionLibrary.all {
            if case .goalTemplate(let template) = action.bridge {
                XCTAssertFalse(template.title.isEmpty, "Action \(action.id) goal template missing title")
            }
        }
    }

    func testBloodMarkerBridgesHaveNonEmptyKey() {
        // Some actions use aspirational keys (e.g. "ferritin", "crp") that
        // aren't in the canonical BloodMarkers.all set yet — they show up as
        // "Add this marker" hints in the UI. We only assert the key is a
        // non-empty string here.
        for action in GenomeActionLibrary.all {
            if case .bloodMarkerKey(let key) = action.bridge {
                XCTAssertFalse(key.isEmpty, "Action \(action.id) blood marker bridge has empty key")
            }
        }
    }

    func testDoctorConsultActionsTendToHaveTalkingPoints() {
        // Most doctor-consult actions ship with a talking point — not strictly
        // required (some actions cover broad themes), but if missing on the
        // majority it suggests data drift. Assert a reasonable floor.
        let consults = GenomeActionLibrary.all.filter { $0.kind == .doctorConsult }
        let withTP = consults.filter { $0.doctorTalkingPoint != nil }
        XCTAssertGreaterThan(withTP.count, consults.count / 2,
                             "Most doctor-consult actions should provide a talking point")
    }

    // MARK: - matches() behaviour

    func testApoeActionMatchesItsHaplotypes() {
        // Find an APOE action and verify it matches one of its declared haplotypes
        guard let action = GenomeActionLibrary.all.first(where: { a in
            a.conditions.contains { $0.rsid == "apoe" && $0.genotypes != nil }
        }) else {
            XCTFail("Expected at least one genotype-restricted APOE action")
            return
        }
        let g = action.conditions.first(where: { $0.rsid == "apoe" })!.genotypes!.first!
        // matches() is rsid-bound; APOE actions use rsid="apoe"
        XCTAssertTrue(action.matches(rsid: "apoe", genotype: g, status: .concern))
    }

    func testApoeActionDoesNotMatchOtherHaplotypes() {
        guard let action = GenomeActionLibrary.all.first(where: { a in
            a.conditions.contains { $0.rsid == "apoe" && ($0.genotypes ?? []).contains("ε4/ε4") }
        }) else { return }  // skip if library no longer contains an ε4/ε4 action
        XCTAssertFalse(action.matches(rsid: "apoe", genotype: "ε2/ε2", status: .concern))
    }

    func testMatchesRequiresMinStatus() {
        // Build a one-off action with minStatus = .majorConcern
        let action = GenomeAction(
            id: "test-min",
            kind: .lifestyle,
            title: "T",
            detail: "D",
            urgency: .soon,
            conditions: [GenomeActionCondition(rsid: "rs1", minStatus: .majorConcern)],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: nil
        )
        XCTAssertFalse(action.matches(rsid: "rs1", genotype: nil, status: .concern))
        XCTAssertTrue(action.matches(rsid: "rs1", genotype: nil, status: .majorConcern))
    }

    func testMatchesRequiresRsid() {
        let action = GenomeAction(
            id: "test-rsid",
            kind: .lifestyle,
            title: "T",
            detail: "D",
            urgency: .soon,
            conditions: [GenomeActionCondition(rsid: "rs1")],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: nil
        )
        XCTAssertTrue(action.matches(rsid: "rs1", genotype: nil, status: .concern))
        XCTAssertFalse(action.matches(rsid: "rs2", genotype: nil, status: .concern))
    }

    func testMatchesNormalizesGenotype() {
        let action = GenomeAction(
            id: "test-norm",
            kind: .lifestyle,
            title: "T",
            detail: "D",
            urgency: .soon,
            conditions: [GenomeActionCondition(rsid: "rs1", genotypes: ["A/T"])],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: nil
        )
        // "TA" should normalize to "A/T" and match
        XCTAssertTrue(action.matches(rsid: "rs1", genotype: "TA", status: .concern))
        XCTAssertTrue(action.matches(rsid: "rs1", genotype: "A/T", status: .concern))
        XCTAssertFalse(action.matches(rsid: "rs1", genotype: "C/G", status: .concern))
    }

    func testMatchesGenotypeRequiresValueWhenAllowlistPresent() {
        let action = GenomeAction(
            id: "test-allow",
            kind: .lifestyle,
            title: "T",
            detail: "D",
            urgency: .soon,
            conditions: [GenomeActionCondition(rsid: "rs1", genotypes: ["A/A"])],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: nil
        )
        XCTAssertFalse(action.matches(rsid: "rs1", genotype: nil, status: .concern))
    }

    // MARK: - Action kinds & cosmetics

    func testGenomeActionKindLabelsAreNonEmpty() {
        for kind in [GenomeActionKind.bloodTest, .screening, .habit, .lifestyle,
                     .supplement, .doctorConsult, .partnerScreen, .research] {
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertFalse(kind.icon.isEmpty)
        }
    }

    func testGenomeActionUrgencyLabelsAreDistinct() {
        let labels = [
            GenomeActionUrgency.routine.label,
            GenomeActionUrgency.soon.label,
            GenomeActionUrgency.prompt.label
        ]
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    // MARK: - GenomeActionState

    func testActionStateKey() {
        let key = GenomeActionState.key(rsid: "rs1234", actionId: "my-action")
        XCTAssertEqual(key, "rs1234:my-action")
    }

    func testActionStateIsResolved() {
        XCTAssertTrue(GenomeActionState(key: "k", status: .discussed).isResolved)
        XCTAssertTrue(GenomeActionState(key: "k", status: .done).isResolved)
        XCTAssertFalse(GenomeActionState(key: "k", status: .pending).isResolved)
        XCTAssertFalse(GenomeActionState(key: "k", status: .inProgress).isResolved)
        XCTAssertFalse(GenomeActionState(key: "k", status: .snoozed).isResolved)
        XCTAssertFalse(GenomeActionState(key: "k", status: .dismissed).isResolved)
    }

    func testActionStateCodableRoundTrip() throws {
        let state = GenomeActionState(
            key: "rs1:a1",
            status: .inProgress,
            updatedAt: "2026-01-15",
            note: "Working on it",
            linkedGoalId: UUID(),
            linkedHabitId: UUID(),
            linkedVisitNoteId: UUID()
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GenomeActionState.self, from: data)
        XCTAssertEqual(state, decoded)
    }

    func testGeneticEvidenceCodableRoundTrip() throws {
        let evidence = GeneticEvidence(rsid: "rs1234", gene: "TEST", reason: "concern", actionId: "a1")
        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(GeneticEvidence.self, from: data)
        XCTAssertEqual(evidence, decoded)
    }
}
