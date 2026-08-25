import PDFKit
import XCTest
@testable import MortalLoom

final class BloodReportPDFTests: XCTestCase {

    private let generatedAt = Date(timeIntervalSince1970: 1_780_000_000)

    func testEmptyReportProducesParseablePDFWithEmptyState() {
        let data = BloodReportPDF.pdfData(for: BloodReport(generatedAt: generatedAt, tests: []))

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = PDFDocument(data: data)
        XCTAssertNotNil(document)
        XCTAssertGreaterThanOrEqual(document?.pageCount ?? 0, 1)
        XCTAssertTrue(text(in: document).contains("No blood test results have been recorded yet."))
    }

    func testFlaggedRowsFollowCategoryOrderBeforeNormalRows() {
        let report = BloodReport(generatedAt: generatedAt, tests: [
            BloodTest(date: "2026-06-12", markers: [
                "glucose": 120,
                "ldl": 130,
                "hdl": 60,
            ]),
        ])
        let rows = BloodReportPDF.categories(for: report).flatMap(\.rows)
        let flagged = rows.filter(\.isFlagged)

        XCTAssertEqual(flagged.map(\.markerKey), ["glucose", "ldl"])
        XCTAssertEqual(flagged.map(\.category), ["Metabolic Panel", "Lipids"])
        XCTAssertTrue(flagged.allSatisfy { $0.delta == nil }, "a single panel must not invent deltas")

        let pdfText = text(in: PDFDocument(data: BloodReportPDF.pdfData(for: report)))
        XCTAssertLessThan(pdfText.range(of: "Glucose")!.lowerBound, pdfText.range(of: "HDL")!.lowerBound)
        XCTAssertTrue(pdfText.contains("High"))
        XCTAssertTrue(pdfText.contains("70–99 mg/dL"))
    }

    func testFlaggedMarkerIncludesDeltaFromPreviousResult() {
        let report = BloodReport(generatedAt: generatedAt, tests: [
            BloodTest(date: "2026-05-14", markers: ["glucose": 108]),
            BloodTest(date: "2026-06-12", markers: ["glucose": 120]),
        ])
        let glucose = BloodReportPDF.categories(for: report).flatMap(\.rows).first

        XCTAssertEqual(glucose?.delta, "↑ 12 mg/dL vs 2026-05-14")
        let pdfText = text(in: PDFDocument(data: BloodReportPDF.pdfData(for: report)))
        XCTAssertTrue(pdfText.contains("12 mg/dL vs 2026-05-14"))
    }

    func testUnknownMarkersAreOmitted() {
        let report = BloodReport(generatedAt: generatedAt, tests: [
            BloodTest(date: "2026-06-12", markers: ["glucose": 90, "mystery_marker": 42]),
        ])

        let rows = BloodReportPDF.categories(for: report).flatMap(\.rows)
        XCTAssertEqual(rows.map(\.markerKey), ["glucose"])
        XCTAssertFalse(text(in: PDFDocument(data: BloodReportPDF.pdfData(for: report))).contains("mystery_marker"))
    }

    func testFilenameUsesRequestedBloodPattern() {
        XCTAssertEqual(
            BloodReportPDF.filename(date: generatedAt),
            "MortalLoom-Blood-\(DateFormatting.dateString(generatedAt)).pdf"
        )
    }

    private func text(in document: PDFDocument?) -> String {
        guard let document else { return "" }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }
}
