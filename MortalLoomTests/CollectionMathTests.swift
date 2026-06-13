import XCTest
@testable import MortalLoom

// MARK: - CollectionMath Tests
//
// Pins the contract of `Sequence.compactAverage(_:)`, the shared helper that
// replaced the repeated `compactMap(\.field) + isEmpty ? nil : reduce/count`
// pattern across the engines and views. The load-bearing semantic is that it
// averages over the NON-NIL values only (divides by their count, not the
// element count) and returns nil when none are present.

final class CollectionMathTests: XCTestCase {

    private struct Row {
        let value: Double?
    }

    func testEmptySequenceReturnsNil() {
        XCTAssertNil([Row]().compactAverage(\.value))
    }

    func testAllNilReturnsNil() {
        let rows = [Row(value: nil), Row(value: nil)]
        XCTAssertNil(rows.compactAverage(\.value))
    }

    func testAllPresentAveragesEveryValue() {
        let rows = [Row(value: 2), Row(value: 4), Row(value: 6)]
        XCTAssertEqual(rows.compactAverage(\.value), 4)
    }

    func testDividesByNonNilCountNotElementCount() {
        // Two real values (10, 20) plus two nils → average 15, NOT 7.5.
        // This is the exact bug the old hand-rolled sites avoided and the
        // helper must preserve.
        let rows = [Row(value: 10), Row(value: nil), Row(value: 20), Row(value: nil)]
        XCTAssertEqual(rows.compactAverage(\.value), 15)
    }

    func testWorksOnArraySlice() {
        // The helper is on `Sequence` (not `Array`) so slices like `prefix(n)`
        // — used in BodyView — are covered.
        let rows = [Row(value: 1), Row(value: 3), Row(value: 5), Row(value: 99)]
        XCTAssertEqual(rows.prefix(3).compactAverage(\.value), 3)
    }
}
