import Foundation

// MARK: - Genome Marker Status

/// Classification status for curated genome marker results.
/// Distinct from blood test MarkerStatus — genome markers use beneficial/typical/concern/major_concern/not_found.
enum GenomeMarkerStatus: String, Sendable, Codable, CaseIterable {
    case beneficial
    case typical
    case concern
    case majorConcern = "major_concern"
    case notFound = "not_found"
}

// MARK: - Curated Marker Types

/// A rule mapping genotypes to a classification status.
struct MarkerRule: Sendable {
    let genotypes: [String]
    let status: GenomeMarkerStatus
}

/// A curated genome marker with classification rules.
struct CuratedMarker: Sendable {
    let rsid: String
    let gene: String
    let name: String
    let category: MarkerCategory
    let description: String
    let implications: [GenomeMarkerStatus: String]
    let rules: [MarkerRule]
}

/// Whether a marker's rare variant is desirable (`.protective`, e.g. FOXO3A longevity)
/// or undesirable (`.risk`, e.g. HFE iron overload). Used to pick contextually
/// appropriate labels: "Concern" on a protective marker just means "no benefit
/// variant" — not an elevated risk.
enum MarkerPolarity: Sendable {
    case protective
    case risk
}

extension CuratedMarker {
    /// Inferred from rule shape: rules containing `.majorConcern` describe a
    /// risk marker; rules that only go beneficial → typical → concern describe
    /// a protective marker where "concern" means lacking the beneficial variant.
    var polarity: MarkerPolarity {
        rules.contains(where: { $0.status == .majorConcern }) ? .risk : .protective
    }
}

// MARK: - Marker Scan Result

struct MarkerResult: Sendable {
    let marker: CuratedMarker
    let genotype: String?
    let status: GenomeMarkerStatus
    let implication: String
}

// MARK: - ClinVar Types

struct ClinVarEntry: Codable, Sendable {
    let gene: String
    let severity: String       // pathogenic, risk_factor, drug_response, protective
    let conditions: [String]
    let reviewStars: Int
    let significance: String
    let submissions: Int

    // Compact coding keys for on-disk storage (matches PortOS format)
    enum CodingKeys: String, CodingKey {
        case gene = "g"
        case severity = "s"
        case conditions = "c"
        case reviewStars = "r"
        case significance = "x"
        case submissions = "n"
    }
}

struct ClinVarHit: Sendable {
    let rsid: String
    let genotype: String
    let entry: ClinVarEntry
}

// MARK: - APOE Haplotype

struct APOEResult: Sendable {
    let haplotype: String
    let frequency: String
    let riskMultiplier: String
    let status: GenomeMarkerStatus
    let implication: String
}

// MARK: - Genome Scan Summary

struct GenomeScanSummary: Sendable {
    let markerResults: [MarkerResult]
    let apoeResult: APOEResult?
    let scannedAt: Date
    let statusCounts: [GenomeMarkerStatus: Int]
}

struct ClinVarScanSummary: Sendable {
    let hits: [ClinVarHit]
    let totalMatched: Int
    let bySeverity: [String: Int]
}

// MARK: - Genome Engine

enum GenomeEngine {

    // MARK: - Genotype Normalization

    /// Normalize raw genotype to canonical "A/T" format with sorted alleles.
    /// Handles: "AT" -> "A/T", "TA" -> "A/T", "A/T" -> "A/T", "T/A" -> "A/T",
    ///          "--" -> nil, "00" -> nil, "D" -> "D/D" (single allele = homozygous),
    ///          "II" -> "I/I", "DD" -> "D/D"
    static func normalizeGenotype(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty, cleaned != "--", cleaned != "00" else { return nil }

        let alleles: [String]
        if cleaned.contains("/") {
            alleles = cleaned.split(separator: "/").map(String.init)
        } else if cleaned.count == 2 {
            alleles = [String(cleaned.first!), String(cleaned.last!)]
        } else if cleaned.count == 1 {
            alleles = [cleaned, cleaned]
        } else {
            return cleaned
        }

        guard alleles.count == 2 else { return cleaned }
        return alleles.sorted().joined(separator: "/")
    }

