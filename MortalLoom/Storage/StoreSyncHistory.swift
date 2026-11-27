import Foundation

/// Retained only within the app's local sandbox, never in the shared iCloud
/// directory. Files are complete, verified JSON snapshots, not summary counts.
struct StoreSyncHistory {
    let directory: URL
    let scope: String

    private var scopedDirectory: URL { directory.appendingPathComponent(scope, isDirectory: true) }
    private var baseline: URL { scopedDirectory.appendingPathComponent("LastVerifiedCloud.json") }
    private var previous: URL { scopedDirectory.appendingPathComponent("PreviousVerifiedCloud.json") }
    private var pending: URL { scopedDirectory.appendingPathComponent("PendingLocalRevision") }
    private var owner: URL { directory.appendingPathComponent("LocalCopyOwner") }

    func matchesLocalOwner() throws -> Bool {
        do { return try String(contentsOf: owner, encoding: .utf8) == scope }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return true }
    }

    func lastVerified() -> Data? { verified(at: baseline) }

    func rememberCloud(_ bytes: Data) throws {
        try createDirectory()
        if let current = lastVerified(), current != bytes {
            try write(current, to: previous)
        }
        try write(bytes, to: baseline)
        try write(Data(scope.utf8), to: owner)
    }

    func preserveCandidate(_ bytes: Data, as name: String) throws {
        try createDirectory()
        let dest = scopedDirectory.appendingPathComponent(name + "-" + SharedStoreDocument.signature(bytes) + ".json")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try write(bytes, to: dest)
        let candidates = try FileManager.default.contentsOfDirectory(
            at: scopedDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { $0.lastPathComponent.hasPrefix(name + "-") }.sorted { a, b in
            let stamp: (URL) -> Date = {
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            }
            return stamp(a) > stamp(b)
        }
        for stale in candidates.dropFirst(10) { try? FileManager.default.removeItem(at: stale) }
    }

    func snapshotURLs() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: scopedDirectory,
                                                        includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }
    }

    func isPendingLocal(_ bytes: Data) -> Bool {
        (try? String(contentsOf: pending, encoding: .utf8)) == SharedStoreDocument.signature(bytes)
    }

    func markPendingLocal(_ bytes: Data) throws {
        try createDirectory()
        try write(Data(SharedStoreDocument.signature(bytes).utf8), to: pending)
        try write(Data(scope.utf8), to: owner)
    }

    func clearPendingLocal() throws {
        do { try FileManager.default.removeItem(at: pending) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {}
    }

    private func verified(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url),
              (try? JSONDecoder().decode(AppData.self, from: data)) != nil else { return nil }
        return data
    }

    private func createDirectory() throws {
        try FileManager.default.createDirectory(at: scopedDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func write(_ bytes: Data, to url: URL) throws {
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard try Data(contentsOf: url) == bytes else { throw CocoaError(.fileWriteUnknown) }
    }
}
