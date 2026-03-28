import Foundation
import Compression

// MARK: - ClinVar Download & Index Service

/// Downloads and indexes the ClinVar database from NCBI for on-device genome cross-referencing.
/// The raw gzipped file (~30MB download) is streamed, parsed, filtered to actionable variants,
/// and stored as a compact JSON index (~5-10MB) in the app's documents directory.
enum ClinVarService {

    static let clinvarURL = "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/tab_delimited/variant_summary.txt.gz"

    private static let actionableSignificance: Set<String> = [
        "pathogenic", "likely pathogenic", "pathogenic/likely pathogenic",
        "risk factor", "drug response", "association", "protective", "affects",
        "pathogenic, risk factor", "likely pathogenic, risk factor"
    ]

    private static let reviewStars: [String: Int] = [
        "practice guideline": 4,
        "reviewed by expert panel": 3,
        "criteria provided, multiple submitters, no conflicts": 2,
        "criteria provided, conflicting classifications": 1,
        "criteria provided, single submitter": 1
    ]

    // MARK: - File Paths

    private static var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var indexFileURL: URL { documentsDir.appendingPathComponent("clinvar-index.json") }
    static var metaFileURL: URL { documentsDir.appendingPathComponent("clinvar-meta.json") }

    // MARK: - Status

    struct SyncStatus: Codable, Sendable {
        var synced: Bool
        var variantCount: Int?
        var syncedAt: String?
        var downloadSizeMB: Double?
    }

    static func getStatus() -> SyncStatus {
        guard let data = try? Data(contentsOf: metaFileURL),
              let status = try? JSONDecoder().decode(SyncStatus.self, from: data) else {
            return SyncStatus(synced: false)
        }
        return status
    }

    static func hasIndex() -> Bool {
        FileManager.default.fileExists(atPath: indexFileURL.path)
    }

    // MARK: - Load Index

    static func loadIndex() -> [String: ClinVarEntry]? {
        guard let data = try? Data(contentsOf: indexFileURL) else { return nil }
        return GenomeEngine.parseClinVarIndex(data: data)
    }

    // MARK: - Download & Build Index

