import Foundation
import Compression

// MARK: - ClinVar Download & Index Service

/// Downloads and indexes the ClinVar database from NCBI for on-device genome cross-referencing.
/// The raw gzipped file (~30MB download) is streamed, parsed, filtered to actionable variants,
/// and stored as a compact JSON index (~5-10MB) in the app's documents directory.
enum ClinVarService {

    static let clinvarURL = "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/tab_delimited/variant_summary.txt.gz"

    private static let downloadURL: URL? = URL(string: clinvarURL)

    /// Cached ISO8601 formatter — `ISO8601DateFormatter` is expensive to allocate,
    /// and sharing a single static instance avoids repeated setup work.
    /// `nonisolated(unsafe)` opts the static out of strict concurrency checking;
    /// `ISO8601DateFormatter` is thread-safe in practice (Apple NSHipster docs, OSS tests).
    nonisolated(unsafe) private static let iso8601Formatter = ISO8601DateFormatter()

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

    private static let indexFileName = "clinvar-index.json"
    private static let metaFileName = "clinvar-meta.json"

    static var indexFileURL: URL {
        FileManager.default.newerOf(
            cloud: DataStore.iCloudDocumentsDirectory?.appendingPathComponent(indexFileName),
            local: DataStore.localDocumentsDirectory.appendingPathComponent(indexFileName)
        )
    }

    static var metaFileURL: URL {
        FileManager.default.newerOf(
            cloud: DataStore.iCloudDocumentsDirectory?.appendingPathComponent(metaFileName),
            local: DataStore.localDocumentsDirectory.appendingPathComponent(metaFileName)
        )
    }

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
    /// Uses streaming decompression to avoid loading the full ~1GB TSV into memory.
    static func syncClinVar(onProgress: @Sendable @escaping (String) -> Void) async throws -> SyncStatus {
        onProgress("Downloading ClinVar database from NCBI...")

        // Download gzipped file to temp location
        guard let url = downloadURL else { throw ClinVarError.downloadFailed }
        let (tempFileURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClinVarError.downloadFailed
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempFileURL.path)[.size] as? Int) ?? 0
        let sizeMB = Double(fileSize) / 1_048_576.0

        onProgress("Parsing ClinVar data (\(String(format: "%.0f", sizeMB))MB)...")

        // Stream-decompress and build index without holding full TSV in memory
        let gzData = try Data(contentsOf: tempFileURL)
        let index = try streamDecompressAndBuildIndex(gzData, onProgress: onProgress)

        let encoder = JSONEncoder()
        let indexData = try encoder.encode(index)
        let meta = SyncStatus(
            synced: true,
            variantCount: index.count,
            syncedAt: iso8601Formatter.string(from: Date()),
            downloadSizeMB: sizeMB
        )
        let metaData = try JSONEncoder().encode(meta)

        let local = DataStore.localDocumentsDirectory
        try indexData.write(to: local.appendingPathComponent(indexFileName), options: [.atomic, .completeFileProtection])
        try metaData.write(to: local.appendingPathComponent(metaFileName), options: [.atomic, .completeFileProtection])

        if let cloud = DataStore.iCloudDocumentsDirectory {
            try? FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
            // Cloud writes use `.completeFileProtectionUnlessOpen` so the iCloud sync daemon can
            // upload while the device is locked, matching DataStore's cloud-write convention.
            try? indexData.write(to: cloud.appendingPathComponent(indexFileName), options: [.atomic, .completeFileProtectionUnlessOpen])
            try? metaData.write(to: cloud.appendingPathComponent(metaFileName), options: [.atomic, .completeFileProtectionUnlessOpen])
        }

        // Cleanup temp file
        try? FileManager.default.removeItem(at: tempFileURL)