    /// Format genotype for display: "AT" -> "A/T". Does not sort alleles (preserves order).
    static func formatGenotype(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty, cleaned != "--", cleaned != "00" else { return nil }
        if cleaned.contains("/") { return cleaned }
        if cleaned.count == 2 { return "\(cleaned.first!)/\(cleaned.last!)" }
        if cleaned.count == 1 { return "\(cleaned)/\(cleaned)" }
        return cleaned
    }

    // MARK: - Genotype Classification

    /// Classify a genotype against a curated marker's rules.
    /// Normalizes both the input genotype and each rule's genotypes before comparison.
    static func classifyGenotype(marker: CuratedMarker, rawGenotype: String) -> GenomeMarkerStatus {
        guard let normalized = normalizeGenotype(rawGenotype) else { return .notFound }

        for rule in marker.rules {
            let normalizedRuleGenotypes = rule.genotypes.compactMap { normalizeGenotype($0) }
            if normalizedRuleGenotypes.contains(normalized) {
                return rule.status
            }
        }
        // Genotype present but doesn't match any known rule
        return .typical
    }

    // MARK: - Marker Scanning

    /// Scan uploaded genome variants against curated markers.
    /// Builds an rsid->genotype lookup, classifies each marker, returns sorted results.
    static func scanMarkers(variants: [GenomeVariant], markers: [CuratedMarker]) -> [MarkerResult] {
        var lookup: [String: String] = [:]
        lookup.reserveCapacity(variants.count)
        for variant in variants { lookup[variant.rsID] = variant.genotype }
        return scanMarkersWithLookup(lookup: lookup, markers: markers)
    }

    static func scanMarkersWithLookup(lookup: [String: String], markers: [CuratedMarker]) -> [MarkerResult] {
        var results: [MarkerResult] = []
        results.reserveCapacity(markers.count)

        for marker in markers {
            let rawGenotype = lookup[marker.rsid]
            let genotype = rawGenotype.flatMap { formatGenotype($0) }
            let status: GenomeMarkerStatus
            if let raw = rawGenotype {
                status = classifyGenotype(marker: marker, rawGenotype: raw)
            } else {
                status = .notFound
            }
            results.append(MarkerResult(
                marker: marker,
                genotype: genotype,
                status: status,
                implication: marker.implications[status] ?? ""
            ))
        }

        return results.sorted { $0.marker.category < $1.marker.category }
    }

    // MARK: - Full Genome Scan (markers + APOE)

    /// Perform a full genome scan: curated markers + APOE haplotype resolution.
    static func fullScan(variants: [GenomeVariant], markers: [CuratedMarker]) -> GenomeScanSummary {
        // Build lookup once, reuse for both marker scan and APOE resolution
        var lookup: [String: String] = [:]
        lookup.reserveCapacity(variants.count)
        for variant in variants { lookup[variant.rsID] = variant.genotype }

        let markerResults = scanMarkersWithLookup(lookup: lookup, markers: markers)

        let apoeResult: APOEResult?
        if let rs429358 = lookup["rs429358"], let rs7412 = lookup["rs7412"] {
            apoeResult = resolveAPOEHaplotype(rs429358raw: rs429358, rs7412raw: rs7412)
        } else {
            apoeResult = nil
        }

        // Compute status counts
        var counts: [GenomeMarkerStatus: Int] = [:]
        for result in markerResults {
            counts[result.status, default: 0] += 1
        }

        return GenomeScanSummary(
            markerResults: markerResults,
            apoeResult: apoeResult,
            scannedAt: Date(),
            statusCounts: counts
        )
    }

    // MARK: - APOE Haplotype Resolution