    /// Download ClinVar from NCBI, parse, filter to actionable variants, and save compact index.
    /// Calls `onProgress` with status strings for UI updates.
    static func syncClinVar(onProgress: @Sendable @escaping (String) -> Void) async throws -> SyncStatus {
        onProgress("Downloading ClinVar database from NCBI...")

        // Download gzipped file to temp location
        let (tempFileURL, response) = try await URLSession.shared.download(from: URL(string: clinvarURL)!)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClinVarError.downloadFailed
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempFileURL.path)[.size] as? Int) ?? 0
        let sizeMB = Double(fileSize) / 1_048_576.0

        onProgress("Parsing ClinVar data (\(String(format: "%.0f", sizeMB))MB)...")

        // Decompress and parse
        let gzData = try Data(contentsOf: tempFileURL)
        let decompressed = try decompressGzip(gzData)

        guard let content = String(data: decompressed, encoding: .utf8) else {
            throw ClinVarError.parseError
        }

        onProgress("Filtering actionable variants...")

        let index = buildIndex(from: content, onProgress: onProgress)

        // Save compact index
        let encoder = JSONEncoder()
        let indexData = try encoder.encode(index)
        try indexData.write(to: indexFileURL)

        // Save metadata
        let meta = SyncStatus(
            synced: true,
            variantCount: index.count,
            syncedAt: ISO8601DateFormatter().string(from: Date()),
            downloadSizeMB: sizeMB
        )
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: metaFileURL)

        // Cleanup temp file
        try? FileManager.default.removeItem(at: tempFileURL)

        onProgress("Done — \(index.count) actionable variants indexed")
        return meta
    }

    // MARK: - Build Index from TSV Content

    private static func buildIndex(from content: String, onProgress: @Sendable @escaping (String) -> Void) -> [String: ClinVarEntry] {
        var index: [String: ClinVarEntry] = [:]
        var headerColumns: [String: Int] = [:]
        var lineCount = 0

        for line in content.components(separatedBy: .newlines) {
            lineCount += 1

            // Parse header
            if lineCount == 1 {
                let headerLine = line.hasPrefix("#") ? String(line.dropFirst()) : line
                for (i, col) in headerLine.split(separator: "\t").enumerated() {
                    headerColumns[col.trimmingCharacters(in: .whitespaces)] = i
                }
                continue
            }

            if lineCount % 500_000 == 0 {
                onProgress("Processed \(lineCount / 1_000_000)M lines...")
            }

            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map { String($0) }

            guard let rsCol = headerColumns["RS# (dbSNP)"],
                  rsCol < cols.count else { continue }

            let rawRsid = cols[rsCol].trimmingCharacters(in: .whitespaces)
            if rawRsid.isEmpty || rawRsid == "-1" || rawRsid == "-" { continue }
            let rsid = rawRsid.hasPrefix("rs") ? rawRsid : "rs\(rawRsid)"

            // Must be single nucleotide variant
            guard let typeCol = headerColumns["Type"],
                  typeCol < cols.count,
                  cols[typeCol].trimmingCharacters(in: .whitespaces).lowercased() == "single nucleotide variant" else { continue }

            // Must be actionable significance
            guard let sigCol = headerColumns["ClinicalSignificance"],
                  sigCol < cols.count else { continue }
            let rawSig = cols[sigCol].trimmingCharacters(in: .whitespaces)
            let sigLower = rawSig.lowercased()
            let isActionable = actionableSignificance.contains(where: { sigLower.contains($0) })
            if !isActionable { continue }

            // Assembly filter
            if let asmCol = headerColumns["Assembly"], asmCol < cols.count {
                let asm = cols[asmCol].trimmingCharacters(in: .whitespaces)
                if !asm.isEmpty && asm != "GRCh37" && asm != "GRCh38" { continue }
            }

            // Origin filter
            if let origCol = headerColumns["Origin"], origCol < cols.count {
                let origin = cols[origCol].trimmingCharacters(in: .whitespaces)
                if !origin.isEmpty && !origin.contains("germline") && origin != "not provided" { continue }
            }

            let gene = headerColumns["GeneSymbol"].flatMap { $0 < cols.count ? cols[$0].trimmingCharacters(in: .whitespaces) : nil } ?? ""
            let phenotype = headerColumns["PhenotypeList"].flatMap { $0 < cols.count ? cols[$0].trimmingCharacters(in: .whitespaces) : nil } ?? ""
            let reviewStatus = headerColumns["ReviewStatus"].flatMap { $0 < cols.count ? cols[$0].trimmingCharacters(in: .whitespaces) : nil } ?? ""
            let stars = reviewStars[reviewStatus] ?? 0

            // Determine severity
            var severity = "risk_factor"
            if sigLower.contains("pathogenic") { severity = "pathogenic" }
            else if sigLower.contains("protective") { severity = "protective" }
            else if sigLower.contains("drug response") { severity = "drug_response" }

            // Clean conditions
            let conditions = Array(Set(
                phenotype.split(separator: ";").flatMap { $0.split(separator: "|") }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && $0 != "not specified" && $0 != "not provided" }
            ).prefix(5))

            // Keep best entry per rsid (highest stars + pathogenic preference)
            if let existing = index[rsid] {
                let existingIsSevere = existing.severity == "pathogenic"
                let newIsSevere = severity == "pathogenic"
                if !newIsSevere && existingIsSevere { continue }
                if stars < existing.reviewStars && !newIsSevere { continue }
                // Merge conditions
                let merged = Array(Set(existing.conditions + conditions).prefix(8))
                index[rsid] = ClinVarEntry(
                    gene: gene.isEmpty ? existing.gene : gene,
                    severity: newIsSevere ? severity : existing.severity,
                    conditions: merged,
                    reviewStars: max(stars, existing.reviewStars),
                    significance: rawSig,
                    submissions: existing.submissions + 1
                )
            } else {
                index[rsid] = ClinVarEntry(
                    gene: gene,
                    severity: severity,
                    conditions: conditions,
                    reviewStars: stars,
                    significance: rawSig,
                    submissions: 1
                )
            }
        }

        return index
    }

    // MARK: - Gzip Decompression

    private static func decompressGzip(_ data: Data) throws -> Data {
        // Strip gzip header (10 bytes minimum) to get raw deflate stream
        guard data.count > 18 else { throw ClinVarError.parseError }
        guard data[0] == 0x1f && data[1] == 0x8b else { throw ClinVarError.parseError }

        // Find start of deflate data (skip gzip header)
        var offset = 10
        let flags = data[3]
        if flags & 0x04 != 0 { // FEXTRA
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC

        let deflateData = data[offset..<(data.count - 8)] // strip 8-byte gzip trailer

        // Use Apple's Compression framework for raw DEFLATE
        let sourceSize = deflateData.count
        // Allocate generous output buffer — ClinVar TSV decompresses to ~1GB
        // Process in chunks to avoid memory issues
        var result = Data()
        let chunkSize = 65536
        var sourceBuffer = Array(deflateData)

        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }

        var stream = streamPtr.pointee
        let initStatus = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else { throw ClinVarError.parseError }
        defer { compression_stream_destroy(&stream) }

        stream.src_ptr = UnsafePointer(sourceBuffer)
        stream.src_size = sourceSize

        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { dstBuffer.deallocate() }

        repeat {
            stream.dst_ptr = dstBuffer
            stream.dst_size = chunkSize

            let status = compression_stream_process(&stream, stream.src_size == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)

            let have = chunkSize - stream.dst_size
            if have > 0 {
                result.append(dstBuffer, count: have)
            }

            if status == COMPRESSION_STATUS_END { break }
            if status == COMPRESSION_STATUS_ERROR { throw ClinVarError.parseError }
        } while stream.src_size > 0 || stream.dst_size == 0

        return result
    }

    // MARK: - Delete

    static func deleteClinVar() {
        try? FileManager.default.removeItem(at: indexFileURL)
        try? FileManager.default.removeItem(at: metaFileURL)
    }
}

enum ClinVarError: Error, LocalizedError {
    case downloadFailed
    case parseError

    var errorDescription: String? {
        switch self {
        case .downloadFailed: "Failed to download ClinVar database"
        case .parseError: "Failed to parse ClinVar data"
        }
    }
}