        onProgress("Done — \(index.count) actionable variants indexed")
        return meta
    }

    // MARK: - Streaming Decompress + Index Build
    //
    // Decompresses gzip data in 64KB chunks, extracts lines from a rolling buffer,
    // and feeds each line to the index builder — never holding the full ~1GB TSV in memory.

    private static func streamDecompressAndBuildIndex(
        _ data: Data,
        onProgress: @Sendable @escaping (String) -> Void
    ) throws -> [String: ClinVarEntry] {
        // Parse gzip header to find the deflate stream start
        guard data.count > 18, data[0] == 0x1f, data[1] == 0x8b else { throw ClinVarError.parseError }

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
        let sourceSize = deflateData.count

        let chunkSize = 65536
        let srcBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceSize)
        defer { srcBuffer.deallocate() }
        deflateData.copyBytes(to: srcBuffer, count: sourceSize)

        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        let initStatus = compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else { throw ClinVarError.parseError }
        defer { compression_stream_destroy(streamPtr) }
        var stream = streamPtr.pointee

        stream.src_ptr = UnsafePointer(srcBuffer)
        stream.src_size = sourceSize

        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { dstBuffer.deallocate() }

        var index: [String: ClinVarEntry] = [:]
        var headerColumns: [String: Int] = [:]
        var lineCount = 0
        var leftover = ""

        onProgress("Filtering actionable variants...")

        repeat {
            stream.dst_ptr = dstBuffer
            stream.dst_size = chunkSize

            let status = compression_stream_process(&stream, stream.src_size == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)

            let have = chunkSize - stream.dst_size
            if have > 0 {
                let chunk = String(decoding: UnsafeBufferPointer(start: dstBuffer, count: have), as: UTF8.self)

                let text = leftover + chunk
                var lines = text.split(separator: "\n", omittingEmptySubsequences: false)

                // Last element is incomplete unless chunk ended with newline
                leftover = String(lines.removeLast())

                for line in lines {
                    lineCount += 1
                    processLine(String(line), lineCount: lineCount, headerColumns: &headerColumns, index: &index)

                    if lineCount % 500_000 == 0 {
                        onProgress("Processed \(lineCount / 1_000_000)M lines...")
                    }
                }
            }

            if status == COMPRESSION_STATUS_END {
                // Process any remaining leftover
                if !leftover.isEmpty {
                    lineCount += 1
                    processLine(leftover, lineCount: lineCount, headerColumns: &headerColumns, index: &index)
                }
                break
            }
            if status == COMPRESSION_STATUS_ERROR { throw ClinVarError.parseError }
        } while stream.src_size > 0 || stream.dst_size == 0

        return index
    }

    // MARK: - Process Single TSV Line

    private static func processLine(
        _ line: String,
        lineCount: Int,
        headerColumns: inout [String: Int],
        index: inout [String: ClinVarEntry]
    ) {
        // Parse header
        if lineCount == 1 {
            let headerLine = line.hasPrefix("#") ? String(line.dropFirst()) : line
            for (i, col) in headerLine.split(separator: "\t").enumerated() {
                headerColumns[col.trimmingCharacters(in: .whitespaces)] = i
            }
            return
        }

        let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map { String($0) }

        guard let rsCol = headerColumns["RS# (dbSNP)"],
              rsCol < cols.count else { return }

        let rawRsid = cols[rsCol].trimmingCharacters(in: .whitespaces)
        if rawRsid.isEmpty || rawRsid == "-1" || rawRsid == "-" { return }
        let rsid = rawRsid.hasPrefix("rs") ? rawRsid : "rs\(rawRsid)"

        // Must be single nucleotide variant
        guard let typeCol = headerColumns["Type"],
              typeCol < cols.count,
              cols[typeCol].trimmingCharacters(in: .whitespaces).lowercased() == "single nucleotide variant" else { return }

        // Must be actionable significance
        guard let sigCol = headerColumns["ClinicalSignificance"],
              sigCol < cols.count else { return }
        let rawSig = cols[sigCol].trimmingCharacters(in: .whitespaces)
        let sigLower = rawSig.lowercased()
        let isActionable = actionableSignificance.contains(where: { sigLower.contains($0) })
        if !isActionable { return }

        // Assembly filter
        if let asmCol = headerColumns["Assembly"], asmCol < cols.count {
            let asm = cols[asmCol].trimmingCharacters(in: .whitespaces)
            if !asm.isEmpty && asm != "GRCh37" && asm != "GRCh38" { return }
        }

        // Origin filter
        if let origCol = headerColumns["Origin"], origCol < cols.count {
            let origin = cols[origCol].trimmingCharacters(in: .whitespaces)
            if !origin.isEmpty && !origin.contains("germline") && origin != "not provided" { return }
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
            if !newIsSevere && existingIsSevere { return }
            if stars < existing.reviewStars && !newIsSevere { return }
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

    // MARK: - Delete

    static func deleteClinVar() {
        let local = DataStore.localDocumentsDirectory
        try? FileManager.default.removeItem(at: local.appendingPathComponent(indexFileName))
        try? FileManager.default.removeItem(at: local.appendingPathComponent(metaFileName))
        if let cloud = DataStore.iCloudDocumentsDirectory {
            try? FileManager.default.removeItem(at: cloud.appendingPathComponent(indexFileName))
            try? FileManager.default.removeItem(at: cloud.appendingPathComponent(metaFileName))
        }
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