    /// Resolve composite APOE haplotype from rs429358 and rs7412.
    ///
    /// APOE alleles are defined by two SNPs on chromosome 19:
    ///   e2: rs429358=T, rs7412=T
    ///   e3: rs429358=T, rs7412=C  (reference/common)
    ///   e4: rs429358=C, rs7412=C
    ///
    /// The six diploid genotypes and their Alzheimer's risk relative to e3/e3:
    ///   e2/e2 (T/T + T/T) — ~0.6x risk, ~0.7% of population
    ///   e2/e3 (T/T + C/T) — ~0.6x risk, ~11% of population
    ///   e3/e3 (T/T + C/C) — 1x baseline, ~60% of population
    ///   e2/e4 (C/T + C/T) — ~2.6x risk, ~2.6% of population
    ///   e3/e4 (C/T + C/C) — ~3.2x risk, ~21% of population
    ///   e4/e4 (C/C + C/C) — ~12x risk, ~2.3% of population
    static func resolveAPOEHaplotype(rs429358raw: String, rs7412raw: String) -> APOEResult? {
        guard let rs429358 = normalizeGenotype(rs429358raw),
              let rs7412 = normalizeGenotype(rs7412raw) else { return nil }

        let key = "\(rs429358)|\(rs7412)"

        switch key {
        case "T/T|T/T":
            return APOEResult(
                haplotype: "\u{03B5}2/\u{03B5}2",
                frequency: "~0.7%",
                riskMultiplier: "~0.6x",
                status: .beneficial,
                implication: "APOE \u{03B5}2/\u{03B5}2 \u{2014} rarest genotype with strongest Alzheimer\u{2019}s protection. Both alleles are the neuroprotective \u{03B5}2 variant. ~0.6x baseline Alzheimer\u{2019}s risk."
            )
        case "T/T|C/T":
            return APOEResult(
                haplotype: "\u{03B5}2/\u{03B5}3",
                frequency: "~11%",
                riskMultiplier: "~0.6x",
                status: .beneficial,
                implication: "APOE \u{03B5}2/\u{03B5}3 \u{2014} one protective \u{03B5}2 allele with the common \u{03B5}3. ~0.6x Alzheimer\u{2019}s risk compared to \u{03B5}3/\u{03B5}3 baseline."
            )
        case "T/T|C/C":
            return APOEResult(
                haplotype: "\u{03B5}3/\u{03B5}3",
                frequency: "~60%",
                riskMultiplier: "1x (baseline)",
                status: .typical,
                implication: "APOE \u{03B5}3/\u{03B5}3 \u{2014} most common genotype and the reference baseline. Standard age-related Alzheimer\u{2019}s risk."
            )
        case "C/T|C/T":
            return APOEResult(
                haplotype: "\u{03B5}2/\u{03B5}4",
                frequency: "~2.6%",
                riskMultiplier: "~2.6x",
                status: .concern,
                implication: "APOE \u{03B5}2/\u{03B5}4 \u{2014} one risk allele (\u{03B5}4) and one protective allele (\u{03B5}2). ~2.6x Alzheimer\u{2019}s risk. The \u{03B5}2 provides some attenuation."
            )
        case "C/T|C/C":
            return APOEResult(
                haplotype: "\u{03B5}3/\u{03B5}4",
                frequency: "~21%",
                riskMultiplier: "~3.2x",
                status: .concern,
                implication: "APOE \u{03B5}3/\u{03B5}4 \u{2014} one \u{03B5}4 risk allele with the common \u{03B5}3. ~3.2x Alzheimer\u{2019}s risk. Prioritize neuroprotective lifestyle: cardiovascular exercise, sleep optimization, omega-3/DHA."
            )
        case "C/C|C/C":
            return APOEResult(
                haplotype: "\u{03B5}4/\u{03B5}4",
                frequency: "~2.3%",
                riskMultiplier: "~12x",
                status: .majorConcern,
                implication: "APOE \u{03B5}4/\u{03B5}4 \u{2014} two \u{03B5}4 risk alleles. ~12x Alzheimer\u{2019}s risk. Aggressive neuroprotective strategy strongly recommended. Consider consulting a genetic counselor."
            )
        default:
            return nil
        }
    }

