import XCTest
import PDFKit
@testable import MortalLoom

// MARK: - GenomeReport Tests
//
// Covers the pure pre-/post-visit content builders (which sections appear, how
// findings/notes/drug-response variants map into blocks, talking-point dedup)
// and a smoke test that the Core Text renderer produces a parseable PDF.

final class GenomeReportTests: XCTestCase {

    // MARK: - Fixtures

    /// APOE ε4/ε4 finding — matches real library actions (cardio + genetic
    /// counselor), both of which carry doctor talking points, so the builder has
    /// real bullets/talking points to emit.
    private func apoeFinding() -> PriorityFinding {
        let apoe = APOEResult(
            haplotype: "\u{03B5}4/\u{03B5}4",
            frequency: "2%",
            riskMultiplier: "~12x",
            status: .majorConcern,
            implication: "Highest APOE Alzheimer's risk."
        )
        return PriorityFinding(
            id: "apoe",
            source: .apoe(apoe),
            score: 1.0,
            topAction: nil,
            actionCount: 0,
            stateCounts: ActionStateCounts(pending: 0, inProgress: 0, discussed: 0, done: 0)
        )
    }

    private func drugHit(rsid: String = "rs4244285",
                         gene: String = "CYP2C19",
                         condition: String = "clopidogrel response") -> ClinVarHit {
        ClinVarHit(
            rsid: rsid,
            genotype: "A/A",
            entry: ClinVarEntry(
                gene: gene,
                severity: "drug_response",
                conditions: [condition],
                reviewStars: 3,
                significance: "",
                submissions: 1
            )
        )
    }

    private let date = Date(timeIntervalSince1970: 1_760_000_000) // fixed for determinism

    // MARK: - Pre-visit

    func testPrevisitIncludesAllThreeSections() {
        let content = GenomeReport.previsit(
            priorities: [apoeFinding()],
            clinvarHits: [drugHit()],
            date: date
        )
        XCTAssertEqual(content.title, "Doctor Visit Prep")
        let titles = content.sections.map(\.title)
        XCTAssertEqual(titles, ["Top Priorities", "Drug-Response Variants", "Questions for Your Doctor"])
    }

    func testPrevisitTopPrioritiesHasFindingHeaderAndActionBullets() {
        let content = GenomeReport.previsit(priorities: [apoeFinding()], clinvarHits: [], date: date)
        let blocks = content.sections.first { $0.title == "Top Priorities" }?.blocks ?? []

        guard case let .findingHeader(title, status, genotype) = blocks.first else {
            return XCTFail("expected a finding header first")
        }
        XCTAssertTrue(title.contains("APOE"))
        XCTAssertEqual(status, "Major Concern")
        XCTAssertEqual(genotype, "\u{03B5}4/\u{03B5}4")

        let bullets = blocks.filter { if case .bullet = $0 { return true } else { return false } }
        XCTAssertFalse(bullets.isEmpty, "expected curated action bullets for the finding")
    }

    func testPrevisitDedupesTalkingPoints() {
        // Two copies of the same finding must not double the talking points.
        let content = GenomeReport.previsit(
            priorities: [apoeFinding(), apoeFinding()],
            clinvarHits: [],
            date: date
        )
        let points = content.sections
            .first { $0.title == "Questions for Your Doctor" }?
            .blocks.compactMap { block -> String? in
                if case let .talkingPoint(text) = block { return text } else { return nil }
            } ?? []
        XCTAssertFalse(points.isEmpty)
        XCTAssertEqual(points.count, Set(points).count, "talking points should be deduped")
    }

    func testPrevisitDrugResponseListsHitAndGenotype() {
        let content = GenomeReport.previsit(priorities: [], clinvarHits: [drugHit()], date: date)
        let blocks = content.sections.first { $0.title == "Drug-Response Variants" }?.blocks ?? []
        let header = blocks.compactMap { block -> (String, String, String?)? in
            if case let .findingHeader(t, s, g) = block { return (t, s, g) } else { return nil }
        }.first
        XCTAssertEqual(header?.1, "Drug Response")
        XCTAssertEqual(header?.2, "A/A")
        XCTAssertTrue(header?.0.contains("CYP2C19") ?? false)
    }

