import Foundation

// MARK: - Priority Engine Output Types

struct PriorityFinding: Sendable, Identifiable {
    let id: String
    let source: PriorityFindingSource
    let score: Double
    let topAction: GenomeAction?
    let actionCount: Int
    let stateCounts: ActionStateCounts

    var title: String { source.title }
    var statusLabel: String { source.statusLabel }
}

enum PriorityFindingSource: Sendable, Hashable, Identifiable {
    case marker(MarkerResult)
    case clinvar(ClinVarHit)
    case apoe(APOEResult)

    var id: String { findingKey }

    static func == (lhs: PriorityFindingSource, rhs: PriorityFindingSource) -> Bool {
        lhs.findingKey == rhs.findingKey
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(findingKey)
    }

    /// rsid or "<rsid>:<condition>" used to look up `GenomeActionState`s.
    var findingKey: String {
        switch self {
        case .marker(let r): r.marker.rsid
        case .clinvar(let h):
            if let cond = h.entry.conditions.first, !cond.isEmpty {
                "\(h.rsid):\(cond.lowercased())"
            } else {
                h.rsid
            }
        case .apoe: "apoe"
        }
    }

    /// rsid for action-library matching. ClinVar uses just rsid; the condition
    /// disambiguator is only for state storage.
    var lookupRsid: String {
        switch self {
        case .marker(let r): r.marker.rsid
        case .clinvar(let h): h.rsid
        case .apoe: "apoe"
        }
    }

    /// Display title — gene + marker name, or fallback to rsid.
    var title: String {
        switch self {
        case .marker(let r): r.marker.gene + (r.marker.name.isEmpty ? "" : " — \(r.marker.name)")
        case .clinvar(let h): (h.entry.gene.isEmpty ? h.rsid : h.entry.gene) +
            (h.entry.conditions.first.map { " (\($0))" } ?? "")
        case .apoe(let a): "APOE \(a.haplotype)"
        }
    }

    /// Status pill text.
    var statusLabel: String {
        switch self {
        case .marker(let r):
            switch r.status {
            case .majorConcern: "Major Concern"
            case .concern: "Concern"
            case .beneficial: "Beneficial"
            case .typical: "Typical"
            case .notFound: "Not Found"
            }
        case .clinvar(let h): clinvarSeverityLabel(h.entry.severity)
        case .apoe(let a):
            switch a.status {
            case .majorConcern: "Major Concern"
            case .concern: "Concern"
            case .beneficial: "Beneficial"
            default: "Typical"
            }
        }
    }

    /// SF Symbol shown beside the finding in the detail sheet and Visit Mode pane.
    var iconName: String {
        switch self {
        case .marker(let r): r.marker.category.icon
        case .clinvar: "building.columns.fill"
        case .apoe: "brain.head.profile"
        }
    }

    /// The user's genotype (marker/ClinVar) or haplotype (APOE), if known.
    var displayGenotype: String? {
        switch self {
        case .marker(let r): r.genotype
        case .clinvar(let h): h.genotype
        case .apoe(let a): a.haplotype
        }
    }
}

struct ActionStateCounts: Sendable {
    let pending: Int
    let inProgress: Int
    let discussed: Int
    let done: Int

    var total: Int { pending + inProgress + discussed + done }
}

// MARK: - Shared severity helpers
//
// The `Color`-returning severity helpers live in the Theme layer
// (Theme/GenomeSeverityColors.swift) so this engine stays free of SwiftUI.
// Only the framework-agnostic label helper remains here.

func clinvarSeverityLabel(_ severity: String) -> String {
    switch severity {
    case "pathogenic": "Pathogenic"
    case "drug_response": "Drug Response"
    case "risk_factor": "Risk Factor"
    case "protective": "Protective"
    default: severity.capitalized
    }
}

// MARK: - Priority Engine

enum GenomePriorityEngine {

    static let maxPriorities = 7
    static let snoozeDays = 180

