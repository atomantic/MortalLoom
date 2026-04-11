import Foundation

struct AppData: Codable, Sendable {
    var profile: HealthProfile
    var alcoholDrinks: [AlcoholDrink]
    var alcoholPresets: [AlcoholPreset]
    var nicotineEntries: [NicotineEntry]
    var nicotinePresets: [NicotinePreset]
    var bloodTests: [BloodTest]
    var eyeExams: [EyeExam]
    var epigeneticTests: [EpigeneticTest]
    var bodyEntries: [BodyEntry]
    var healthMetrics: [HealthMetricEntry]
    var goals: [Goal]
    var habits: [Habit]
    var genomeScanRecord: GenomeScanRecord?
    var saunaSessions: [SaunaSession]
    var saunaPresets: [SaunaPreset]

    static let empty = AppData(
        profile: HealthProfile(birthDate: nil, biologicalSex: nil, lifestyle: .default),
        alcoholDrinks: [],
        alcoholPresets: AlcoholPreset.defaults,
        nicotineEntries: [],
        nicotinePresets: NicotinePreset.defaults,
        bloodTests: [],
        eyeExams: [],
        epigeneticTests: [],
        bodyEntries: [],
        healthMetrics: [],
        goals: [],
        habits: [],
        genomeScanRecord: nil,
        saunaSessions: [],
        saunaPresets: SaunaPreset.defaults
    )

    init(profile: HealthProfile, alcoholDrinks: [AlcoholDrink], alcoholPresets: [AlcoholPreset],
         nicotineEntries: [NicotineEntry], nicotinePresets: [NicotinePreset],
         bloodTests: [BloodTest], eyeExams: [EyeExam], epigeneticTests: [EpigeneticTest],
         bodyEntries: [BodyEntry] = [], healthMetrics: [HealthMetricEntry] = [],
         goals: [Goal] = [], habits: [Habit] = [],
         genomeScanRecord: GenomeScanRecord? = nil,
         saunaSessions: [SaunaSession] = [], saunaPresets: [SaunaPreset] = SaunaPreset.defaults) {
        self.profile = profile
        self.alcoholDrinks = alcoholDrinks
        self.alcoholPresets = alcoholPresets
        self.nicotineEntries = nicotineEntries
        self.nicotinePresets = nicotinePresets
        self.bloodTests = bloodTests
        self.eyeExams = eyeExams
        self.epigeneticTests = epigeneticTests
        self.bodyEntries = bodyEntries
        self.healthMetrics = healthMetrics
        self.goals = goals
        self.habits = habits
        self.genomeScanRecord = genomeScanRecord
        self.saunaSessions = saunaSessions
        self.saunaPresets = saunaPresets
    }

    /// True when the data has no user-entered content (only defaults).
    var hasUserData: Bool {
        profile.birthDate != nil
        || !alcoholDrinks.isEmpty
        || !nicotineEntries.isEmpty
        || !saunaSessions.isEmpty
        || !bloodTests.isEmpty
        || !eyeExams.isEmpty
        || !epigeneticTests.isEmpty
        || !bodyEntries.isEmpty
        || !healthMetrics.isEmpty
        || !goals.isEmpty
        || !habits.isEmpty
        || genomeScanRecord != nil
    }

    // Support decoding files saved before newer fields were added
    enum CodingKeys: String, CodingKey {
        case profile, alcoholDrinks, alcoholPresets, nicotineEntries, nicotinePresets
        case bloodTests, eyeExams, epigeneticTests, bodyEntries, healthMetrics, goals, habits
        case genomeScanRecord, saunaSessions, saunaPresets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decode(HealthProfile.self, forKey: .profile)
        alcoholDrinks = try c.decode([AlcoholDrink].self, forKey: .alcoholDrinks)
        alcoholPresets = try c.decode([AlcoholPreset].self, forKey: .alcoholPresets)
        nicotineEntries = try c.decode([NicotineEntry].self, forKey: .nicotineEntries)
        nicotinePresets = try c.decode([NicotinePreset].self, forKey: .nicotinePresets)
        bloodTests = try c.decode([BloodTest].self, forKey: .bloodTests)
        eyeExams = try c.decode([EyeExam].self, forKey: .eyeExams)
        epigeneticTests = try c.decode([EpigeneticTest].self, forKey: .epigeneticTests)
        bodyEntries = try c.decodeIfPresent([BodyEntry].self, forKey: .bodyEntries) ?? []
        healthMetrics = try c.decodeIfPresent([HealthMetricEntry].self, forKey: .healthMetrics) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        habits = try c.decodeIfPresent([Habit].self, forKey: .habits) ?? []
        genomeScanRecord = try c.decodeIfPresent(GenomeScanRecord.self, forKey: .genomeScanRecord)
        saunaSessions = try c.decodeIfPresent([SaunaSession].self, forKey: .saunaSessions) ?? []
        saunaPresets = try c.decodeIfPresent([SaunaPreset].self, forKey: .saunaPresets) ?? SaunaPreset.defaults
    }
}

// MARK: - Sync Merge

