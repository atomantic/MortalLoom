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

enum GenomeParser {

    /// Parse genome file content (23andMe or AncestryDNA format) into variants.
    /// Returns an empty array if no valid variants are found.
    static func parse(_ content: String) -> [GenomeVariant] {
        let lines = content.components(separatedBy: .newlines)
        var variants: [GenomeVariant] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts: [String]
            if trimmed.contains("\t") {
                parts = trimmed.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if trimmed.contains(",") {
                parts = trimmed.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            }

            guard parts.count >= 4 else { continue }
            let rsID = parts[0]
            guard rsID.hasPrefix("rs") || rsID.hasPrefix("i") else { continue }

            let chromosome = parts[1]
            let position = parts[2]
            let genotype: String
            if parts.count >= 5 {
                genotype = parts[3] + parts[4]
            } else {
                genotype = parts[3]
            }

            variants.append(GenomeVariant(rsID: rsID, chromosome: chromosome, position: position, genotype: genotype))
        }

        return variants
    }
}