    /// Pure ranker — combines severity, ClinVar confidence, library
    /// actionability, lifestyle amplification, and freshness, then filters
    /// out dismissed/snoozed findings and caps at `maxPriorities`.
    static func rank(
        summary: GenomeScanSummary,
        clinvarHits: [ClinVarHit],
        library: [GenomeAction],
        states: [String: GenomeActionState],
        lifestyle: LifestyleData?,
        today: Date = Date()
    ) -> [PriorityFinding] {
        let bucketed = bucketActions(library)
        var sources: [PriorityFindingSource] = []

        for result in summary.markerResults where result.status != .notFound && result.status != .typical {
            if result.status == .beneficial {
                if actions(for: .marker(result), bucketed: bucketed).isEmpty { continue }
            }
            sources.append(.marker(result))
        }

        if let apoe = summary.apoeResult, apoe.status != .typical {
            sources.append(.apoe(apoe))
        }

        for hit in clinvarHits {
            switch hit.entry.severity {
            case "pathogenic", "risk_factor", "drug_response":
                sources.append(.clinvar(hit))
            default:
                continue
            }
        }

        var scored: [(PriorityFinding, Double)] = []
        for source in sources {
            let matched = actions(for: source, bucketed: bucketed)
            let stateCounts = countStates(for: source, actions: matched, states: states)

            if allDismissed(source: source, actions: matched, states: states) { continue }
            if anySnoozedAndUnexpired(source: source, actions: matched, states: states, today: today) { continue }

            let score = severityScore(for: source)
                * confidenceScore(for: source)
                * actionabilityScore(for: matched)
                * lifestyleAmplifier(for: source, lifestyle: lifestyle)
                * freshnessScore(stateCounts: stateCounts)
            let top = matched.first { $0.bridge != nil } ?? matched.first

            scored.append((
                PriorityFinding(
                    id: source.findingKey,
                    source: source,
                    score: score,
                    topAction: top,
                    actionCount: matched.count,
                    stateCounts: stateCounts
                ),
                score
            ))
        }

        scored.sort { $0.1 > $1.1 }
        return Array(scored.prefix(maxPriorities).map(\.0))
    }

    // MARK: - Action lookup (public, pre-bucketed)

    /// Pre-bucketed view of the action library, indexed by the rsid each
    /// action's conditions reference. Pseudo-rsids (`apoe`, `clinvar:<sev>`)
    /// land in the same dictionary alongside real rsids.
    struct ActionBuckets {
        let byRsid: [String: [GenomeAction]]
    }

    /// Build the bucketed lookup once. Cheap (one library pass), reused across
    /// the whole `rank` invocation and any view-side action queries.
    static func bucketActions(_ library: [GenomeAction] = GenomeActionLibrary.all) -> ActionBuckets {
        var byRsid: [String: [GenomeAction]] = [:]
        for action in library {
            var seenRsids: Set<String> = []
            for cond in action.conditions where !seenRsids.contains(cond.rsid) {
                seenRsids.insert(cond.rsid)
                byRsid[cond.rsid, default: []].append(action)
            }
        }
        return ActionBuckets(byRsid: byRsid)
    }

    /// Actions matching a given finding. Filters by genotype/status conditions.
    /// Use this from views in place of the old triplicated lookup.
    static func actions(for source: PriorityFindingSource,
                        bucketed: ActionBuckets) -> [GenomeAction] {
        switch source {
        case .marker(let r):
            let candidates = bucketed.byRsid[r.marker.rsid] ?? []
            return candidates.filter { $0.matches(rsid: r.marker.rsid, genotype: r.genotype, status: r.status) }
        case .apoe(let a):
            let candidates = bucketed.byRsid["apoe"] ?? []
            return candidates.filter { action in
                action.conditions.contains { $0.rsid == "apoe"
                    && ($0.genotypes?.contains(a.haplotype) ?? true) }
            }
        case .clinvar(let h):
            let direct = bucketed.byRsid[h.rsid] ?? []
            let generic = bucketed.byRsid["clinvar:\(h.entry.severity)"] ?? []
            return direct + generic
        }
    }

    /// Convenience overload that buckets on demand. Use sparingly — for views
    /// that present a single finding, calling this per render is ~25 filter
    /// passes which is fine; for repeated lookups (rank), pass an `ActionBuckets`.
    static func actions(for source: PriorityFindingSource,
                        in library: [GenomeAction] = GenomeActionLibrary.all) -> [GenomeAction] {
        actions(for: source, bucketed: bucketActions(library))
    }

    // MARK: - Score Components

