import Foundation
import os

extension Notification.Name {
    static let dataDidSync = Notification.Name("dataDidSync")
    /// Posted (at most once per launch) when the ubiquity container *resolves to
    /// a URL* but its directory operations then fail — i.e. the entitlement is
    /// configured yet the container isn't actually reachable/writable (first
    /// launch before the daemon provisions it, an unsigned build, a transient
    /// daemon error). Data is still saved locally; the UI surfaces a one-time
    /// toast so this otherwise-silent failure isn't invisible. Note this does
    /// NOT fire when iCloud is simply not configured — a signed-out account
    /// usually yields a nil container URL, which is a supported local-only mode,
    /// not an error worth toasting on every launch.
    static let iCloudWriteUnavailable = Notification.Name("iCloudWriteUnavailable")
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

    init() {
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
        isICloudReachable = nil
        didWarnICloudUnavailable = false
    }

    private var data: AppData = .empty
    private var loaded = false
    private var lastSaveDate: Date = .distantPast
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
    /// is not configured. Resolves the container on every call — services should
    /// cache the result for the duration of a single operation if needed.
    nonisolated static var iCloudDocumentsDirectory: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: CloudConfig.containerID)?
            .appendingPathComponent("Documents")
    }

    // File locations
    private var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MortalLoom.json")
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
        ubiquityContainerURL?.appendingPathComponent("Documents/MortalLoom.json")
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
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups", isDirectory: true)
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
        let dest = backupsDirectory.appendingPathComponent("MortalLoom-\(stamp)-\(reason).json")

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
        backupCurrentFile(reason: "pre-restore")
        save(decoded)
        logger.info("💾 restored from backup \(url.lastPathComponent, privacy: .public) (\(decoded.alcoholDrinks.count, privacy: .private) drinks, \(decoded.nicotineEntries.count, privacy: .private) nic)")
        return true
    }

    // Load from best available source
    func load() -> AppData {
        if loaded { return data }

        let url = bestURL()
        if let fileData = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode(AppData.self, from: fileData) {
                data = decoded
                // Seed lastSaveDate with the loaded file's mtime so that
                // reloadIfNeeded() doesn't treat any subsequent iCloud change
                // as "newer" than our freshly-loaded state. Without this,
                // lastSaveDate stays at .distantPast and any iCloud push from
                // another device (even a stale one) unconditionally wins.
                if let mtime = FileManager.default.modificationDate(at: url) {
                    lastSaveDate = mtime
                }
                let drinkCount = self.data.alcoholDrinks.count
                let nicCount = self.data.nicotineEntries.count
                let saunaCount = self.data.saunaSessions.count
                logger.info("💾 loaded data from \(url.lastPathComponent, privacy: .public) (\(drinkCount, privacy: .private) drinks, \(nicCount, privacy: .private) nic, \(saunaCount, privacy: .private) sauna)")
            } else {
                logger.error("💾 failed to decode data from \(url.path, privacy: .private)")
            }
        } else {
            logger.info("💾 no data file found at \(url.path, privacy: .private)")
        }
        loaded = true
        return data
    }

    /// Ensure data is loaded, waiting for iCloud file download if needed.
    /// Call this before any sync that might write, to prevent overwriting
    /// cloud data that hasn't been downloaded yet.
    func ensureLoaded() async -> AppData {
        if loaded { return data }

        let result = load()

        // If we loaded empty data and iCloud is available, the cloud file
        // might not be downloaded yet. Trigger download and wait briefly.
        if !result.hasUserData, let cloudURL = iCloudURL {
            let fm = FileManager.default
            if !fm.fileExists(atPath: cloudURL.path) {
                logger.info("💾 no local user data, attempting iCloud download…")
                try? fm.startDownloadingUbiquitousItem(at: cloudURL)

                for _ in 0..<10 {
                    try? await Task.sleep(for: .seconds(0.5))
                    if fm.fileExists(atPath: cloudURL.path) {
                        if let fileData = try? Data(contentsOf: cloudURL),
                           let decoded = try? JSONDecoder().decode(AppData.self, from: fileData) {
                            data = decoded
                            // Record the cloud file's mod date so reloadIfNeeded()
                            // doesn't redundantly reload the same data.
                            lastSaveDate = fm.modificationDate(at: cloudURL) ?? Date()
                            let drinkCount = self.data.alcoholDrinks.count
                            let nicCount = self.data.nicotineEntries.count
                            logger.info("💾 loaded iCloud data after download (\(drinkCount, privacy: .private) drinks, \(nicCount, privacy: .private) nic)")
                            do {
                                try fileData.write(to: localURL, options: [.atomic, .completeFileProtection])
                            } catch {
                                logger.error("💾 failed to mirror iCloud data locally: \(error.localizedDescription, privacy: .private)")
                            }
                        }
                        break
                    }
                }
            }
        }

        return data
    }

    /// Reload from iCloud when it has a newer file. Instead of wholesale
    /// replacing our in-memory state with the remote file, this merges the
    /// remote file INTO the current state using `AppData.merged(with:)` —
    /// unioning UUID-keyed arrays, field-merging health metrics per date,
    /// and preserving non-default profile fields. The result is written
    /// back to the local file so subsequent launches start from the merged
    /// state.
    ///
    /// We deliberately do NOT push the merged state back to iCloud from
    /// this function to avoid a ping-pong feedback loop with other devices.
    /// The merged state will propagate to iCloud on the next user edit via
    /// `save(_:)`. Eventual convergence is fine for this use case.
    ///
    /// Returns true if the merge produced any change.
    func reloadIfNeeded() -> Bool {
        // Sample-data (screenshot) mode is in-memory only and must never read
        // from or write to iCloud/local — see enableSampleDataMode(). The merge
        // below writes straight to localURL (bypassing save()'s sample-mode
        // guard), so without this an iCloud-provisioned device would pull the
        // real container file into the fake sample state and persist it.
        if sampleDataMode { return false }
        guard let cloudURL = iCloudURL else { return false }

        let fm = FileManager.default
        if !fm.fileExists(atPath: cloudURL.path) {
            // File is evicted (iCloud placeholder not yet downloaded). Trigger
            // download — NSMetadataQuery will fire again when it lands, giving
            // us another chance to reload. This is the fix for fresh installs
            // on new devices where the iCloud file hasn't been fetched yet.
            logger.info("☁️ iCloud file not local — triggering download, will reload on completion")
            try? fm.startDownloadingUbiquitousItem(at: cloudURL)
            return false
        }

        let cloudDate = FileManager.default.modificationDate(at: cloudURL) ?? .distantPast
        guard cloudDate > lastSaveDate else { return false }

        guard let fileData = try? Data(contentsOf: cloudURL),
              let decoded = try? JSONDecoder().decode(AppData.self, from: fileData) else {
            return false
        }

        let beforeDrinks = data.alcoholDrinks.count
        let beforeNic = data.nicotineEntries.count
        let beforeSauna = data.saunaSessions.count
        let beforeMetrics = data.healthMetrics.count
        let beforeBlood = data.bloodTests.count
        let beforeEye = data.eyeExams.count
        let beforeBody = data.bodyEntries.count
        let beforeEpi = data.epigeneticTests.count
        let beforeGoals = data.goals.count

        let merged = data.merged(with: decoded)
        data = merged
        lastSaveDate = cloudDate

        let addedDrinks = merged.alcoholDrinks.count - beforeDrinks
        let addedNic = merged.nicotineEntries.count - beforeNic
        let addedSauna = merged.saunaSessions.count - beforeSauna
        let addedMetrics = merged.healthMetrics.count - beforeMetrics
        logger.info("☁️ merged iCloud update (+ \(addedDrinks, privacy: .private) drinks, \(addedNic, privacy: .private) nic, \(addedSauna, privacy: .private) sauna, \(addedMetrics, privacy: .private) metrics)")

        let didChange = addedDrinks != 0 || addedNic != 0 || addedSauna != 0 || addedMetrics != 0
            || merged.bloodTests.count != beforeBlood || merged.eyeExams.count != beforeEye
            || merged.bodyEntries.count != beforeBody || merged.epigeneticTests.count != beforeEpi
            || merged.goals.count != beforeGoals

        // Mirror merged state to the local sandbox copy so the next launch
        // doesn't need to re-run the merge. Use the same protection class
        // as save(_:) so the file isn't silently downgraded.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(merged) {
            do {
                try encoded.write(to: localURL, options: [.atomic, .completeFileProtection])
            } catch {
                logger.error("💾 Failed to write local data in reloadIfNeeded: \(error.localizedDescription, privacy: .private)")
            }
        }

        return didChange
    }

    // Save to both local and iCloud
    func save(_ newData: AppData) {
        data = newData

        // Sample-data mode short-circuits persistence so screenshot runs
        // can never mutate a real user's local file or iCloud container.
        if sampleDataMode {
            logger.info("💾 sample-data mode — skipping persistence (in-memory only)")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded: Data
        do {
            encoded = try encoder.encode(data)
        } catch {
            logger.error("💾 Failed to encode data — save aborted, no data written: \(error.localizedDescription, privacy: .private)")
            return
        }

        // Health profile contains birth date, sex, and behavioral data — write
        // with .complete file protection so the file is unreadable while the
        // device is locked. The main app does not need background access to
        // this file (the widget reads its own snapshot via WidgetBridge), so
        // .complete is the strongest level we can use without breaking sync.
        do {
            try encoded.write(to: localURL, options: [.atomic, .completeFileProtection])
        } catch {
            logger.error("💾 Failed to write local data: \(error.localizedDescription, privacy: .private)")
        }
        lastSaveDate = Date()

        if let cloudURL = iCloudURL, ensureICloudReachable(cloudURL) {
            // iCloud Documents propagates protection class via the container's
            // security policy; pass .completeUnlessOpen so the iCloud daemon
            // can still read it for sync after first authentication.
            do {
                try encoded.write(to: cloudURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            } catch {
                logger.error("☁️ Failed to write iCloud data: \(error.localizedDescription, privacy: .private)")
                noteICloudUnavailable()
            }
        }

        // iCloud-monitor markLocalWrite runs on @MainActor (attached Task is fine).
        Task { @MainActor in ICloudMonitor.shared.markLocalWrite() }
        // WidgetBridge.update does synchronous work (engine calc, file write, WidgetCenter
        // reload). Task.detached keeps it off the DataStore actor's serial executor.
        Task.detached { WidgetBridge.update(data: newData) }
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
    /// The closure returns `(persist:, result:)`: `persist == false` skips the
    /// write entirely so a sync that finds nothing new doesn't trigger a
    /// redundant save + iCloud broadcast. `result` is handed back to the caller
    /// (e.g. to decide which change notifications to post).
    @discardableResult
    func mutate<R: Sendable>(_ body: @Sendable (inout AppData) -> (persist: Bool, result: R)) -> R {
        var d = load()
        let (persist, result) = body(&d)
        if persist { save(d) }
        return result
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(load())
    }

    func importData(from jsonData: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode(AppData.self, from: jsonData) else { return false }
        // Snapshot whatever is currently on disk BEFORE the import clobbers
        // it, so a bad import file can be undone.
        backupCurrentFile(reason: "import")
        save(imported)
        return true
    }

    // MARK: - Private

    private func bestURL() -> URL {
        FileManager.default.newerOf(cloud: iCloudURL, local: localURL)
    }

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
            logger.error("☁️ iCloud container not reachable — saving locally only: \(error.localizedDescription, privacy: .private)")
            noteICloudUnavailable()
            return false
        }
    }

    /// Post the iCloud-unavailable notification at most once per launch. Hops to
    /// `@MainActor` like the other DataStore notifications since the UI observes it.
    private func noteICloudUnavailable() {
        guard !didWarnICloudUnavailable else { return }
        didWarnICloudUnavailable = true
        Task { @MainActor in
            NotificationCenter.default.post(name: .iCloudWriteUnavailable, object: nil)
        }
    }
}
