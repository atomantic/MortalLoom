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
    static func parse(_ content: String) -> [GenomeVariant] {
        var variants: [GenomeVariant] = []

        for line in content.split(separator: "\n") {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.isEmpty || trimmed.first == "#" { continue }

            let parts: [Substring]
            if trimmed.contains("\t") {
                parts = trimmed.split(separator: "\t").map { $0.drop(while: { $0 == " " }) }
            } else if trimmed.contains(",") {
                parts = trimmed.split(separator: ",").map { $0.drop(while: { $0 == " " }) }
            } else {
                parts = trimmed.split(whereSeparator: { $0 == " " })
            }

            guard parts.count >= 4 else { continue }
            let rsID = parts[0]
            guard rsID.hasPrefix("rs") || rsID.hasPrefix("i") else { continue }

            let genotype = parts.count >= 5 ? "\(parts[3])\(parts[4])" : String(parts[3])

            variants.append(GenomeVariant(
                rsID: String(rsID), chromosome: String(parts[1]),
                position: String(parts[2]), genotype: genotype
            ))
        }

        return variants
    }
}
