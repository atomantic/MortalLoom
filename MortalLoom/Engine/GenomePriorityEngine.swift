import Foundation

// MARK: - Priority Engine Output Types

struct PriorityFinding: Sendable, Identifiable {
    let id: String
    let source: PriorityFindingSource
    let score: Double
    let topAction: GenomeAction?
    let actionCount: Int
    let stateCounts: ActionStateCounts

    /// Display label, e.g. "MTHFR C677T" or "BRCA1 (Breast cancer)".
    var title: String {
        switch source {
        case .marker(let r): r.marker.gene + (r.marker.name.isEmpty ? "" : " — \(r.marker.name)")
        case .clinvar(let h): (h.entry.gene.isEmpty ? h.rsid : h.entry.gene) +
            (h.entry.conditions.first.map { " (\($0))" } ?? "")
        case .apoe(let a): "APOE \(a.haplotype)"
        }
    }

    /// Status pill text (color drives severity dot in UI).
    var statusLabel: String {
        switch source {
        case .marker(let r):
            switch r.status {
            case .majorConcern: "Major Concern"
            case .concern: "Concern"
            case .beneficial: "Beneficial"
            case .typical: "Typical"
            case .notFound: "Not Found"
            }
        case .clinvar(let h):
            switch h.entry.severity {
            case "pathogenic": "Pathogenic"
            case "risk_factor": "Risk Factor"
            case "drug_response": "Drug Response"
            case "protective": "Protective"
            default: h.entry.severity.capitalized
            }
        case .apoe(let a):
            switch a.status {
            case .majorConcern: "Major Concern"
            case .concern: "Concern"
            case .beneficial: "Beneficial"
            default: "Typical"
            }
        }
    }
}

enum PriorityFindingSource: Sendable {
    case marker(MarkerResult)
    case clinvar(ClinVarHit)
    case apoe(APOEResult)

    /// rsid or "<rsid>:<condition-hash>" used to look up actions in the library
    /// and `GenomeActionState`s in `AppData`.
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

    /// rsid we use for action-library matching (ClinVar uses just rsid; the
    /// condition disambiguator is only for state storage).
    var lookupRsid: String {
        switch self {
        case .marker(let r): r.marker.rsid
        case .clinvar(let h): h.rsid
        case .apoe: "apoe"
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

// MARK: - Priority Engine

enum GenomePriorityEngine {

    /// Maximum number of priorities returned. Sized to fit one phone scroll.
    static let maxPriorities = 7

    /// Snooze duration applied when the user hits "Snooze 6 months". Hardcoded
    /// per design; a setting would only be added if real users ask.
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
        var sources: [PriorityFindingSource] = []

        // Markers — exclude `.notFound` and `.typical` outright (no signal),
        // and `.beneficial` unless the library has monitoring actions for it.
        for result in summary.markerResults where result.status != .notFound && result.status != .typical {
            if result.status == .beneficial {
                let actions = matchingActions(
                    forRsid: result.marker.rsid,
                    genotype: result.genotype,
                    status: result.status,
                    in: library
                )
                if actions.isEmpty { continue }
            }
            sources.append(.marker(result))
        }

        // APOE — only surface non-typical haplotypes
        if let apoe = summary.apoeResult, apoe.status != .typical {
            sources.append(.apoe(apoe))
        }

        // ClinVar — surface pathogenic + risk_factor + drug_response (always)
        for hit in clinvarHits {
            switch hit.entry.severity {
            case "pathogenic", "risk_factor", "drug_response":
                sources.append(.clinvar(hit))
            default:
                continue
            }
        }

        // Score + filter
        var scored: [(PriorityFinding, Double)] = []
        for source in sources {
            let actions = librariedActions(for: source, library: library)
            let stateCounts = countStates(for: source, actions: actions, states: states)

            // Filter rules
            if allDismissed(source: source, actions: actions, states: states) { continue }
            if anySnoozedAndUnexpired(source: source, actions: actions, states: states, today: today) { continue }

            // Score components
            let severity = severityScore(for: source)
            let confidence = confidenceScore(for: source)
            let actionability = actionabilityScore(for: actions)
            let lifestyleAmp = lifestyleAmplifier(for: source, lifestyle: lifestyle)
            let freshness = freshnessScore(stateCounts: stateCounts)

            let score = severity * confidence * actionability * lifestyleAmp * freshness
            let top = actions.first { $0.bridge != nil } ?? actions.first

            scored.append((
                PriorityFinding(
                    id: source.findingKey,
                    source: source,
                    score: score,
                    topAction: top,
                    actionCount: actions.count,
                    stateCounts: stateCounts
                ),
                score
            ))
        }

        scored.sort { $0.1 > $1.1 }
        return Array(scored.prefix(maxPriorities).map(\.0))
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
            if (a.haplotype.contains("\u{03B5}4")) && lifestyle.exerciseMinutesPerWeek < 150 {
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

    // MARK: - Lookup helpers

    /// Actions in the library that target this finding's rsid AND match the
    /// user's actual genotype/status (per `GenomeActionCondition`).
    static func matchingActions(
        forRsid rsid: String,
        genotype: String?,
        status: GenomeMarkerStatus,
        in library: [GenomeAction]
    ) -> [GenomeAction] {
        library.filter { action in
            action.conditions.contains { cond in
                guard cond.rsid == rsid else { return false }
                if let minStatus = cond.minStatus, !meetsMin(status: status, min: minStatus) {
                    return false
                }
                if let allowed = cond.genotypes {
                    guard let g = genotype else { return false }
                    let normalized = GenomeEngine.normalizeGenotype(g) ?? g
                    return allowed.contains { (GenomeEngine.normalizeGenotype($0) ?? $0) == normalized }
                }
                return true
            }
        }
    }

    private static func librariedActions(for source: PriorityFindingSource,
                                         library: [GenomeAction]) -> [GenomeAction] {
        switch source {
        case .marker(let r):
            return matchingActions(forRsid: r.marker.rsid, genotype: r.genotype, status: r.status, in: library)
        case .apoe(let a):
            // APOE actions are gated by haplotype-as-genotype string ("ε3/ε4")
            return library.filter { action in
                action.conditions.contains { $0.rsid == "apoe"
                    && ($0.genotypes?.contains(a.haplotype) ?? true) }
            }
        case .clinvar(let h):
            // ClinVar uses generic actions keyed by severity rather than rsid.
            // We match either rsid-specific or `clinvar:<severity>` pseudo-rsids.
            let pseudo = "clinvar:\(h.entry.severity)"
            return library.filter { action in
                action.conditions.contains { $0.rsid == h.rsid || $0.rsid == pseudo }
            }
        }
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

    private static func meetsMin(status: GenomeMarkerStatus, min: GenomeMarkerStatus) -> Bool {
        let order: [GenomeMarkerStatus: Int] = [
            .notFound: -1,
            .typical: 0,
            .beneficial: 1,
            .concern: 2,
            .majorConcern: 3
        ]
        return (order[status] ?? -1) >= (order[min] ?? -1)
    }
}
