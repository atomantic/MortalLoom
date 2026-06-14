import XCTest
@testable import MortalLoom

// MARK: - GenomeVisitFlow Tests
//
// Tests the pure navigation + note-construction helpers that drive Genome
// Visit Mode (`GenomeVisitModeView`): "Save & Next" sequencing, the
// last/position indicators, and the draft→`VisitNote` trimming rules.

final class GenomeVisitFlowTests: XCTestCase {

    private let order = ["rs1", "rs2", "rs3"]

    // MARK: - nextKey

    func testNextKeyAdvancesThroughOrder() {
        XCTAssertEqual(GenomeVisitFlow.nextKey(after: "rs1", in: order), "rs2")
        XCTAssertEqual(GenomeVisitFlow.nextKey(after: "rs2", in: order), "rs3")
    }

    func testNextKeyReturnsNilOnLast() {
        XCTAssertNil(GenomeVisitFlow.nextKey(after: "rs3", in: order))
    }

    func testNextKeyReturnsNilForMissingOrEmpty() {
        XCTAssertNil(GenomeVisitFlow.nextKey(after: "nope", in: order))
        XCTAssertNil(GenomeVisitFlow.nextKey(after: nil, in: order))
        XCTAssertNil(GenomeVisitFlow.nextKey(after: "rs1", in: []))
    }

    // MARK: - isLast / position

    func testIsLast() {
        XCTAssertTrue(GenomeVisitFlow.isLast("rs3", in: order))
        XCTAssertFalse(GenomeVisitFlow.isLast("rs2", in: order))
        XCTAssertFalse(GenomeVisitFlow.isLast(nil, in: order))
        XCTAssertFalse(GenomeVisitFlow.isLast("missing", in: order))
    }

    func testPositionIsOneBased() {
        XCTAssertEqual(GenomeVisitFlow.position(of: "rs1", in: order), 1)
        XCTAssertEqual(GenomeVisitFlow.position(of: "rs3", in: order), 3)
        XCTAssertEqual(GenomeVisitFlow.position(of: "missing", in: order), 0)
        XCTAssertEqual(GenomeVisitFlow.position(of: nil, in: order), 0)
    }

    // MARK: - makeNote

    func testMakeNoteTrimsAndPopulatesFields() {
        let note = GenomeVisitFlow.makeNote(
            date: Date(timeIntervalSince1970: 0),
            providerLabel: "  Dr. Patel  ",
            findingKey: "rs1",
            body: "  Discussed APOE risk.  ",
            followUp: "  Recheck in 3 months  "
        )
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.findingKey, "rs1")
        XCTAssertEqual(note?.providerLabel, "Dr. Patel")
        XCTAssertEqual(note?.body, "Discussed APOE risk.")
        XCTAssertEqual(note?.followUp, "Recheck in 3 months")
    }

    func testMakeNoteReturnsNilForBlankBody() {
        XCTAssertNil(GenomeVisitFlow.makeNote(
            date: Date(),
            providerLabel: "Dr. Patel",
            findingKey: "rs1",
            body: "   \n  ",
            followUp: "something"
        ))
    }

    func testMakeNoteNilsEmptyOptionalFields() {
        let note = GenomeVisitFlow.makeNote(
            date: Date(),
            providerLabel: "   ",
            findingKey: "rs1",
            body: "Body text",
            followUp: "   "
        )
        XCTAssertNotNil(note)
        XCTAssertNil(note?.providerLabel)
        XCTAssertNil(note?.followUp)
    }
}
