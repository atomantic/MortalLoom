import Foundation
import os

extension Notification.Name {
    static let dataDidSync = Notification.Name("dataDidSync")
    static let dataStoreNeedsRecovery = Notification.Name("dataStoreNeedsRecovery")
    /// Posted (at most once per launch) when the ubiquity container *resolves to
    /// a URL* but it cannot safely accept writes. A previously loaded store
    /// can preserve edits locally if the container is unreachable. If the
    /// daemon instead reports stale data, leave both copies alone until it
    /// catches up. Surface a one-time toast rather than failing silently. Note this does
    /// NOT fire when iCloud is simply not configured — a signed-out account
    /// usually yields a nil container URL, which is a supported local-only mode,
    /// not an error worth toasting on every launch.
    static let iCloudWriteUnavailable = Notification.Name("iCloudWriteUnavailable")
    static let iCloudWriteDeferred = Notification.Name("iCloudWriteDeferred")
}

enum CloudConfig {
    static let containerID = "iCloud.net.shadowpuppet.MeatSpaceTracker"
}

private let logger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "DataStore")

extension FileManager {
    /// Modification date of the file at `url`, or nil if it can't be read.
    /// Centralizes the `attributesOfItem(...)[.modificationDate] as? Date`
    /// dance so the fragile cast lives in exactly one place.
    func modificationDate(at url: URL) -> Date? {
        try? attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// Returns the cloud URL if it exists and is newer than the local URL, otherwise the local URL.
    func newerOf(cloud: URL?, local: URL) -> URL {
        guard let cloud, fileExists(atPath: cloud.path) else { return local }
        let cloudDate = modificationDate(at: cloud) ?? .distantPast
        let localDate = modificationDate(at: local) ?? .distantPast
        return cloudDate >= localDate ? cloud : local
    }
}

actor DataStore {
    static let shared = DataStore()

    // Isolated URLs let tests exercise the real load/save paths without using
    // the app sandbox or its iCloud account.
    private let fixtureURLs: (local: URL, cloud: URL?)?
    private let fixtureCloudStatus: (@Sendable () -> CloudStatus)?

    enum CloudStatus: Sendable {
        case current, downloaded, notDownloaded, conflicted, uploading
    }

    init(fixtureURLs: (local: URL, cloud: URL?)? = nil,
         fixtureCloudStatus: (@Sendable () -> CloudStatus)? = nil) {
        self.fixtureURLs = fixtureURLs
        self.fixtureCloudStatus = fixtureCloudStatus
        guard fixtureURLs == nil else { return }
        // The resolved ubiquity-container URL and the reachability probe are
        // cached for the session (see `cachedUbiquityURL` / `isICloudReachable`).
        // Those caches are only valid for the *current* iCloud identity, so drop
        // them when the user signs in/out or switches accounts mid-session —
        // otherwise we'd keep returning a stale container URL and skip resolving
        // the new (or now-absent) one (#31).
        NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.invalidateICloudCaches() }
        }
    }

    /// Reset the cached iCloud container URL + reachability so the next access
    /// re-resolves for the current iCloud identity.
    private func invalidateICloudCaches() {
        cachedUbiquityURL = nil
        cloudBaseline = nil
        lastPublishedCloudBytes = nil
        isICloudReachable = nil
        didWarnICloudUnavailable = false
    }

    private var data: AppData = .empty
    private var loaded = false
    private var needsRecovery = false
    // Exact bytes of the cloud snapshot incorporated into the current state.
    // A timestamp can stay the same across different iCloud revisions.
    private var cloudBaseline: CloudRevision?
    private var lastPublishedCloudBytes: Data?
    private var waitingForCloud = false

    private enum CloudRevision: Equatable {
        case missing, present(Data)
    }

    enum Startup: Sendable {
        case ready(AppData)
        case needsRecovery
    }

    private enum FileRead {
        case missing
        case readable(AppData, Data)
        case waiting
        case unavailable
    }
    /// When true, save() keeps data in memory only and NEVER writes to local
    /// or iCloud. Used by -sample-data mode so fake screenshot data cannot
    /// overwrite a real user's iCloud container. Set once at app launch via
    /// enableSampleDataMode(); there is no way to turn it back off.
    private var sampleDataMode = false

    /// Caches a *confirmed-reachable* iCloud container so the probe runs once,
    /// not on every save. `nil` until a write probes it; set to `true` only when
    /// the container's Documents dir can be created and listed. A failed probe
    /// deliberately leaves this `nil` so a later save re-probes — the container
    /// is often unreachable for a few seconds at first launch (daemon still
    /// provisioning) and we don't want to disable iCloud for the whole session
    /// over a transient early miss.
    ///
    /// `url(forUbiquityContainerIdentifier:)` returning non-nil only proves the
    /// entitlement is configured, NOT that the container is reachable — hence the
    /// real directory-listing probe. We probe *reachability* (create + list), not
    /// literal writability; the actual `write(to:)` below still has its own catch,
    /// so a directory that lists but rejects the write is still handled there.
    private var isICloudReachable: Bool?
    /// Guards `iCloudWriteUnavailable` so the failure toast fires at most once
    /// per launch instead of on every save while iCloud stays unreachable.
    private var didWarnICloudUnavailable = false

    /// Debug-only: switch this store into in-memory mode so writes don't
    /// touch disk or iCloud. Irreversible for the process lifetime.
    func enableSampleDataMode() {
        sampleDataMode = true
    }

    /// Debug-only: replace the in-memory data without persisting. Paired with
    /// enableSampleDataMode() for the screenshot-capture flow.
    ///
    /// Posts `.dataDidSync` + `.profileDidChange` after replacing so any
    /// views that already called `getData()` and cached an empty result
    /// will refresh. Without this, `-sample-data` races OverviewView's
    /// first `loadData()` and the user sees the empty-state Overview
    /// even though sample data is loaded.
    func setInMemory(_ newData: AppData) {
        data = newData
        loaded = true
        Task { @MainActor in
            NotificationCenter.default.post(name: .dataDidSync, object: nil)
            NotificationCenter.default.post(name: .profileDidChange, object: nil)
        }
    }

    // MARK: - Shared path helpers (used by services to avoid duplicating path logic)

    /// The app's local Documents directory. Services that store their own files
    /// (e.g. ClinVarService) use this instead of resolving the path themselves.
    nonisolated static var localDocumentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// The iCloud ubiquity container's Documents directory, or nil when iCloud
    /// is not configured.
    ///
    /// Calls `url(forUbiquityContainerIdentifier:)` on every access (the
    /// session-level `cachedUbiquityURL` is actor-isolated and unreachable from
    /// a `nonisolated static`). Callers that perform multiple accesses in a
    /// single operation should snapshot the value once:
    /// `let cloud = DataStore.iCloudDocumentsDirectory` and reuse `cloud`.
    nonisolated static var iCloudDocumentsDirectory: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: CloudConfig.containerID)?
            .appendingPathComponent("Documents")
    }

    // File locations
    private var localURL: URL {
        fixtureURLs?.local ?? Self.localDocumentsDirectory.appendingPathComponent("MortalLoom.json")
    }

    // Resolving the ubiquity container (`url(forUbiquityContainerIdentifier:)`)
    // hits the iCloud daemon and is documented as slow — it was re-resolved on
    // every read/write access (#31). Cache the resolved container URL once.
    // Only a NON-nil result is cached: early in launch (before the iCloud
    // account loads) it can return nil, and we must keep re-resolving until the
    // container actually appears rather than latching nil for the session.
    private var cachedUbiquityURL: URL?
    private var ubiquityContainerURL: URL? {
        if let cachedUbiquityURL { return cachedUbiquityURL }
        guard let url = FileManager.default.url(forUbiquityContainerIdentifier: CloudConfig.containerID) else {
            return nil
        }
        cachedUbiquityURL = url
        return url
    }

    private var iCloudURL: URL? {
        if let fixtureURLs { return fixtureURLs.cloud }
        return ubiquityContainerURL?.appendingPathComponent("Documents/MortalLoom.json")
    }

    private var localGenomeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("genome-raw.txt")
    }

    private var iCloudGenomeURL: URL? {
        ubiquityContainerURL?.appendingPathComponent("Documents/genome-raw.txt")
    }

    /// Timestamp formatter for backup filenames, cached to avoid allocating a
    /// `DateFormatter` (expensive) on every `backupCurrentFile` call (#31).
    private static let backupStampFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return fmt
    }()

    /// Rolling backups of the main data file. Written before destructive
    /// operations (reset, import) so we always have an undo path. Lives in
    /// the sandbox so it survives reboots but never leaks outside the app.
    private var backupsDirectory: URL {
        localURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
    }

    /// Maximum number of rolling backups to keep. Older backups beyond this
    /// count are deleted on each new backup.
    private let maxBackups = 10

    /// Copy the current local data file into backups/ with a timestamped
    /// filename. Call this before any destructive mutation (reset, import,
    /// bulk replace). Prunes to the last `maxBackups` entries.
    @discardableResult
    func backupCurrentFile(reason: String) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: localURL.path) else {
            logger.info("💾 backup skipped — no local file yet (\(reason, privacy: .public))")
            return nil
        }

        do {
            try fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("💾 backup dir create failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }

        let stamp = Self.backupStampFormatter.string(from: Date())
        let dest = backupsDirectory.appendingPathComponent("MortalLoom-\(stamp).\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))-\(reason).json")

        do {
            try fm.copyItem(at: localURL, to: dest)
            logger.info("💾 pre-\(reason, privacy: .public) backup: \(dest.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("💾 backup copy failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }

        pruneBackups()
        return dest
    }

    /// Delete oldest backups so at most `maxBackups` remain.
    private func pruneBackups() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = urls.sorted { lhs, rhs in
            let ld = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rd = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ld > rd // newest first
        }

        guard sorted.count > maxBackups else { return }
        for url in sorted[maxBackups...] {
            try? fm.removeItem(at: url)
            logger.info("💾 pruned old backup \(url.lastPathComponent, privacy: .public)")
        }
    }

    /// List current backups (most recent first). Used by the Restore from
    /// Backup UI in Settings.
    func listBackups() -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.sorted { lhs, rhs in
            let ld = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rd = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ld > rd
        }
    }

    /// Restore the store from a backup file. Before applying the backup we
    /// snapshot the current state (reason "pre-restore") so the restore
    /// itself is reversible — a user who picks the wrong backup can roll
    /// back one more step. Returns true on success.
    @discardableResult
    func restoreFromBackup(_ url: URL) -> Bool {
        guard let fileData = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppData.self, from: fileData) else {
            logger.error("💾 restore failed to decode backup at \(url.lastPathComponent, privacy: .public)")
            return false
        }

        // Snapshot the current state before overwriting so the restore is
        // itself reversible. Uses a different "reason" so the user can see
        // which rolling backup was the pre-restore snapshot.
        guard save(decoded, replacementBackupReason: "pre-restore") else { return false }
        logger.info("💾 restored from backup \(url.lastPathComponent, privacy: .public) (\(decoded.alcoholDrinks.count, privacy: .private) drinks, \(decoded.nicotineEntries.count, privacy: .private) nic)")
        return true
    }

    private func cloudStatus(at resourceURL: URL) throws -> CloudStatus {
        if let fixtureURLs {
            // Plain fixture files have no ubiquitous resource attributes.
            return fixtureURLs.cloud == nil ? .current : (fixtureCloudStatus?() ?? .current)
        }
        var url = resourceURL
        url.removeAllCachedResourceValues()
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemHasUnresolvedConflictsKey,
                .ubiquitousItemIsUploadingKey
            ])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .current
        }
        switch values.ubiquitousItemDownloadingStatus {
        case .downloaded: return .downloaded
        case .notDownloaded: return .notDownloaded
        default: break
        }
        if values.ubiquitousItemHasUnresolvedConflicts == true
            || !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty {
            return .conflicted
        }
        if values.ubiquitousItemIsUploading == true { return .uploading }
        // A real ubiquitous item with unknown freshness is not writable.
        if values.ubiquitousItemDownloadingStatus == .current { return .current }
        let exists = FileManager.default.fileExists(atPath: url.path)
        return values.isUbiquitousItem == true || exists ? .notDownloaded : .current
    }

    private func readStoreFile(_ url: URL, cloud: Bool = false) -> FileRead {
        do {
            let status = cloud ? try cloudStatus(at: url) : .current
            if cloud {
                switch status {
                case .current, .uploading: break
                case .downloaded, .notDownloaded:
                    if fixtureURLs == nil { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
                    return .waiting
                case .conflicted:
                    return .unavailable
                }
            }
            let bytes = try Data(contentsOf: url)
            // Rapid edits can build on exactly the revision this actor just
            // published. An upload inherited from before launch (or another
            // writer) must settle before this process edits the cloud file.
            if status == .uploading && bytes != lastPublishedCloudBytes { return .waiting }
            return .readable(try JSONDecoder().decode(AppData.self, from: bytes), bytes)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain,
               error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError {
                return .missing
            }
            logger.error("💾 Could not read MortalLoom data (\(error.domain, privacy: .public):\(error.code))")
            return .unavailable
        }
    }

    private func blockWritesForRecovery() {
        guard !needsRecovery else { return }
        needsRecovery = true
        if fixtureURLs == nil {
            Task { @MainActor in
                NotificationCenter.default.post(name: .dataStoreNeedsRecovery, object: nil)
            }
        }
    }

    // Inspect the cloud copy even when a readable local file contains some data.
    // HealthKit-only data is valid JSON and counts as user data; neither fact
    // establishes that iCloud has downloaded the latest version of the file.
    func load() -> AppData {
        if loaded || needsRecovery { return data }
        waitingForCloud = false
        let local = readStoreFile(localURL)
        guard let cloudURL = iCloudURL else {
            if fixtureURLs == nil && FileManager.default.ubiquityIdentityToken != nil {
                waitingForCloud = true
                return data
            }
            acceptLocal(local)
            return data
        }

        switch readStoreFile(cloudURL, cloud: true) {
        case .readable(let remote, let bytes):
            if case .unavailable = local {
                blockWritesForRecovery()
                return data
            }
            // Preserve unsynced local-only edits on the newer local copy using
            // the same reconciliation as the watcher (remote wins collisions).
            if case .readable(let localData, let localBytes) = local, localBytes != bytes,
               (FileManager.default.modificationDate(at: localURL) ?? .distantPast)
                 > (FileManager.default.modificationDate(at: cloudURL) ?? .distantPast) {
                data = localData.merged(with: remote)
            } else {
                data = remote
            }
            cloudBaseline = .present(bytes)
            loaded = true
        case .missing:
            // For a resolved but not yet reachable container, absence is not
            // proof that a fresh iCloud store may be created.
            guard ensureICloudReachable(cloudURL) else {
                waitingForCloud = true
                return data
            }
            cloudBaseline = .missing
            acceptLocal(local)
        case .waiting:
            waitingForCloud = true
        case .unavailable:
            blockWritesForRecovery()
        }
        return data
    }

    private func acceptLocal(_ local: FileRead) {
        switch local {
        case .readable(let decoded, _): data = decoded
        case .missing: data = .empty
        case .waiting, .unavailable:
            blockWritesForRecovery()
            return
        }
        loaded = true
    }

    func ensureLoaded(retry: Bool = false) async -> Startup {
        if retry && needsRecovery {
            needsRecovery = false
            loaded = false
            cloudBaseline = nil
        }
        _ = load()
        if waitingForCloud && !needsRecovery {
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(0.5))
                if Task.isCancelled { break }
                _ = load()
                if loaded || needsRecovery { break }
            }
            if !loaded { blockWritesForRecovery() }
        }
        return needsRecovery ? .needsRecovery : .ready(data)
    }

    /// Pull changed iCloud bytes into the local snapshot without publishing the
    /// merge back, even when the download kept an equal or older timestamp.
    func reloadIfNeeded() -> Bool {
        if sampleDataMode || needsRecovery { return false }
        let wasLoaded = loaded
        _ = load()
        guard !needsRecovery, let cloudURL = iCloudURL else { return false }
        switch readStoreFile(cloudURL, cloud: true) {
        case .readable(let remote, let bytes):
            if cloudBaseline == .present(bytes) { return !wasLoaded && loaded }
            reconcileRemote(remote, bytes: bytes)
            return true
        case .missing, .waiting:
            return false
        case .unavailable:
            blockWritesForRecovery()
            return false
        }
    }

    private func reconcileRemote(_ remote: AppData, bytes: Data) {
        let merged = data.merged(with: remote)
        do {
            try encode(merged).write(to: localURL, options: [.atomic, .completeFileProtection])
        } catch {
            logger.error("💾 Failed to write local data in reload: \(error.localizedDescription, privacy: .private)")
        }
        data = merged
        cloudBaseline = .present(bytes)
    }

    private func encode(_ value: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    @discardableResult
    func save(_ newData: AppData) -> Bool { save(newData, replacementBackupReason: nil) }

    private func save(_ newData: AppData, replacementBackupReason: String?,
                      notifyIfReconciled: Bool = true) -> Bool {
        if sampleDataMode {
            data = newData
            return true
        }

        _ = load()
        guard loaded, !needsRecovery else { return false }
        if let reason = replacementBackupReason,
           FileManager.default.fileExists(atPath: localURL.path),
           backupCurrentFile(reason: reason) == nil { return false }
        let encoded: Data
        do {
            encoded = try encode(newData)
        } catch {
            logger.error("💾 Failed to encode data — save aborted: \(error.localizedDescription, privacy: .private)")
            return false
        }

        // Re-check and write under the same file coordination claim. A remote
        // write between the mutator's read and this claim must not be replaced
        // by a whole local snapshot, even if the new cloud file decodes cleanly.
        var savedLocally = false
        var savedToCloud = false
        let cloudURL = iCloudURL
        if let cloudURL {
            if ensureICloudReachable(cloudURL) {
                let coordinator = NSFileCoordinator()
                var error: NSError?
                coordinator.coordinate(writingItemAt: cloudURL, options: [], error: &error) { url in
                    switch readStoreFile(url, cloud: true) {
                    case .readable(let remote, let bytes):
                        guard cloudBaseline == .present(bytes) else {
                            reconcileRemote(remote, bytes: bytes)
                            if notifyIfReconciled { noteICloudDeferred() }
                            if fixtureURLs == nil {
                                Task { @MainActor in
                                    NotificationCenter.default.post(name: .dataDidSync, object: nil)
                                    NotificationCenter.default.post(name: .profileDidChange, object: nil)
                                }
                            }
                            return
                        }
                        // Preserve the actual cloud revision as well as the
                        // local file before an explicit replacement.
                        if let reason = replacementBackupReason,
                           !backupCloudBytes(bytes, reason: reason) { return }
                    case .missing:
                        guard cloudBaseline == .missing else {
                            blockWritesForRecovery()
                            return
                        }
                    case .waiting:
                        noteICloudDeferred()
                        return
                    case .unavailable:
                        blockWritesForRecovery()
                        return
                    }
                    guard writeLocal(encoded) else { return }
                    savedLocally = true
                    do {
                        try encoded.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
                        cloudBaseline = .present(encoded)
                        lastPublishedCloudBytes = encoded
                        savedToCloud = true
                    } catch {
                        isICloudReachable = nil
                        noteICloudUnavailable()
                    }
                }
                if error != nil { noteICloudUnavailable() }
            } else if replacementBackupReason == nil && cloudBaseline != nil {
                // Previously loaded store, now offline. Keep the edit on this
                // device without changing the baseline or attempting a push.
                savedLocally = writeLocal(encoded)
            }
        } else if fixtureURLs != nil || FileManager.default.ubiquityIdentityToken == nil {
            savedLocally = writeLocal(encoded)
        } else if replacementBackupReason == nil && cloudBaseline != nil {
            noteICloudUnavailable()
            savedLocally = writeLocal(encoded)
        }
        guard savedLocally else { return false }
        data = newData

        if replacementBackupReason != nil { pruneBackups() }
        if fixtureURLs == nil {
            Task { @MainActor in ICloudMonitor.shared.markLocalWrite() }
            Task.detached { WidgetBridge.update(data: newData) }
        }
        // The UI cannot claim a destructive import/reset completed when
        // only the local side of a configured cloud replacement was saved.
        return replacementBackupReason == nil || cloudURL == nil || savedToCloud
    }

    private func writeLocal(_ bytes: Data) -> Bool {
        do {
            try bytes.write(to: localURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            logger.error("💾 Failed to write local data: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private func backupCloudBytes(_ bytes: Data, reason: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let path = backupsDirectory.appendingPathComponent("MortalLoom-\(Self.backupStampFormatter.string(from: Date())).\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))-cloud-\(reason).json")
            try bytes.write(to: path, options: [.completeFileProtection, .withoutOverwriting])
            return true
        } catch {
            logger.error("💾 Could not preserve the existing iCloud data before replacement")
            return false
        }
    }

    // Convenience accessors
    func getData() -> AppData { load() }

    /// Atomically read-modify-write the store in a single actor hop.
    ///
    /// Unlike a `getData()` … (await) … `save()` pair — which suspends
    /// between the read and the write, letting a concurrent caller's stale
    /// snapshot clobber this one's changes (issue #28) — the closure here runs
    /// with no suspension point, so the actor serializes whole read-modify-write
    /// cycles. Callers that must `await` external work (e.g. HealthKit fetches)
    /// should do that work FIRST, then apply every resulting change inside a
    /// single `mutate`.
    ///
    /// The closure is a pure change to the supplied copy. If a newer remote
    /// revision arrived, retry once on the reconciled data, never on stale
    /// bytes. A refused commit returns nil, so a caller cannot report success.
    @discardableResult
    func mutate<R: Sendable>(_ body: @Sendable (inout AppData) -> (persist: Bool, result: R)) -> R? {
        for _ in 0..<2 {
            var draft = load()
            guard (loaded || sampleDataMode), !needsRecovery else { return nil }
            let baseline = cloudBaseline
            let (persist, result) = body(&draft)
            if !persist || save(draft, replacementBackupReason: nil, notifyIfReconciled: false) { return result }
            if cloudBaseline == baseline { return nil }
        }
        noteICloudDeferred()
        return nil
    }

    func updateProfile(_ profile: HealthProfile) {
        var d = load()
        d.profile = profile
        save(d)
    }

    func updateCountdownMode(_ mode: CountdownMode) {
        var d = load()
        d.profile.countdownMode = mode
        save(d)
    }

    func addAlcoholDrink(_ drink: AlcoholDrink) {
        var d = load()
        d.alcoholDrinks.append(drink)
        save(d)
    }

    func removeAlcoholDrink(id: UUID) {
        var d = load()
        d.alcoholDrinks.removeAll { $0.id == id }
        save(d)
    }

    func updateAlcoholDrink(_ drink: AlcoholDrink) {
        var d = load()
        if let idx = d.alcoholDrinks.firstIndex(where: { $0.id == drink.id }) {
            d.alcoholDrinks[idx] = drink
            save(d)
        }
    }

    func setAlcoholPresets(_ presets: [AlcoholPreset]) {
        var d = load()
        d.alcoholPresets = presets
        save(d)
    }

    func addNicotineEntry(_ entry: NicotineEntry) {
        var d = load()
        d.nicotineEntries.append(entry)
        save(d)
    }

    func removeNicotineEntry(id: UUID) {
        var d = load()
        d.nicotineEntries.removeAll { $0.id == id }
        save(d)
    }

    func updateNicotineEntry(_ entry: NicotineEntry) {
        var d = load()
        if let idx = d.nicotineEntries.firstIndex(where: { $0.id == entry.id }) {
            d.nicotineEntries[idx] = entry
            save(d)
        }
    }

    func setNicotinePresets(_ presets: [NicotinePreset]) {
        var d = load()
        d.nicotinePresets = presets
        save(d)
    }

    func addSaunaSession(_ session: SaunaSession) {
        var d = load()
        d.saunaSessions.append(session)
        save(d)
    }

    func removeSaunaSession(id: UUID) {
        var d = load()
        d.saunaSessions.removeAll { $0.id == id }
        save(d)
    }

    func updateSaunaSession(_ session: SaunaSession) {
        var d = load()
        if let idx = d.saunaSessions.firstIndex(where: { $0.id == session.id }) {
            d.saunaSessions[idx] = session
            save(d)
        }
    }

    func setSaunaPresets(_ presets: [SaunaPreset]) {
        var d = load()
        d.saunaPresets = presets
        save(d)
    }

    func addBloodTest(_ test: BloodTest) {
        var d = load()
        d.bloodTests.append(test)
        save(d)
    }

    func removeBloodTest(id: UUID) {
        var d = load()
        d.bloodTests.removeAll { $0.id == id }
        save(d)
    }

    func updateBloodTest(_ test: BloodTest) {
        var d = load()
        if let idx = d.bloodTests.firstIndex(where: { $0.id == test.id }) {
            d.bloodTests[idx] = test
            save(d)
        }
    }

    func addBloodDonation(_ donation: BloodDonation) {
        var d = load()
        d.bloodDonations.append(donation)
        save(d)
    }

    func removeBloodDonation(id: UUID) {
        var d = load()
        d.bloodDonations.removeAll { $0.id == id }
        save(d)
    }

    func updateBloodDonation(_ donation: BloodDonation) {
        var d = load()
        if let idx = d.bloodDonations.firstIndex(where: { $0.id == donation.id }) {
            d.bloodDonations[idx] = donation
            save(d)
        }
    }

    func addEyeExam(_ exam: EyeExam) {
        var d = load()
        d.eyeExams.append(exam)
        save(d)
    }

    func removeEyeExam(id: UUID) {
        var d = load()
        d.eyeExams.removeAll { $0.id == id }
        save(d)
    }

    func updateEyeExam(_ exam: EyeExam) {
        var d = load()
        if let idx = d.eyeExams.firstIndex(where: { $0.id == exam.id }) {
            d.eyeExams[idx] = exam
            save(d)
        }
    }

    func addBodyEntry(_ entry: BodyEntry) {
        var d = load()
        d.bodyEntries.append(entry)
        save(d)
    }

    func removeBodyEntry(id: UUID) {
        var d = load()
        d.bodyEntries.removeAll { $0.id == id }
        save(d)
    }

    func addEpigeneticTest(_ test: EpigeneticTest) {
        var d = load()
        d.epigeneticTests.append(test)
        save(d)
    }

    func removeEpigeneticTest(id: UUID) {
        var d = load()
        d.epigeneticTests.removeAll { $0.id == id }
        save(d)
    }

    /// Upsert a health metric entry — merges fields into existing entry for the same date.
    func upsertHealthMetric(_ entry: HealthMetricEntry) {
        var d = load()
        if let idx = d.healthMetrics.firstIndex(where: { $0.date == entry.date }) {
            d.healthMetrics[idx].mergeFields(from: entry)
        } else {
            d.healthMetrics.append(entry)
        }
        save(d)
    }

    /// Bulk upsert health metrics (used by HealthKitSync).
    func upsertHealthMetrics(_ entries: [HealthMetricEntry]) {
        guard !entries.isEmpty else { return }
        var d = load()
        var byDate: [String: Int] = [:]
        for (idx, m) in d.healthMetrics.enumerated() {
            byDate[m.date] = idx
        }
        for entry in entries {
            if let idx = byDate[entry.date] {
                d.healthMetrics[idx].mergeFields(from: entry)
            } else {
                byDate[entry.date] = d.healthMetrics.count
                d.healthMetrics.append(entry)
            }
        }
        save(d)
    }

    // MARK: - Goals

    func addGoal(_ goal: Goal) {
        var d = load()
        d.goals.append(goal)
        save(d)
    }

    func updateGoal(_ goal: Goal) {
        var d = load()
        if let idx = d.goals.firstIndex(where: { $0.id == goal.id }) {
            d.goals[idx] = goal
            save(d)
        }
    }

    func saveGenomeScanRecord(_ record: GenomeScanRecord) {
        var d = load()
        d.genomeScanRecord = record
        save(d)
    }

    func removeGoal(id: UUID) {
        var d = load()
        d.goals.removeAll { $0.id == id }
        save(d)
    }

    // MARK: - Habits

    func addHabit(_ habit: Habit) {
        var d = load()
        d.habits.append(habit)
        save(d)
    }

    func updateHabit(_ habit: Habit) {
        var d = load()
        if let idx = d.habits.firstIndex(where: { $0.id == habit.id }) {
            d.habits[idx] = habit
            save(d)
        }
    }

    func removeHabit(id: UUID) {
        var d = load()
        d.habits.removeAll { $0.id == id }
        save(d)
    }

    /// Append a completion to a habit. If the habit doesn't exist, this is a no-op.
    func logHabitCompletion(habitId: UUID, completion: HabitCompletion) {
        var d = load()
        guard let idx = d.habits.firstIndex(where: { $0.id == habitId }) else { return }
        d.habits[idx].completions.append(completion)
        save(d)
    }

    /// Remove a single completion by id from a habit. Used for undo.
    func removeHabitCompletion(habitId: UUID, completionId: UUID) {
        var d = load()
        guard let idx = d.habits.firstIndex(where: { $0.id == habitId }) else { return }
        d.habits[idx].completions.removeAll { $0.id == completionId }
        save(d)
    }

    // MARK: - Genome Action State

    /// Set or update the state for a single genome action. The key combines
    /// the finding's rsid (or pseudo-rsid for ClinVar/APOE) with the action ID.
    func setGenomeActionStatus(
        rsid: String,
        actionId: String,
        status: GenomeActionStatus,
        linkedHabitId: UUID? = nil,
        linkedGoalId: UUID? = nil,
        linkedVisitNoteId: UUID? = nil,
        note: String? = nil
    ) {
        var d = load()
        let key = GenomeActionState.key(rsid: rsid, actionId: actionId)
        let existing = d.genomeActionStates[key]
        d.genomeActionStates[key] = GenomeActionState(
            key: key,
            status: status,
            updatedAt: DateFormatting.todayString(),
            note: note ?? existing?.note,
            linkedGoalId: linkedGoalId ?? existing?.linkedGoalId,
            linkedHabitId: linkedHabitId ?? existing?.linkedHabitId,
            linkedVisitNoteId: linkedVisitNoteId ?? existing?.linkedVisitNoteId
        )
        save(d)
    }

    /// Add a doctor visit note. When `autoDiscussPending` is true (the default,
    /// used by the detail sheet's quick "add note" form), any pending actions on
    /// the same finding are flipped to `discussed` and stamped with
    /// `linkedVisitNoteId` so the genome detail view can navigate from the action
    /// back to the conversation. Visit Mode passes `false`: it has an explicit
    /// per-action checklist, so the checkbox toggles — not the act of saving a
    /// note — are the source of truth for what was discussed, and a deliberately
    /// unchecked (pending) action must not be auto-completed.
    func addVisitNote(_ note: VisitNote, autoDiscussPending: Bool = true) {
        var d = load()
        d.genomeVisitNotes.append(note)
        if autoDiscussPending {
            let prefix = "\(note.findingKey):"
            for (key, state) in d.genomeActionStates where key.hasPrefix(prefix) && state.status == .pending {
                d.genomeActionStates[key] = GenomeActionState(
                    key: key,
                    status: .discussed,
                    updatedAt: DateFormatting.todayString(),
                    note: state.note,
                    linkedGoalId: state.linkedGoalId,
                    linkedHabitId: state.linkedHabitId,
                    linkedVisitNoteId: note.id
                )
            }
        }
        save(d)
    }

    /// Replace an existing visit note (same `id`).
    func updateVisitNote(_ note: VisitNote) {
        var d = load()
        if let idx = d.genomeVisitNotes.firstIndex(where: { $0.id == note.id }) {
            d.genomeVisitNotes[idx] = note
            save(d)
        }
    }

    func removeVisitNote(id: UUID) {
        var d = load()
        d.genomeVisitNotes.removeAll { $0.id == id }
        save(d)
    }

    // MARK: - Genome File

    func saveGenomeFile(_ content: String) {
        guard let data = content.data(using: .utf8) else { return }
        // Genome data is the most sensitive payload in the app — full data
        // protection while the device is locked.
        do {
            try data.write(to: localGenomeURL, options: [.atomic, .completeFileProtection])
        } catch {
            logger.error("🧬 Failed to write local genome file: \(error.localizedDescription, privacy: .private)")
        }
        if let cloudURL = iCloudGenomeURL, ensureICloudReachable(cloudURL) {
            do {
                try data.write(to: cloudURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            } catch {
                logger.error("🧬 Failed to write iCloud genome file: \(error.localizedDescription, privacy: .private)")
                noteICloudUnavailable()
            }
        }
    }

    func loadGenomeFile() -> String? {
        let url = bestGenomeURL()
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return nil }
        return content
    }

    func deleteGenomeFile() {
        try? FileManager.default.removeItem(at: localGenomeURL)
        if let url = iCloudGenomeURL { try? FileManager.default.removeItem(at: url) }
    }

    private func bestGenomeURL() -> URL {
        FileManager.default.newerOf(cloud: iCloudGenomeURL, local: localGenomeURL)
    }

    func exportData() -> Data? {
        let snapshot = load()
        guard !needsRecovery else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(snapshot)
    }

    func importData(from jsonData: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode(AppData.self, from: jsonData) else { return false }
        // Snapshot whatever is currently on disk BEFORE the import clobbers
        // it, so a bad import file can be undone.
        return save(imported, replacementBackupReason: "import")
    }

    func resetAllData() -> Bool {
        return save(.empty, replacementBackupReason: "reset")
    }

    /// Explicit recovery only. Do not let an ordinary save, reset, or
    /// HealthKit sync use this path. Validate the selected backup, then save
    /// the original raw bytes (including malformed JSON) before replacing it.
    func recoverFromBackup(_ backup: Data) -> Bool {
        guard needsRecovery, !sampleDataMode,
              let restored = try? JSONDecoder().decode(AppData.self, from: backup),
              restored.hasUserData else { return false }

        let cloudURL = iCloudURL
        let fm = FileManager.default
        let folder = localURL.deletingLastPathComponent()
            .appendingPathComponent("Recovery Backups", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            if let cloudURL, !ensureICloudReachable(cloudURL) { return false }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try preserveRecoveryCopy(at: localURL, in: folder, as: "Local.json")
            if let cloudURL {
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var writeError: Error?
                coordinator.coordinate(writingItemAt: cloudURL, options: [], error: &coordinationError) { url in
                    do {
                        switch try cloudStatus(at: url) {
                        case .downloaded, .notDownloaded, .uploading:
                            if fixtureURLs == nil { try? fm.startDownloadingUbiquitousItem(at: url) }
                            throw CocoaError(.fileReadUnknown)
                        case .current, .conflicted: break
                        }
                        try preserveRecoveryCopy(at: url, in: folder, as: "iCloud.json")
                        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
                        for (index, conflict) in conflicts.enumerated() {
                            let original = try Data(contentsOf: conflict.url)
                            try original.write(to: folder.appendingPathComponent("iCloud Conflict \(index + 1).json"),
                                               options: [.completeFileProtection, .withoutOverwriting])
                        }
                        try backup.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
                        try backup.write(to: localURL, options: [.atomic, .completeFileProtection])
                        for conflict in conflicts { conflict.isResolved = true }
                    } catch { writeError = error }
                }
                if let error = writeError ?? coordinationError { throw error }
            } else {
                try backup.write(to: localURL, options: [.atomic, .completeFileProtection])
            }
        } catch {
            logger.error("💾 Explicit recovery could not complete: \(error.localizedDescription, privacy: .private)")
            return false
        }
        needsRecovery = false
        loaded = false
        cloudBaseline = nil
        return true
    }

    private func preserveRecoveryCopy(at source: URL, in folder: URL, as name: String) throws {
        let downloadStatus = try? source.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if downloadStatus?.ubiquitousItemDownloadingStatus == .notDownloaded {
            try? FileManager.default.startDownloadingUbiquitousItem(at: source)
            throw CocoaError(.fileReadUnknown)
        }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: source)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return
        }
        try bytes.write(to: folder.appendingPathComponent(name), options: [.completeFileProtection, .withoutOverwriting])
    }

    // MARK: - Private

    /// Confirm the iCloud ubiquity container is actually reachable before we
    /// trust the iCloud write path. `url(forUbiquityContainerIdentifier:)`
    /// returning a non-nil URL only means the entitlement is configured — on an
    /// unsigned build or first launch before the daemon has provisioned the
    /// container, the directory create + a `contentsOfDirectory` probe still
    /// fail. We listing-probe (not `try?`) so a real error is seen, cache only a
    /// *successful* result, and on failure surface a one-time toast and fall back
    /// to the local-only copy `save()` already wrote.
    ///
    /// A failed probe is NOT cached: `isICloudReachable` stays `nil` so the next
    /// save re-probes. First-launch unreachability is usually transient (the
    /// daemon provisions the container a few seconds in), and caching `false`
    /// would strand the session with no iCloud copy even once it comes online.
    /// The repeat probe is cheap relative to a save and bounded to the offline
    /// path; `didWarnICloudUnavailable` still keeps the toast to one per launch.
    ///
    /// This proves *reachability*, not literal writability — `Documents` may
    /// legitimately not exist yet on a fresh container, so a successful
    /// `createDirectory` followed by a successful listing is the signal that the
    /// container is live. The actual `write(to:)` in the caller has its own catch,
    /// so a dir that lists but rejects the write is still surfaced there.
    private func ensureICloudReachable(_ cloudURL: URL) -> Bool {
        if isICloudReachable == true { return true }

        let dir = cloudURL.deletingLastPathComponent()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // The probe: a reachable container lists its Documents dir without
            // throwing. An unreachable one throws here (or at createDirectory).
            _ = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            isICloudReachable = true
            return true
        } catch {
            // Leave isICloudReachable nil so a later save re-probes once the
            // daemon comes online — see the property doc above.
            logger.error("☁️ iCloud container not reachable: \(error.localizedDescription, privacy: .private)")
            noteICloudUnavailable()
            return false
        }
    }

    /// Post the iCloud-unavailable notification at most once per launch. Hops to
    /// `@MainActor` like the other DataStore notifications since the UI observes it.
    private func noteICloudDeferred() {
        guard fixtureURLs == nil else { return }
        Task { @MainActor in
            NotificationCenter.default.post(name: .iCloudWriteDeferred, object: nil)
        }
    }

    private func noteICloudUnavailable() {
        guard fixtureURLs == nil, !didWarnICloudUnavailable else { return }
        didWarnICloudUnavailable = true
        Task { @MainActor in
            NotificationCenter.default.post(name: .iCloudWriteUnavailable, object: nil)
        }
    }
}
