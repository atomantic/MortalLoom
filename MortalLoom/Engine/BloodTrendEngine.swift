import Foundation

enum BloodTrendEngine {

    enum TrendDirection: String, Sendable {
        case rising, falling, stable
    }

    enum TrendSeverity: Int, Comparable, Sendable {
        case improving = 0
        case stable = 1
        case approaching = 2  // In range but heading toward boundary
        case worsening = 3    // Out of range and getting worse

        static func < (lhs: TrendSeverity, rhs: TrendSeverity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct MarkerTrend: Identifiable, Sendable {
        let id: String           // marker key
        let label: String
        let unit: String
        let direction: TrendDirection
        let severity: TrendSeverity
        let latestValue: Double
        let previousValue: Double
        let changePercent: Double // percentage change from previous
        let currentStatus: MarkerStatus
        let distanceToBoundary: Double? // nil if out-of-range already
        let detail: String       // human-readable summary
    }

    /// Analyze trends across blood tests for all markers with 2+ data points.
    /// Returns trends sorted by severity (most concerning first), then by change magnitude.
    static func analyze(tests: [BloodTest]) -> [MarkerTrend] {
        let sorted = tests.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return [] }

        var trends: [MarkerTrend] = []

        for ref in BloodMarkers.all {
            // Collect (date, value) pairs for this marker
            let values: [(date: String, value: Double)] = sorted.compactMap { test in
                guard let v = test.markers[ref.key] else { return nil }
                return (test.date, v)
            }
            guard values.count >= 2 else { continue }

            let latest = values[values.count - 1]
            let previous = values[values.count - 2]
            let delta = latest.value - previous.value
            let changePercent = previous.value != 0
                ? (delta / abs(previous.value)) * 100
                : 0

            let direction: TrendDirection
            // Use 2% threshold for stability to avoid noise
            if abs(changePercent) < 2 {
                direction = .stable
            } else if delta > 0 {
                direction = .rising
            } else {
                direction = .falling
            }

            let status = ref.status(for: latest.value)
            let severity = classifySeverity(
                ref: ref,
                latestValue: latest.value,
                previousValue: previous.value,
                status: status,
                direction: direction
            )

            let distanceToBoundary = boundaryDistance(ref: ref, value: latest.value)

            let detail = buildDetail(
                label: ref.label,
                direction: direction,
                severity: severity,
                latestValue: latest.value,
                changePercent: changePercent,
                status: status,
                unit: ref.unit
            )

            trends.append(MarkerTrend(
                id: ref.key,
                label: ref.label,
                unit: ref.unit,
                direction: direction,
                severity: severity,
                latestValue: latest.value,
                previousValue: previous.value,
                changePercent: (changePercent * 10).rounded() / 10,
                currentStatus: status,
                distanceToBoundary: distanceToBoundary,
                detail: detail
            ))
        }

        return trends.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return abs($0.changePercent) > abs($1.changePercent)
        }
    }

    /// Return only concerning trends (approaching or worsening).
    static func alerts(tests: [BloodTest]) -> [MarkerTrend] {
        analyze(tests: tests).filter { $0.severity >= .approaching }
    }

    // MARK: - Internal

    /// Classify severity based on current status, direction, and proximity to boundaries.
    private static func classifySeverity(
        ref: BloodMarkerRef,
        latestValue: Double,
        previousValue: Double,
        status: MarkerStatus,
        direction: TrendDirection
    ) -> TrendSeverity {
        let rangeSize = ref.max - ref.min
        guard rangeSize > 0 else { return .stable }

        switch status {
        case .normal:
            // In range — check if trending toward a boundary
            let distToMin = latestValue - ref.min
            let distToMax = ref.max - latestValue
            let nearestBoundaryDist = min(distToMin, distToMax)
            let boundaryProximity = nearestBoundaryDist / rangeSize

            // Within 15% of boundary AND heading that way
            if boundaryProximity < 0.15 {
                let headingToMin = direction == .falling && distToMin < distToMax
                let headingToMax = direction == .rising && distToMax < distToMin
                if headingToMin || headingToMax {
                    return .approaching
                }
            }

            // Check if moving from out-of-range back toward normal
            let prevStatus = ref.status(for: previousValue)
            if prevStatus != .normal && status == .normal {
                return .improving
            }

            return .stable

        case .low:
            // Below range — rising is improving, falling is worsening
            return direction == .rising ? .improving : (direction == .falling ? .worsening : .stable)

        case .high:
            // Above range — falling is improving, rising is worsening
            return direction == .falling ? .improving : (direction == .rising ? .worsening : .stable)

        case .unknown:
            return .stable
        }
    }

    /// Distance to nearest boundary as a fraction of the reference range.
    /// Returns nil if already out of range.
    private static func boundaryDistance(ref: BloodMarkerRef, value: Double) -> Double? {
        let status = ref.status(for: value)
        guard status == .normal else { return nil }
        let rangeSize = ref.max - ref.min
        guard rangeSize > 0 else { return nil }
        let distToMin = value - ref.min
        let distToMax = ref.max - value
        return (min(distToMin, distToMax) / rangeSize * 100).rounded() / 100
    }

    private static func buildDetail(
        label: String,
        direction: TrendDirection,
        severity: TrendSeverity,
        latestValue: Double,
        changePercent: Double,
        status: MarkerStatus,
        unit: String
    ) -> String {
        let arrow = direction == .rising ? "up" : (direction == .falling ? "down" : "stable")
        let pct = String(format: "%.1f", abs(changePercent))
        let val = formatValue(latestValue)

        switch severity {
        case .worsening:
            let statusWord = status == .high ? "above" : "below"
            return "\(label) is \(statusWord) range at \(val) \(unit) and trending \(arrow) (\(pct)%)"
        case .approaching:
            return "\(label) at \(val) \(unit) approaching boundary — trending \(arrow) (\(pct)%)"
        case .improving:
            return "\(label) improving at \(val) \(unit), trending \(arrow) (\(pct)%)"
        case .stable:
            return "\(label) stable at \(val) \(unit)"
        }
    }

    private static func formatValue(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}