    static func severityScore(for source: PriorityFindingSource) -> Double {
        switch source {
        case .marker(let r):
            switch r.status {
            case .majorConcern: 1.0
            case .concern: 0.7
            case .beneficial: 0.2
            default: 0.0
            }
        case .clinvar(let h):
            switch h.entry.severity {
            case "pathogenic": 1.0
            case "risk_factor": 0.7
            case "drug_response": 0.5
            case "protective": 0.2
            default: 0.0
            }
        case .apoe(let a):
            switch a.status {
            case .majorConcern: 1.0
            case .concern: 0.7
            case .beneficial: 0.2
            default: 0.0
            }
        }
    }

    static func confidenceScore(for source: PriorityFindingSource) -> Double {
        switch source {
        case .marker, .apoe: 0.85
        case .clinvar(let h):
            // 4★ = 1.0, 3★ = 0.85, 2★ = 0.7, 1★ = 0.6, 0 = 0.5
            switch h.entry.reviewStars {
            case 4...: 1.0
            case 3: 0.85
            case 2: 0.7
            case 1: 0.6
            default: 0.5
            }
        }
    }

    static func actionabilityScore(for actions: [GenomeAction]) -> Double {
        if actions.contains(where: { $0.kind != .research }) { return 1.0 }
        if !actions.isEmpty { return 0.4 }
        return 0.6  // no curated actions — stays mid-range so it isn't crushed
    }

    /// Amplify findings whose modifiable lifestyle is mismatched. Small rule
    /// table — kept conservative.
    static func lifestyleAmplifier(for source: PriorityFindingSource,
                                    lifestyle: LifestyleData?) -> Double {
        guard let lifestyle else { return 1.0 }

        switch source {
        case .apoe(let a):
            // ε4 carriers benefit most from cardio. If exercise is below WHO target, amplify.
            if (a.haplotype.contains("\u{03B5}4")) && lifestyle.exerciseMinutesPerWeek < DeathClockEngine.Constants.exerciseRecommendedMinutes {
                return 1.4
            }
        case .marker(let r):
            // 9p21 CAD risk + smoker → strong amplifier
            if r.marker.rsid == "rs1333049" && r.status == .concern && lifestyle.smokingStatus == .current {
                return 1.4
            }
            // ALDH2 / ADH1B alcohol-flush — alcohol amplification handled by
            // `AlcoholRisk` flowing into RecommendationEngine separately, so we
            // only boost on the cardio/smoking pairing here.
        case .clinvar:
            break
        }
        return 1.0
    }

    static func freshnessScore(stateCounts: ActionStateCounts) -> Double {
        if stateCounts.total == 0 { return 1.0 }
        if stateCounts.discussed > 0 || stateCounts.done > 0 {
            // All resolved? Lowest freshness so it falls off the top.
            if stateCounts.pending == 0 && stateCounts.inProgress == 0 { return 0.7 }
        }
        if stateCounts.inProgress > 0 { return 0.85 }
        return 1.0
    }

    // MARK: - Filtering helpers

    private static func allDismissed(source: PriorityFindingSource,
                                     actions: [GenomeAction],
                                     states: [String: GenomeActionState]) -> Bool {
        guard !actions.isEmpty else { return false }
        return actions.allSatisfy { action in
            let key = GenomeActionState.key(rsid: source.findingKey, actionId: action.id)
            return states[key]?.status == .dismissed
        }
    }

    private static func anySnoozedAndUnexpired(source: PriorityFindingSource,
                                               actions: [GenomeAction],
                                               states: [String: GenomeActionState],
                                               today: Date) -> Bool {
        for action in actions {
            let key = GenomeActionState.key(rsid: source.findingKey, actionId: action.id)
            guard let state = states[key], state.status == .snoozed else { continue }
            let daysSince = DateFormatting.daysSince(state.updatedAt)
            if daysSince < snoozeDays { return true }
        }
        return false
    }

    private static func countStates(for source: PriorityFindingSource,
                                    actions: [GenomeAction],
                                    states: [String: GenomeActionState]) -> ActionStateCounts {
        var pending = 0, inProgress = 0, discussed = 0, done = 0
        for action in actions {
            let key = GenomeActionState.key(rsid: source.findingKey, actionId: action.id)
            switch states[key]?.status ?? .pending {
            case .pending: pending += 1
            case .inProgress: inProgress += 1
            case .discussed: discussed += 1
            case .done: done += 1
            case .snoozed, .dismissed: break
            }
        }
        return ActionStateCounts(pending: pending, inProgress: inProgress,
                                 discussed: discussed, done: done)
    }

}
