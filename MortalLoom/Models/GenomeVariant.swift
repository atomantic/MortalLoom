import Foundation

struct GenomeVariant: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let rsID: String
    let chromosome: String
    let position: String
    let genotype: String

    init(id: UUID = UUID(), rsID: String, chromosome: String, position: String, genotype: String) {
        self.id = id
        self.rsID = rsID
        self.chromosome = chromosome
        self.position = position
        self.genotype = genotype
    }
}

// MARK: - Genome Parsing

struct GenomeParseResult: Sendable {
    let variants: [GenomeVariant]
    let build: String?
}

enum GenomeParser {

    private static let csvTrimSet: Set<Character> = [" ", "\""]

    /// Parse genome file content (23andMe or AncestryDNA format) into variants.
    /// 23andMe format: rsid\tchromosome\tposition\tgenotype (4 tab-separated columns)
    /// AncestryDNA format: rsid\tchromosome\tposition\tallele1\tallele2 (5 tab-separated columns)
    static func parse(_ content: String) -> GenomeParseResult {
        var variants: [GenomeVariant] = []
        var build: String?

        for line in content.components(separatedBy: .newlines) {
            let line = line[...]
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("#") {
                let lower = trimmed.lowercased()
                if lower.contains("build 36") { build = "Build 36" }
                else if lower.contains("build 37") { build = "Build 37" }
                else if lower.contains("build 38") || lower.contains("grch38") { build = "Build 38" }
                continue
            }

            let parts: [Substring]
            if trimmed.contains("\t") {
                parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
            } else if trimmed.contains(",") {
                parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
                    .map { sub in
                        var s = sub
                        while let first = s.first, csvTrimSet.contains(first) { s = s.dropFirst() }
                        while let last = s.last, csvTrimSet.contains(last) { s = s.dropLast() }
                        return s
                    }
            } else {
                parts = trimmed.split(whereSeparator: { $0 == " " })
            }

            guard parts.count >= 4 else { continue }

            let rsID = parts[0].trimmingCharacters(in: .whitespaces)
            guard rsID.hasPrefix("rs") || rsID.hasPrefix("i") else { continue }

            let chromosome = parts[1].trimmingCharacters(in: .whitespaces)
            let position = parts[2].trimmingCharacters(in: .whitespaces)

            // AncestryDNA has allele1 + allele2 in columns 4-5; 23andMe has genotype in column 4
            let genotype: String
            if parts.count >= 5 {
                let a1 = parts[3].trimmingCharacters(in: .whitespaces)
                let a2 = parts[4].trimmingCharacters(in: .whitespaces)
                if a1.count == 1 && a2.count == 1 {
                    genotype = "\(a1)\(a2)"
                } else {
                    genotype = a1
                }
            } else {
                genotype = parts[3].trimmingCharacters(in: .whitespaces)
            }

            guard !genotype.isEmpty else { continue }

            variants.append(GenomeVariant(
                rsID: rsID, chromosome: chromosome,
                position: position, genotype: genotype
            ))
        }

        return GenomeParseResult(variants: variants, build: build)
    }

    /// Check if data looks like a zip file (PK\x03\x04 magic bytes)
    static func isZipFile(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x50 && data[1] == 0x4B && data[2] == 0x03 && data[3] == 0x04
    }
}
