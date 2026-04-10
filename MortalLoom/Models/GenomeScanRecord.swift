import Foundation

/// Lightweight, Codable summary of a genome scan for persistence in AppData.
/// Captures per-category risk counts and APOE haplotype so the longevity engine
/// can apply genome-based life expectancy adjustments without re-scanning.
struct GenomeScanRecord: Codable, Sendable {
    let scannedAt: Date
    let apoeHaplotype: String?
    let apoeStatus: GenomeMarkerStatus?
    let categoryRisks: [String: CategoryRisk]

    struct CategoryRisk: Codable, Sendable {
        let beneficial: Int
        let typical: Int
        let concern: Int
        let majorConcern: Int
    }

    /// Build a GenomeScanRecord from a live GenomeScanSummary.
    static func from(_ summary: GenomeScanSummary) -> GenomeScanRecord {
        var risks: [String: CategoryRisk] = [:]

        // Group marker results by category and count statuses
        var categoryBuckets: [String: [GenomeMarkerStatus: Int]] = [:]
        for result in summary.markerResults where result.status != .notFound {
            let key = result.marker.category.rawValue
            categoryBuckets[key, default: [:]][result.status, default: 0] += 1
        }

        for (category, counts) in categoryBuckets {
            risks[category] = CategoryRisk(
                beneficial: counts[.beneficial] ?? 0,
                typical: counts[.typical] ?? 0,
                concern: counts[.concern] ?? 0,
                majorConcern: counts[.majorConcern] ?? 0
            )
        }

        return GenomeScanRecord(
            scannedAt: summary.scannedAt,
            apoeHaplotype: summary.apoeResult?.haplotype,
            apoeStatus: summary.apoeResult?.status,
            categoryRisks: risks
        )
    }
}