    func testPrevisitDropsEmptySections() {
        let content = GenomeReport.previsit(priorities: [], clinvarHits: [], date: date)
        XCTAssertTrue(content.sections.isEmpty)
        XCTAssertEqual(content.title, "Doctor Visit Prep")
        XCTAssertTrue(content.meta.contains(GenomeReport.disclaimer))
    }

    // MARK: - Post-visit

    func testPostvisitMapsNotesToFindingTitlesAndKeepsFollowUp() {
        let note = VisitNote(
            date: "2026-06-13",
            providerLabel: "Dr. Chen",
            findingKey: "apoe",
            body: "Discussed neuroprotective cardio plan.",
            followUp: "Order ApoB panel."
        )
        let content = GenomeReport.postvisit(
            findings: [apoeFinding().source],
            clinvarHits: [drugHit()],
            notes: [note],
            date: date,
            provider: "Dr. Chen"
        )
        XCTAssertEqual(content.title, "Doctor Visit Summary")
        XCTAssertTrue(content.meta.contains { $0.contains("Dr. Chen") })

        let titles = content.sections.map(\.title)
        XCTAssertEqual(titles, ["Findings Reviewed", "Visit Notes", "Drug-Response Variants"])

        let noteBlocks = content.sections.first { $0.title == "Visit Notes" }?.blocks ?? []
        guard case let .note(finding, _, provider, body, followUp) = noteBlocks.first else {
            return XCTFail("expected a note block")
        }
        XCTAssertTrue(finding.contains("APOE"), "note should map findingKey -> finding title")
        XCTAssertEqual(provider, "Dr. Chen")
        XCTAssertEqual(body, "Discussed neuroprotective cardio plan.")
        XCTAssertEqual(followUp, "Order ApoB panel.")
    }

    func testPostvisitOmitsNotesSectionWhenNoNotes() {
        let content = GenomeReport.postvisit(
            findings: [apoeFinding().source],
            clinvarHits: [],
            notes: [],
            date: date,
            provider: nil
        )
        XCTAssertEqual(content.sections.map(\.title), ["Findings Reviewed"])
        XCTAssertFalse(content.meta.contains { $0.hasPrefix("Provider:") })
    }

    // MARK: - Filename

    func testFilenameEncodesPrefixAndDate() {
        let name = GenomeReport.filename(prefix: "VisitPrep", date: date)
        XCTAssertTrue(name.hasPrefix("MortalLoom-VisitPrep-"))
        XCTAssertTrue(name.hasSuffix(".pdf"))
        XCTAssertTrue(name.contains(DateFormatting.dateString(date)))
    }

    // MARK: - Renderer smoke test

    func testPdfDataIsParseablePDF() {
        let content = GenomeReport.previsit(
            priorities: [apoeFinding()],
            clinvarHits: [drugHit()],
            date: date
        )
        let data = GenomeReport.pdfData(for: content)
        XCTAssertFalse(data.isEmpty)
        let doc = PDFDocument(data: data)
        XCTAssertNotNil(doc, "renderer should emit a parseable PDF")
        XCTAssertGreaterThanOrEqual(doc?.pageCount ?? 0, 1)
    }

    func testPdfDataPaginatesLongReports() {
        // Many findings + notes should spill onto more than one page.
        let findings = Array(repeating: apoeFinding(), count: 12)
        let notes = (0..<12).map { i in
            VisitNote(date: "2026-06-13", providerLabel: "Dr. Chen", findingKey: "apoe",
                      body: String(repeating: "Detailed discussion notes. ", count: 20),
                      followUp: "Follow up item \(i).")
        }
        let content = GenomeReport.postvisit(
            findings: findings.map(\.source),
            clinvarHits: [drugHit()],
            notes: notes,
            date: date,
            provider: "Dr. Chen"
        )
        let doc = PDFDocument(data: GenomeReport.pdfData(for: content))
        XCTAssertGreaterThanOrEqual(doc?.pageCount ?? 0, 2)
    }
}