    // MARK: - ClinVar Index Parsing

    /// Parse a ClinVar JSON index (compact keys: g/s/c/r/x/n) into typed entries.
    /// Works with both PortOS-generated and locally-generated indexes.
    static func parseClinVarIndex(data: Data) -> [String: ClinVarEntry]? {
        guard let index = try? JSONDecoder().decode([String: ClinVarEntry].self, from: data),
              !index.isEmpty else { return nil }
        return index
    }

    // MARK: - ClinVar Scanning

    /// Severity sort order: pathogenic first, then drug_response, risk_factor, protective last.
    static let severityOrder: [String: Int] = [
        "pathogenic": 0,
        "drug_response": 1,
        "risk_factor": 2,
        "protective": 3
    ]

    /// Cross-reference genome variants against a ClinVar index.
    /// Returns hits sorted by severity (pathogenic first) then review stars (higher first).
    static func scanClinVar(variants: [GenomeVariant], index: [String: ClinVarEntry]) -> [ClinVarHit] {
        // Build rsid -> genotype lookup
        var lookup: [String: String] = [:]
        lookup.reserveCapacity(variants.count)
        for variant in variants {
            lookup[variant.rsID] = variant.genotype
        }

        var hits: [ClinVarHit] = []

        for (rsid, entry) in index {
            guard let rawGenotype = lookup[rsid] else { continue }
            guard let genotype = formatGenotype(rawGenotype) else { continue }

            hits.append(ClinVarHit(
                rsid: rsid,
                genotype: genotype,
                entry: entry
            ))
        }

        // Sort: pathogenic first, then by review stars descending
        hits.sort { a, b in
            let aOrder = severityOrder[a.entry.severity] ?? 9
            let bOrder = severityOrder[b.entry.severity] ?? 9
            if aOrder != bOrder { return aOrder < bOrder }
            return a.entry.reviewStars > b.entry.reviewStars
        }

        return hits
    }

    /// Scan ClinVar and return a summary with severity counts.
    static func scanClinVarSummary(variants: [GenomeVariant], index: [String: ClinVarEntry]) -> ClinVarScanSummary {
        let hits = scanClinVar(variants: variants, index: index)

        var bySeverity: [String: Int] = [:]
        for hit in hits {
            bySeverity[hit.entry.severity, default: 0] += 1
        }

        return ClinVarScanSummary(
            hits: hits,
            totalMatched: hits.count,
            bySeverity: bySeverity
        )
    }

    // MARK: - ClinVar Severity to Genome Status Mapping

    /// Map ClinVar severity level to our GenomeMarkerStatus for consistent UI display.
    static func statusForSeverity(_ severity: String) -> GenomeMarkerStatus {
        switch severity {
        case "pathogenic": return .majorConcern
        case "risk_factor", "drug_response": return .concern
        case "protective": return .beneficial
        default: return .typical
        }
    }

    // MARK: - ClinVar Health Theme Classification