extension AppData {
    /// Return a new AppData that unions `self` with `remote`.
    ///
    /// For UUID-keyed arrays (drinks, nicotine, sauna, blood, body, eye,
    /// epigenetic, goals), entries are keyed by `id` and the REMOTE entry
    /// wins on any id collision (remote is treated as the "source of truth
    /// that just arrived"). This preserves both sides' additions — the core
    /// reason to merge instead of wholesale-replace.
    ///
    /// For `healthMetrics` (date-keyed, one row per day), rows are combined
    /// by date using `HealthMetricEntry.mergeFields(from:)`, which takes
    /// any non-nil field from the remote side. This means a row with only
    /// HRV on one device and only sleep on the other becomes a single row
    /// with both, rather than one overwriting the other.
    ///
    /// For single-object fields (`profile`, `genomeScanRecord`) and preset
    /// lists (`alcoholPresets`, `nicotinePresets`, `saunaPresets`), the
    /// merge uses remote-wins wholesale. The caller of `merged(with:)` is
    /// expected to pass the "newer" file as `remote` when deciding which
    /// profile/presets to keep.
    ///
    /// Known limitation: explicit deletions are not tombstoned. If you
    /// delete an entry on device A and the same entry still exists on
    /// device B, the next merge will resurrect it. Users hit by this can
    /// simply re-delete; tombstones are a larger design change deferred
    /// to a future iteration.
    func merged(with remote: AppData) -> AppData {
        var result = self

        result.alcoholDrinks    = mergeByID(self.alcoholDrinks,    remote.alcoholDrinks)
        result.nicotineEntries  = mergeByID(self.nicotineEntries,  remote.nicotineEntries)
        result.saunaSessions    = mergeByID(self.saunaSessions,    remote.saunaSessions)
        result.bloodTests       = mergeByID(self.bloodTests,       remote.bloodTests)
        result.eyeExams         = mergeByID(self.eyeExams,         remote.eyeExams)
        result.epigeneticTests  = mergeByID(self.epigeneticTests,  remote.epigeneticTests)
        result.bodyEntries      = mergeByID(self.bodyEntries,      remote.bodyEntries)
        result.goals            = mergeByID(self.goals,            remote.goals)
        result.habits           = mergeByID(self.habits,           remote.habits)

        // healthMetrics is logically keyed by date, not by uuid. Merge per
        // date using HealthMetricEntry.mergeFields which preserves non-nil
        // fields from the remote side.
        result.healthMetrics    = mergeHealthMetricsByDate(self.healthMetrics, remote.healthMetrics)

        // Single-object / remote-wins fields. Profile merges by field so a
        // remote with only a few fields set doesn't wipe locally-edited
        // fields (e.g., iPhone updates lifestyle while Mac updates BMI).
        result.profile          = mergeProfile(self.profile, remote.profile)
        result.genomeScanRecord = remote.genomeScanRecord ?? self.genomeScanRecord
        result.alcoholPresets   = remote.alcoholPresets
        result.nicotinePresets  = remote.nicotinePresets
        result.saunaPresets     = remote.saunaPresets

        return result
    }

    /// Union two arrays of Identifiable-by-UUID items. Remote wins on
    /// ID collision (see doc on `merged(with:)` for rationale).
    private func mergeByID<T: Identifiable>(_ local: [T], _ remote: [T]) -> [T] where T.ID: Hashable {
        var dict: [T.ID: T] = [:]
        dict.reserveCapacity(local.count + remote.count)
        for item in local { dict[item.id] = item }
        for item in remote { dict[item.id] = item }
        return Array(dict.values)
    }

    /// Merge health metric arrays keyed by the `date` string. Fields are
    /// combined using `HealthMetricEntry.mergeFields`, preferring remote
    /// non-nil fields over local.
    private func mergeHealthMetricsByDate(_ local: [HealthMetricEntry], _ remote: [HealthMetricEntry]) -> [HealthMetricEntry] {
        var byDate: [String: HealthMetricEntry] = [:]
        byDate.reserveCapacity(local.count + remote.count)
        for m in local { byDate[m.date] = m }
        for m in remote {
            if var existing = byDate[m.date] {
                existing.mergeFields(from: m)
                byDate[m.date] = existing
            } else {
                byDate[m.date] = m
            }
        }
        return Array(byDate.values)
    }

    /// Merge profile: take remote non-nil scalar fields, preserve local
    /// values otherwise. Lifestyle uses field-level preference of non-nil
    /// values. This prevents a device that never set BMI from clobbering
    /// a device that did.
    private func mergeProfile(_ local: HealthProfile, _ remote: HealthProfile) -> HealthProfile {
        var merged = local
        if remote.birthDate != nil      { merged.birthDate = remote.birthDate }
        if remote.biologicalSex != nil  { merged.biologicalSex = remote.biologicalSex }
        merged.lifestyle = mergeLifestyle(local.lifestyle, remote.lifestyle)
        return merged
    }

    /// Merge lifestyle data field-by-field. Most lifestyle fields are
    /// non-optional scalars, so we can't distinguish "unset" from "explicit
    /// default". We treat remote's non-default value as authoritative; if
    /// remote is still on the default, we keep local (which might be a
    /// user-edited value). This is a heuristic but it beats wholesale
    /// last-wins replacement for the common "user updates lifestyle on one
    /// device" pattern.
    private func mergeLifestyle(_ local: LifestyleData, _ remote: LifestyleData) -> LifestyleData {
        let d = LifestyleData.default
        var merged = local
        if remote.smokingStatus != d.smokingStatus                 { merged.smokingStatus = remote.smokingStatus }
        if remote.exerciseMinutesPerWeek != d.exerciseMinutesPerWeek { merged.exerciseMinutesPerWeek = remote.exerciseMinutesPerWeek }
        if remote.sleepHoursPerNight != d.sleepHoursPerNight       { merged.sleepHoursPerNight = remote.sleepHoursPerNight }
        if remote.dietQuality != d.dietQuality                     { merged.dietQuality = remote.dietQuality }
        if remote.stressLevel != d.stressLevel                     { merged.stressLevel = remote.stressLevel }
        if remote.bmi != nil                                        { merged.bmi = remote.bmi }
        return merged
    }
}
