import Foundation
import os

extension Notification.Name {
    static let dataDidSync = Notification.Name("dataDidSync")
}

enum CloudConfig {
    static let containerID = "iCloud.net.shadowpuppet.MeatSpaceTracker"
}

private let logger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "DataStore")

extension FileManager {
    /// Returns the cloud URL if it exists and is newer than the local URL, otherwise the local URL.
    func newerOf(cloud: URL?, local: URL) -> URL {
        guard let cloud, fileExists(atPath: cloud.path) else { return local }
        let cloudDate = (try? attributesOfItem(atPath: cloud.path)[.modificationDate] as? Date) ?? .distantPast
        let localDate = (try? attributesOfItem(atPath: local.path)[.modificationDate] as? Date) ?? .distantPast
        return cloudDate >= localDate ? cloud : local
    }
}

actor DataStore {
    static let shared = DataStore()

    private var data: AppData = .empty
    private var loaded = false
    private var lastSaveDate: Date = .distantPast
    /// When true, save() keeps data in memory only and NEVER writes to local
    /// or iCloud. Used by -sample-data mode so fake screenshot data cannot
    /// overwrite a real user's iCloud container. Set once at app launch via
    /// enableSampleDataMode(); there is no way to turn it back off.
    private var sampleDataMode = false

    /// Debug-only: switch this store into in-memory mode so writes don't
    /// touch disk or iCloud. Irreversible for the process lifetime.
    func enableSampleDataMode() {
        sampleDataMode = true
    }

    /// Debug-only: replace the in-memory data without persisting. Paired with
    /// enableSampleDataMode() for the screenshot-capture flow.
    func setInMemory(_ newData: AppData) {
        data = newData
        loaded = true
    }

    // File locations
    private var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MortalLoom.json")
    }

    private var iCloudURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: CloudConfig.containerID)?
            .appendingPathComponent("Documents/MortalLoom.json")
    }

    private var localGenomeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("genome-raw.txt")
    }

    private var iCloudGenomeURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: CloudConfig.containerID)?
            .appendingPathComponent("Documents/genome-raw.txt")
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
                if let mtime = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date {
                    lastSaveDate = mtime
                }
                let drinkCount = self.data.alcoholDrinks.count
                let nicCount = self.data.nicotineEntries.count
                let saunaCount = self.data.saunaSessions.count
                logger.info("💾 loaded data from \(url.lastPathComponent, privacy: .public) (\(drinkCount) drinks, \(nicCount) nic, \(saunaCount) sauna)")
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
                            lastSaveDate = (try? fm.attributesOfItem(atPath: cloudURL.path)[.modificationDate] as? Date) ?? Date()
                            let drinkCount = self.data.alcoholDrinks.count
                            let nicCount = self.data.nicotineEntries.count
                            logger.info("💾 loaded iCloud data after download (\(drinkCount) drinks, \(nicCount) nic)")
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

    /// Reload from disk if the iCloud file is newer than our last save.
    /// Returns true if data was updated.
    func reloadIfNeeded() -> Bool {
        guard let cloudURL = iCloudURL,
              FileManager.default.fileExists(atPath: cloudURL.path) else { return false }

        let cloudDate = (try? FileManager.default.attributesOfItem(atPath: cloudURL.path)[.modificationDate] as? Date) ?? .distantPast
        guard cloudDate > lastSaveDate else { return false }

        if let fileData = try? Data(contentsOf: cloudURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: fileData) {
            data = decoded
            lastSaveDate = cloudDate
            // Mirror the same protection class used in save(_:) so the local
            // copy is never silently downgraded by an iCloud-triggered reload.
            do {
                try fileData.write(to: localURL, options: [.atomic, .completeFileProtection])
            } catch {
                logger.error("💾 Failed to write local data in reloadIfNeeded: \(error.localizedDescription, privacy: .private)")
            }
            return true
        }
        return false
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
        guard let encoded = try? encoder.encode(data) else { return }

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

        if let cloudURL = iCloudURL {
            let dir = cloudURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                logger.error("☁️ Failed to create iCloud directory: \(error.localizedDescription, privacy: .private)")
            }
            // iCloud Documents propagates protection class via the container's
            // security policy; pass .completeUnlessOpen so the iCloud daemon
            // can still read it for sync after first authentication.
            do {
                try encoded.write(to: cloudURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            } catch {
                logger.error("☁️ Failed to write iCloud data: \(error.localizedDescription, privacy: .private)")
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

    func updateProfile(_ profile: HealthProfile) {
        var d = load()
        d.profile = profile
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
        if let cloudURL = iCloudGenomeURL {
            let dir = cloudURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                logger.error("🧬 Failed to create iCloud genome directory: \(error.localizedDescription, privacy: .private)")
            }
            do {
                try data.write(to: cloudURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            } catch {
                logger.error("🧬 Failed to write iCloud genome file: \(error.localizedDescription, privacy: .private)")
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
        save(imported)
        return true
    }

    // MARK: - Private

    private func bestURL() -> URL {
        FileManager.default.newerOf(cloud: iCloudURL, local: localURL)
    }
}
