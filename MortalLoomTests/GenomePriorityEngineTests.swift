import XCTest
@testable import MortalLoom

// MARK: - GenomePriorityEngine Tests
//
// Tests the pure-function priority ranker: severity/confidence/actionability/
// lifestyle/freshness scoring, dismissed/snoozed filtering, and the action
// lookup helpers (bucketActions / actions(for:)).

final class GenomePriorityEngineTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a minimal CuratedMarker for tests — only the fields used by the
    /// priority engine are populated.
    private func curated(rsid: String,
                         gene: String = "GENE",
                         category: MarkerCategory = .longevity,
                         polarity: MarkerPolarity = .risk) -> CuratedMarker {
        CuratedMarker(
            rsid: rsid,
            gene: gene,
            name: "Test \(rsid)",
            category: category,
            description: "",
            implications: [:],
            rules: [],
            polarity: polarity
        )
    }

    private func markerResult(rsid: String,
                              status: GenomeMarkerStatus,
                              genotype: String? = nil,
                              polarity: MarkerPolarity = .risk) -> MarkerResult {
        MarkerResult(
            marker: curated(rsid: rsid, polarity: polarity),
            genotype: genotype,
            status: status,
            implication: ""
        )
    }

    private func clinvarHit(rsid: String,
                            severity: String,
                            stars: Int = 3,
                            condition: String = "test condition") -> ClinVarHit {
        ClinVarHit(
            rsid: rsid,
            genotype: "A/A",
            entry: ClinVarEntry(
                gene: "GENE",
                severity: severity,
                conditions: [condition],
                reviewStars: stars,
                significance: "",
                submissions: 1
            )
        )
    }

    private func summary(_ results: [MarkerResult] = [], apoe: APOEResult? = nil) -> GenomeScanSummary {
        GenomeScanSummary(
            markerResults: results,
            apoeResult: apoe,
            scannedAt: Date(),
            statusCounts: [:]
        )
    }

    private func libraryAction(id: String,
                               rsid: String,
                               kind: GenomeActionKind = .lifestyle,
                               minStatus: GenomeMarkerStatus? = nil,
                               genotypes: [String]? = nil) -> GenomeAction {
        GenomeAction(
            id: id,
            kind: kind,
            title: "Test \(id)",
            detail: "",
            urgency: .soon,
            conditions: [GenomeActionCondition(rsid: rsid, genotypes: genotypes, minStatus: minStatus)],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: nil
        )
    }

    // MARK: - severityScore

    func testSeverityScoreMarker() {
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .marker(markerResult(rsid: "rs1", status: .majorConcern))), 1.0)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .marker(markerResult(rsid: "rs1", status: .concern))), 0.7)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .marker(markerResult(rsid: "rs1", status: .beneficial))), 0.2)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .marker(markerResult(rsid: "rs1", status: .typical))), 0.0)
    }

    func testSeverityScoreClinvar() {
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "pathogenic"))), 1.0)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "risk_factor"))), 0.7)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "drug_response"))), 0.5)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "protective"))), 0.2)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "unknown"))), 0.0)
    }

    func testSeverityScoreApoe() {
        let major = APOEResult(haplotype: "ε4/ε4", frequency: "", riskMultiplier: "", status: .majorConcern, implication: "")
        let concern = APOEResult(haplotype: "ε3/ε4", frequency: "", riskMultiplier: "", status: .concern, implication: "")
        let beneficial = APOEResult(haplotype: "ε2/ε3", frequency: "", riskMultiplier: "", status: .beneficial, implication: "")
        let typical = APOEResult(haplotype: "ε3/ε3", frequency: "", riskMultiplier: "", status: .typical, implication: "")
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .apoe(major)), 1.0)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .apoe(concern)), 0.7)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .apoe(beneficial)), 0.2)
        XCTAssertEqual(GenomePriorityEngine.severityScore(for: .apoe(typical)), 0.0)
    }

    // MARK: - confidenceScore

    func testConfidenceScoreMarkerAndApoeFixed() {
        let m = PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .concern))
        let a = APOEResult(haplotype: "ε4/ε4", frequency: "", riskMultiplier: "", status: .majorConcern, implication: "")
        XCTAssertEqual(GenomePriorityEngine.confidenceScore(for: m), 0.85)
        XCTAssertEqual(GenomePriorityEngine.confidenceScore(for: .apoe(a)), 0.85)
    }

    func testConfidenceScoreClinvarByStars() {
        XCTAssertEqual(GenomePriorityEngine.confidenceScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "pathogenic", stars: 4))), 1.0)
        XCTAssertEqual(GenomePriorityEngine.confidenceScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "pathogenic", stars: 5))), 1.0)
        XCTAssertEqual(GenomePriorityEngine.confidenceScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "pathogenic", stars: 3))), 0.85)
        XCTAssertEqual(GenomePriorityEngine.confidenceScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "pathogenic", stars: 2))), 0.7)
        XCTAssertEqual(GenomePriorityEngine.confidenceScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "pathogenic", stars: 1))), 0.6)
        XCTAssertEqual(GenomePriorityEngine.confidenceScore(for: .clinvar(clinvarHit(rsid: "rs1", severity: "pathogenic", stars: 0))), 0.5)
    }

    // MARK: - actionabilityScore

    func testActionabilityScoreEmptyActions() {
        XCTAssertEqual(GenomePriorityEngine.actionabilityScore(for: []), 0.6)
    }

    func testActionabilityScoreOnlyResearch() {
        let action = libraryAction(id: "research-1", rsid: "rs1", kind: .research)
        XCTAssertEqual(GenomePriorityEngine.actionabilityScore(for: [action]), 0.4)
    }

    func testActionabilityScoreContainsConcreteAction() {
        let research = libraryAction(id: "research-1", rsid: "rs1", kind: .research)
        let bloodTest = libraryAction(id: "blood-1", rsid: "rs1", kind: .bloodTest)
        XCTAssertEqual(GenomePriorityEngine.actionabilityScore(for: [research, bloodTest]), 1.0)
    }

    // MARK: - lifestyleAmplifier

    func testLifestyleAmplifierNilLifestyleNoEffect() {
        let source = PriorityFindingSource.marker(markerResult(rsid: "rs1333049", status: .concern))
        XCTAssertEqual(GenomePriorityEngine.lifestyleAmplifier(for: source, lifestyle: nil), 1.0)
    }

    func testLifestyleAmplifierApoeLowExerciseAmplifies() {
        let apoe = APOEResult(haplotype: "ε3/ε4", frequency: "", riskMultiplier: "", status: .concern, implication: "")
        var lifestyle = LifestyleData.default
        lifestyle.exerciseMinutesPerWeek = 30  // below WHO 150 target
        XCTAssertEqual(
            GenomePriorityEngine.lifestyleAmplifier(for: .apoe(apoe), lifestyle: lifestyle),
            1.4
        )
    }

    func testLifestyleAmplifierApoeAdequateExerciseNoBoost() {
        let apoe = APOEResult(haplotype: "ε3/ε4", frequency: "", riskMultiplier: "", status: .concern, implication: "")
        var lifestyle = LifestyleData.default
        lifestyle.exerciseMinutesPerWeek = 200
        XCTAssertEqual(
            GenomePriorityEngine.lifestyleAmplifier(for: .apoe(apoe), lifestyle: lifestyle),
            1.0
        )
    }

    func testLifestyleAmplifier9p21SmokerAmplifies() {
        let result = markerResult(rsid: "rs1333049", status: .concern)
        var lifestyle = LifestyleData.default
        lifestyle.smokingStatus = .current
        XCTAssertEqual(
            GenomePriorityEngine.lifestyleAmplifier(for: .marker(result), lifestyle: lifestyle),
            1.4
        )
    }

    func testLifestyleAmplifier9p21NonSmokerNoBoost() {
        let result = markerResult(rsid: "rs1333049", status: .concern)
        var lifestyle = LifestyleData.default
        lifestyle.smokingStatus = .never
        XCTAssertEqual(
            GenomePriorityEngine.lifestyleAmplifier(for: .marker(result), lifestyle: lifestyle),
            1.0
        )
    }

    func testLifestyleAmplifierClinvarUnchanged() {
        let hit = clinvarHit(rsid: "rs1", severity: "pathogenic")
        XCTAssertEqual(
            GenomePriorityEngine.lifestyleAmplifier(for: .clinvar(hit), lifestyle: LifestyleData.default),
            1.0
        )
    }

    // MARK: - freshnessScore

    func testFreshnessScoreEmptyState() {
        let counts = ActionStateCounts(pending: 0, inProgress: 0, discussed: 0, done: 0)
        XCTAssertEqual(GenomePriorityEngine.freshnessScore(stateCounts: counts), 1.0)
    }

    func testFreshnessScoreAllResolved() {
        let counts = ActionStateCounts(pending: 0, inProgress: 0, discussed: 1, done: 1)
        XCTAssertEqual(GenomePriorityEngine.freshnessScore(stateCounts: counts), 0.7)
    }

    func testFreshnessScoreInProgress() {
        let counts = ActionStateCounts(pending: 0, inProgress: 1, discussed: 0, done: 0)
        XCTAssertEqual(GenomePriorityEngine.freshnessScore(stateCounts: counts), 0.85)
    }

    func testFreshnessScoreSomePendingNotResolved() {
        let counts = ActionStateCounts(pending: 2, inProgress: 0, discussed: 0, done: 0)
        XCTAssertEqual(GenomePriorityEngine.freshnessScore(stateCounts: counts), 1.0)
    }

    // MARK: - bucketActions / actions(for:)

    func testBucketActionsIndexesByRsid() {
        let lib = [
            libraryAction(id: "a1", rsid: "rs1"),
            libraryAction(id: "a2", rsid: "rs1"),
            libraryAction(id: "a3", rsid: "rs2")
        ]
        let buckets = GenomePriorityEngine.bucketActions(lib)
        XCTAssertEqual(buckets.byRsid["rs1"]?.count, 2)
        XCTAssertEqual(buckets.byRsid["rs2"]?.count, 1)
        XCTAssertNil(buckets.byRsid["rs999"])
    }

    func testBucketActionsDeduplicatesActionWithRepeatedConditions() {
        // Action with two conditions both pointing at rs1 should appear once in the rs1 bucket.
        let action = GenomeAction(
            id: "a1",
            kind: .lifestyle,
            title: "",
            detail: "",
            urgency: .soon,
            conditions: [
                GenomeActionCondition(rsid: "rs1", minStatus: .concern),
                GenomeActionCondition(rsid: "rs1", minStatus: .majorConcern)
            ],
            bridge: nil,
            citationIds: [],
            doctorTalkingPoint: nil
        )
        let buckets = GenomePriorityEngine.bucketActions([action])
        XCTAssertEqual(buckets.byRsid["rs1"]?.count, 1)
    }

    func testActionsForMarkerFiltersByMinStatus() {
        let lib = [
            libraryAction(id: "a-concern", rsid: "rs1", minStatus: .concern),
            libraryAction(id: "a-major", rsid: "rs1", minStatus: .majorConcern)
        ]
        let bucket = GenomePriorityEngine.bucketActions(lib)
        let concernSource = PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .concern))
        let majorSource = PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .majorConcern))
        let concernActions = GenomePriorityEngine.actions(for: concernSource, bucketed: bucket)
        let majorActions = GenomePriorityEngine.actions(for: majorSource, bucketed: bucket)
        XCTAssertEqual(concernActions.map(\.id), ["a-concern"])  // major-only filtered out for concern
        XCTAssertEqual(Set(majorActions.map(\.id)), Set(["a-concern", "a-major"]))
    }

    func testActionsForApoeFiltersByGenotype() {
        let action = libraryAction(id: "apoe-e4", rsid: "apoe", genotypes: ["ε3/ε4", "ε4/ε4"])
        let bucket = GenomePriorityEngine.bucketActions([action])
        let e4Carrier = APOEResult(haplotype: "ε3/ε4", frequency: "", riskMultiplier: "", status: .concern, implication: "")
        let e2 = APOEResult(haplotype: "ε2/ε3", frequency: "", riskMultiplier: "", status: .typical, implication: "")
        XCTAssertEqual(GenomePriorityEngine.actions(for: .apoe(e4Carrier), bucketed: bucket).count, 1)
        XCTAssertEqual(GenomePriorityEngine.actions(for: .apoe(e2), bucketed: bucket).count, 0)
    }

    func testActionsForClinvarMergesDirectAndGenericBuckets() {
        let direct = libraryAction(id: "direct", rsid: "rs999")
        let generic = libraryAction(id: "generic", rsid: "clinvar:pathogenic")
        let bucket = GenomePriorityEngine.bucketActions([direct, generic])
        let hit = clinvarHit(rsid: "rs999", severity: "pathogenic")
        let actions = GenomePriorityEngine.actions(for: .clinvar(hit), bucketed: bucket)
        XCTAssertEqual(Set(actions.map(\.id)), Set(["direct", "generic"]))
    }

    // MARK: - PriorityFindingSource computed properties

    func testFindingKeyMarker() {
        let s = PriorityFindingSource.marker(markerResult(rsid: "rs1234", status: .concern))
        XCTAssertEqual(s.findingKey, "rs1234")
        XCTAssertEqual(s.lookupRsid, "rs1234")
    }

    func testFindingKeyClinvarIncludesConditionWhenPresent() {
        let s = PriorityFindingSource.clinvar(clinvarHit(rsid: "rs1234", severity: "pathogenic", condition: "Some Condition"))
        XCTAssertEqual(s.findingKey, "rs1234:some condition")
        XCTAssertEqual(s.lookupRsid, "rs1234")
    }

    func testFindingKeyClinvarFallbackToRsidWhenConditionEmpty() {
        let hit = ClinVarHit(
            rsid: "rs1234",
            genotype: "A/A",
            entry: ClinVarEntry(gene: "G", severity: "pathogenic", conditions: [],
                                reviewStars: 3, significance: "", submissions: 1)
        )
        let s = PriorityFindingSource.clinvar(hit)
        XCTAssertEqual(s.findingKey, "rs1234")
    }

    func testFindingKeyApoeIsConstant() {
        let a = APOEResult(haplotype: "ε4/ε4", frequency: "", riskMultiplier: "", status: .majorConcern, implication: "")
        let s = PriorityFindingSource.apoe(a)
        XCTAssertEqual(s.findingKey, "apoe")
        XCTAssertEqual(s.lookupRsid, "apoe")
    }

    func testFindingTitlesAreNonEmpty() {
        XCTAssertFalse(PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .concern)).title.isEmpty)
        XCTAssertFalse(PriorityFindingSource.clinvar(clinvarHit(rsid: "rs1", severity: "pathogenic")).title.isEmpty)
        let a = APOEResult(haplotype: "ε4/ε4", frequency: "", riskMultiplier: "", status: .majorConcern, implication: "")
        XCTAssertEqual(PriorityFindingSource.apoe(a).title, "APOE ε4/ε4")
    }

    func testFindingStatusLabels() {
        XCTAssertEqual(PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .majorConcern)).statusLabel, "Major Concern")
        XCTAssertEqual(PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .concern)).statusLabel, "Concern")
        XCTAssertEqual(PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .beneficial)).statusLabel, "Beneficial")
        XCTAssertEqual(PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .typical)).statusLabel, "Typical")
        XCTAssertEqual(PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .notFound)).statusLabel, "Not Found")
    }

    func testFindingHashableEquality() {
        let s1 = PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .concern))
        let s2 = PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .majorConcern))
        // Equality is by findingKey (rsid for marker), so different statuses but same rsid are equal.
        XCTAssertEqual(s1, s2)
        let s3 = PriorityFindingSource.marker(markerResult(rsid: "rs2", status: .concern))
        XCTAssertNotEqual(s1, s3)
    }

    // MARK: - clinvarSeverityLabel

    func testClinvarSeverityLabels() {
        XCTAssertEqual(clinvarSeverityLabel("pathogenic"), "Pathogenic")
        XCTAssertEqual(clinvarSeverityLabel("drug_response"), "Drug Response")
        XCTAssertEqual(clinvarSeverityLabel("risk_factor"), "Risk Factor")
        XCTAssertEqual(clinvarSeverityLabel("protective"), "Protective")
        XCTAssertEqual(clinvarSeverityLabel("unknown"), "Unknown")
    }

    // MARK: - rank — high-level integration

    func testRankExcludesTypicalAndNotFoundResults() {
        let scan = summary([
            markerResult(rsid: "rs-a", status: .typical),
            markerResult(rsid: "rs-b", status: .notFound),
            markerResult(rsid: "rs-c", status: .concern)
        ])
        let ranked = GenomePriorityEngine.rank(
            summary: scan, clinvarHits: [], library: [], states: [:], lifestyle: nil
        )
        XCTAssertEqual(ranked.map(\.id), ["rs-c"])
    }

    func testRankExcludesBeneficialWithoutActions() {
        // beneficial markers only surface if there's a curated action for them
        let scan = summary([markerResult(rsid: "rs-x", status: .beneficial)])
        let ranked = GenomePriorityEngine.rank(
            summary: scan, clinvarHits: [], library: [], states: [:], lifestyle: nil
        )
        XCTAssertTrue(ranked.isEmpty)
    }

    func testRankIncludesBeneficialWhenActionExists() {
        let scan = summary([markerResult(rsid: "rs-x", status: .beneficial)])
        let lib = [libraryAction(id: "a1", rsid: "rs-x")]
        let ranked = GenomePriorityEngine.rank(
            summary: scan, clinvarHits: [], library: lib, states: [:], lifestyle: nil
        )
        XCTAssertEqual(ranked.count, 1)
    }

    func testRankClinvarIncludesOnlyActionableSeverities() {
        let hits = [
            clinvarHit(rsid: "rs-1", severity: "pathogenic"),
            clinvarHit(rsid: "rs-2", severity: "risk_factor"),
            clinvarHit(rsid: "rs-3", severity: "drug_response"),
            clinvarHit(rsid: "rs-4", severity: "protective"),
            clinvarHit(rsid: "rs-5", severity: "benign")
        ]
        let ranked = GenomePriorityEngine.rank(
            summary: summary(), clinvarHits: hits, library: [], states: [:], lifestyle: nil
        )
        // pathogenic + risk_factor + drug_response — protective + benign filtered out
        XCTAssertEqual(ranked.count, 3)
    }

    func testRankCapsAtMaxPriorities() {
        let many = (0..<20).map { markerResult(rsid: "rs-\($0)", status: .majorConcern) }
        let ranked = GenomePriorityEngine.rank(
            summary: summary(many), clinvarHits: [], library: [], states: [:], lifestyle: nil
        )
        XCTAssertEqual(ranked.count, GenomePriorityEngine.maxPriorities)
    }

    func testRankSortsBySeverityDescending() {
        let scan = summary([
            markerResult(rsid: "rs-low", status: .concern),
            markerResult(rsid: "rs-high", status: .majorConcern)
        ])
        let ranked = GenomePriorityEngine.rank(
            summary: scan, clinvarHits: [], library: [], states: [:], lifestyle: nil
        )
        XCTAssertEqual(ranked.first?.id, "rs-high")
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    func testRankFiltersOutAllDismissedFindings() {
        let scan = summary([markerResult(rsid: "rs-x", status: .majorConcern)])
        let lib = [libraryAction(id: "a1", rsid: "rs-x")]
        let dismissed = GenomeActionState(
            key: GenomeActionState.key(rsid: "rs-x", actionId: "a1"),
            status: .dismissed
        )
        let states = [dismissed.key: dismissed]
        let ranked = GenomePriorityEngine.rank(
            summary: scan, clinvarHits: [], library: lib, states: states, lifestyle: nil
        )
        XCTAssertTrue(ranked.isEmpty)
    }

    func testRankFiltersOutSnoozedFindingsWithinWindow() {
        let scan = summary([markerResult(rsid: "rs-x", status: .majorConcern)])
        let lib = [libraryAction(id: "a1", rsid: "rs-x")]
        let snoozed = GenomeActionState(
            key: GenomeActionState.key(rsid: "rs-x", actionId: "a1"),
            status: .snoozed,
            updatedAt: DateFormatting.todayString()
        )
        let states = [snoozed.key: snoozed]
        let ranked = GenomePriorityEngine.rank(
            summary: scan, clinvarHits: [], library: lib, states: states, lifestyle: nil
        )
        XCTAssertTrue(ranked.isEmpty)
    }

    func testRankIncludesApoeWhenNotTypical() {
        let apoe = APOEResult(haplotype: "ε4/ε4", frequency: "", riskMultiplier: "",
                              status: .majorConcern, implication: "")
        let ranked = GenomePriorityEngine.rank(
            summary: summary(apoe: apoe), clinvarHits: [], library: [], states: [:], lifestyle: nil
        )
        XCTAssertEqual(ranked.first?.id, "apoe")
    }

    func testRankExcludesApoeTypical() {
        let apoe = APOEResult(haplotype: "ε3/ε3", frequency: "", riskMultiplier: "",
                              status: .typical, implication: "")
        let ranked = GenomePriorityEngine.rank(
            summary: summary(apoe: apoe), clinvarHits: [], library: [], states: [:], lifestyle: nil
        )
        XCTAssertTrue(ranked.isEmpty)
    }

    func testRankReportsAccurateActionCount() {
        let scan = summary([markerResult(rsid: "rs-x", status: .concern)])
        let lib = [
            libraryAction(id: "a1", rsid: "rs-x"),
            libraryAction(id: "a2", rsid: "rs-x", kind: .bloodTest)
        ]
        let ranked = GenomePriorityEngine.rank(
            summary: scan, clinvarHits: [], library: lib, states: [:], lifestyle: nil
        )
        XCTAssertEqual(ranked.first?.actionCount, 2)
    }

    func testRankConvenienceActionsLookupOverload() {
        // Convenience overload that buckets on demand should give same results as bucketed call
        let lib = [libraryAction(id: "a", rsid: "rs1", minStatus: .concern)]
        let source = PriorityFindingSource.marker(markerResult(rsid: "rs1", status: .concern))
        let direct = GenomePriorityEngine.actions(for: source, in: lib)
        XCTAssertEqual(direct.count, 1)
        XCTAssertEqual(direct.first?.id, "a")
    }

    // MARK: - Constants

    func testEngineConstantsAreReasonable() {
        XCTAssertGreaterThan(GenomePriorityEngine.maxPriorities, 0)
        XCTAssertGreaterThan(GenomePriorityEngine.snoozeDays, 0)
    }
}
