import Foundation

extension Array {
    /// Average of the non-nil values at `keyPath`, or `nil` when none are present.
    /// Replaces the repeated `compactMap(\.field)` + `isEmpty ? nil : reduce/count`
    /// pattern that the longevity engines (gait, sleep, death-clock) each spelled out.
    func compactAverage<T: BinaryFloatingPoint>(_ keyPath: KeyPath<Element, T?>) -> T? {
        let values = compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return nil }
        return values.reduce(T.zero, +) / T(values.count)
    }
}