    /// Classify a ClinVar hit into a health theme based on gene name and condition keywords.
    static func classifyTheme(_ hit: ClinVarHit) -> ClinVarTheme {
        let gene = hit.entry.gene.lowercased()
        let conds = hit.entry.conditions.joined(separator: " ").lowercased()
        let text = gene + " " + conds

        // Cancer — check specific cancer types first, then general
        if text.contains("breast") || text.contains("ovarian") || ["brca1", "brca2"].contains(gene) {
            return .cancerBreast
        }
        if text.contains("prostate") { return .cancerProstate }
        if text.contains("colorectal") || text.contains("colon") || text.contains("lynch") { return .cancerColorectal }
        if text.contains("lung") && (text.contains("cancer") || text.contains("carcinoma")) { return .cancerLung }
        if text.contains("melanoma") { return .cancerMelanoma }
        if text.contains("leukemia") || text.contains("lymphoma") || text.contains("myeloma") { return .cancerBlood }
        if text.contains("cancer") || text.contains("carcinoma") || text.contains("neoplasm") || text.contains("tumor")
            || text.contains("tumour") || text.contains("sarcoma") || text.contains("adenoma")
            || text.contains("glioma") || text.contains("blastoma") || gene == "tp53" || gene == "apc" { return .cancerOther }

        // Cardiovascular
        if text.contains("cardio") || text.contains("heart") || text.contains("arrhythmia") || text.contains("cardiomyopathy")
            || text.contains("atrial") || text.contains("ventricular") || text.contains("coronary") || text.contains("aortic")
            || text.contains("hypertension") || text.contains("long qt") || text.contains("brugada")
            || text.contains("marfan") || text.contains("thromb") || text.contains("factor v") { return .cardiovascular }

        // Neurological / Cognitive
        if text.contains("alzheimer") || text.contains("dementia") || text.contains("parkinson")
            || text.contains("huntington") || text.contains("neurodegenerat") || text.contains("amyotrophic")
            || text.contains("epilepsy") || text.contains("seizure") || text.contains("neuropathy")
            || text.contains("ataxia") || text.contains("charcot") { return .neurological }

        // Blood & Clotting
        if text.contains("anemia") || text.contains("anaemia") || text.contains("thalassemia") || text.contains("sickle cell")
            || text.contains("hemophilia") || text.contains("haemophilia") || text.contains("hemochromatosis")
            || text.contains("iron overload") || text.contains("factor v leiden") || text.contains("von willebrand") { return .blood }

        // Metabolic
        if text.contains("diabetes") || text.contains("obesity") || text.contains("metabolic")
            || text.contains("phenylketonuria") || text.contains("galactosemia") || text.contains("glycogen storage")
            || text.contains("familial hypercholesterolemia") || text.contains("gaucher") || text.contains("fabry") { return .metabolic }

        // Immune & Autoimmune
        if text.contains("autoimmune") || text.contains("lupus") || text.contains("rheumatoid")
            || text.contains("celiac") || text.contains("coeliac") || text.contains("crohn")
            || text.contains("multiple sclerosis") || text.contains("psoriasis") || text.contains("immunodeficiency") { return .immune }

        // Drug Response
        if hit.entry.severity == "drug_response" || text.contains("drug response") || text.contains("pharmacogen")
            || text.contains("warfarin") || text.contains("clopidogrel") || text.contains("statin")
            || text.contains("codeine") || text.contains("metabolism of") { return .drugResponse }

        // Vision
        if text.contains("macular") || text.contains("retinitis") || text.contains("glaucoma")
            || text.contains("retinal") || text.contains("blindness") || text.contains("leber") { return .vision }

        // Respiratory
        if text.contains("cystic fibrosis") || text.contains("asthma") || text.contains("pulmonary")
            || text.contains("copd") || text.contains("lung") { return .respiratory }

        // Connective Tissue & Musculoskeletal
        if text.contains("osteoporosis") || text.contains("ehlers") || text.contains("muscular dystrophy")
            || text.contains("skeletal") || text.contains("bone mineral") || text.contains("osteogenesis") { return .musculoskeletal }

        // Hearing
        if text.contains("hearing") || text.contains("deafness") || text.contains("connexin") { return .hearing }

        // Skin (psoriasis handled under immune above)
        if text.contains("skin") || text.contains("dermatitis") || text.contains("epidermolysis")
            || text.contains("ichthyosis") { return .skin }

        // Kidney
        if text.contains("kidney") || text.contains("renal") || text.contains("polycystic kidney")
            || text.contains("nephro") { return .kidney }

        // Liver
        if text.contains("liver") || text.contains("hepat") || text.contains("wilson disease")
            || text.contains("cirrhosis") || text.contains("biliary") { return .liver }

        // Endocrine
        if text.contains("thyroid") || text.contains("adrenal") || text.contains("pituitary")
            || text.contains("hormone") || text.contains("growth hormone") { return .endocrine }

        // Protective factors
        if hit.entry.severity == "protective" { return .protective }

        return .other
    }

