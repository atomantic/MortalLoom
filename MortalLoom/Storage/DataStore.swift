import Foundation

extension Notification.Name {
    static let dataDidSync = Notification.Name("dataDidSync")
}

actor DataStore {
    static let shared = DataStore()

    private var data: AppData = .empty
    private var loaded = false
    private var lastSaveDate: Date = .distantPast

    // File locations
    private var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MortalLoom.json")
    }

    private var iCloudURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.net.shadowpuppet.MeatSpaceTracker")?
            .appendingPathComponent("Documents/MortalLoom.json")
    }

    // Load from best available source
    func load() -> AppData {
        if loaded { return data }

        let url = bestURL()
        if let fileData = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppData.self, from: fileData) {
            data = decoded
        }
        loaded = true
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
            // Also update local copy
            try? fileData.write(to: localURL, options: .atomic)
            return true
        }
        return false
    }

    // Save to both local and iCloud
    func save(_ newData: AppData) {
        data = newData
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let encoded = try? encoder.encode(data) else { return }

        try? encoded.write(to: localURL, options: .atomic)
        lastSaveDate = Date()

        if let cloudURL = iCloudURL {
            let dir = cloudURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? encoded.write(to: cloudURL, options: .atomic)
        }

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
        if let cloudURL = iCloudURL,
           FileManager.default.fileExists(atPath: cloudURL.path) {
            // Use whichever is newer
            let cloudDate = (try? FileManager.default.attributesOfItem(atPath: cloudURL.path)[.modificationDate] as? Date) ?? .distantPast
            let localDate = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.modificationDate] as? Date) ?? .distantPast
            return cloudDate >= localDate ? cloudURL : localURL
        }
        return localURL
    }
}