    /// Group ClinVar hits by health theme.
    static func groupByTheme(_ hits: [ClinVarHit]) -> [(theme: ClinVarTheme, hits: [ClinVarHit])] {
        var grouped: [ClinVarTheme: [ClinVarHit]] = [:]
        var pathogenicCounts: [ClinVarTheme: Int] = [:]
        for hit in hits {
            let theme = classifyTheme(hit)
            grouped[theme, default: []].append(hit)
            if hit.entry.severity == "pathogenic" {
                pathogenicCounts[theme, default: 0] += 1
            }
        }

        return grouped.sorted { a, b in
            let aPath = pathogenicCounts[a.key] ?? 0
            let bPath = pathogenicCounts[b.key] ?? 0
            if aPath != bPath { return aPath > bPath }
            return a.value.count > b.value.count
        }.map { (theme: $0.key, hits: $0.value) }
    }
}

// MARK: - ClinVar Health Theme

enum ClinVarTheme: String, Sendable, CaseIterable {
    case cancerBreast = "cancer_breast"
    case cancerProstate = "cancer_prostate"
    case cancerColorectal = "cancer_colorectal"
    case cancerLung = "cancer_lung"
    case cancerMelanoma = "cancer_melanoma"
    case cancerBlood = "cancer_blood"
    case cancerOther = "cancer_other"
    case cardiovascular
    case neurological
    case blood
    case metabolic
    case immune
    case drugResponse = "drug_response"
    case vision
    case respiratory
    case musculoskeletal
    case hearing
    case skin
    case kidney
    case liver
    case endocrine
    case protective
    case other

    var label: String {
        switch self {
        case .cancerBreast: "Breast & Ovarian Cancer"
        case .cancerProstate: "Prostate Cancer"
        case .cancerColorectal: "Colorectal Cancer"
        case .cancerLung: "Lung Cancer"
        case .cancerMelanoma: "Melanoma"
        case .cancerBlood: "Blood Cancer"
        case .cancerOther: "Other Cancer"
        case .cardiovascular: "Cardiovascular"
        case .neurological: "Neurological"
        case .blood: "Blood & Clotting"
        case .metabolic: "Metabolic"
        case .immune: "Immune & Autoimmune"
        case .drugResponse: "Drug Response"
        case .vision: "Vision"
        case .respiratory: "Respiratory"
        case .musculoskeletal: "Musculoskeletal"
        case .hearing: "Hearing"
        case .skin: "Skin"
        case .kidney: "Kidney"
        case .liver: "Liver"
        case .endocrine: "Endocrine"
        case .protective: "Protective"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .cancerBreast: "ribbon"
        case .cancerProstate, .cancerColorectal, .cancerBlood, .cancerOther: "shield.checkmark.fill"
        case .cancerLung: "wind"
        case .cancerMelanoma: "sun.max.fill"
        case .cardiovascular: "heart.fill"
        case .neurological: "brain.head.profile"
        case .blood: "drop.fill"
        case .metabolic: "bolt.fill"
        case .immune: "shield.trianglebadge.exclamationmark.fill"
        case .drugResponse: "pills.fill"
        case .vision: "eye"
        case .respiratory: "lungs.fill"
        case .musculoskeletal: "figure.walk"
        case .hearing: "ear"
        case .skin: "sun.max.fill"
        case .kidney: "drop.triangle.fill"
        case .liver: "cross.circle.fill"
        case .endocrine: "waveform.path.ecg"
        case .protective: "checkmark.shield.fill"
        case .other: "questionmark.circle"
        }
    }
}
