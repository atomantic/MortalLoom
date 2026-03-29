import Foundation

/// Daily health metric snapshot synced from HealthKit on iOS.
/// Persisted to iCloud so macOS can render the same data without HealthKit access.
struct HealthMetricEntry: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var date: String // "YYYY-MM-DD"

    // Heart
    var heartRate: Double?           // bpm (daily average)
    var restingHeartRate: Double?    // bpm
    var hrv: Double?                 // ms (SDNN)

    // Respiratory
    var oxygenSaturation: Double?   // % (0-100)
    var respiratoryRate: Double?    // breaths/min

    // Fitness
    var vo2Max: Double?             // mL/min/kg
    var steps: Double?              // count (daily sum)
    var activeEnergy: Double?       // kcal (daily sum)
    var exerciseMinutes: Double?    // minutes (daily sum)
    var flightsClimbed: Double?     // count (daily sum)

    // Sleep
    var sleepHours: Double?         // total asleep hours (daily)
    var sleepDeepHours: Double?     // deep (slow-wave) sleep hours
    var sleepRemHours: Double?      // REM sleep hours
    var sleepCoreHours: Double?     // core (N1+N2) sleep hours

    // Cardio recovery
    var cardioRecovery: Double?     // HR recovery bpm drop in 1 min post-exercise

    // Gait & mobility
    var walkingSpeed: Double?       // m/s (daily average)
    var walkingDistance: Double?     // km (daily sum)
    var walkingAsymmetry: Double?   // % asymmetry (lower is better)
    var walkingDoubleSupport: Double? // % of gait cycle in double support
    var stairSpeedUp: Double?       // m/s ascending stairs
    var stairSpeedDown: Double?     // m/s descending stairs
    var walkingHRAverage: Double?   // bpm average during walks

    // Activity
    var standMinutes: Double?       // daily stand time (minutes)
    var basalEnergy: Double?        // basal metabolic rate (kcal/day)

    // Respiratory
    var breathingDisturbances: Double? // events per hour during sleep

    // Environment
    var daylightMinutes: Double?    // outdoor light exposure (minutes/day)

    init(
        id: UUID = UUID(),
        date: String,
        heartRate: Double? = nil,
        restingHeartRate: Double? = nil,
        hrv: Double? = nil,
        oxygenSaturation: Double? = nil,
        respiratoryRate: Double? = nil,
        vo2Max: Double? = nil,
        steps: Double? = nil,
        activeEnergy: Double? = nil,
        exerciseMinutes: Double? = nil,
        flightsClimbed: Double? = nil,
        sleepHours: Double? = nil,
        sleepDeepHours: Double? = nil,
        sleepRemHours: Double? = nil,
        sleepCoreHours: Double? = nil,
        cardioRecovery: Double? = nil,
        walkingSpeed: Double? = nil,
        walkingDistance: Double? = nil,
        walkingAsymmetry: Double? = nil,
        walkingDoubleSupport: Double? = nil,
        stairSpeedUp: Double? = nil,
        stairSpeedDown: Double? = nil,
        walkingHRAverage: Double? = nil,
        standMinutes: Double? = nil,
        basalEnergy: Double? = nil,
        breathingDisturbances: Double? = nil,
        daylightMinutes: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.heartRate = heartRate
        self.restingHeartRate = restingHeartRate
        self.hrv = hrv
        self.oxygenSaturation = oxygenSaturation
        self.respiratoryRate = respiratoryRate
        self.vo2Max = vo2Max
        self.steps = steps
        self.activeEnergy = activeEnergy
        self.exerciseMinutes = exerciseMinutes
        self.flightsClimbed = flightsClimbed
        self.sleepHours = sleepHours
        self.sleepDeepHours = sleepDeepHours
        self.sleepRemHours = sleepRemHours
        self.sleepCoreHours = sleepCoreHours
        self.cardioRecovery = cardioRecovery
        self.walkingSpeed = walkingSpeed
        self.walkingDistance = walkingDistance
        self.walkingAsymmetry = walkingAsymmetry
        self.walkingDoubleSupport = walkingDoubleSupport
        self.stairSpeedUp = stairSpeedUp
        self.stairSpeedDown = stairSpeedDown
        self.walkingHRAverage = walkingHRAverage
        self.standMinutes = standMinutes
        self.basalEnergy = basalEnergy
        self.breathingDisturbances = breathingDisturbances
        self.daylightMinutes = daylightMinutes
    }

    /// Merge non-nil fields from another entry into this one.
    mutating func mergeFields(from source: HealthMetricEntry) {
        if let v = source.heartRate { heartRate = v }
        if let v = source.restingHeartRate { restingHeartRate = v }
        if let v = source.hrv { hrv = v }
        if let v = source.oxygenSaturation { oxygenSaturation = v }
        if let v = source.respiratoryRate { respiratoryRate = v }
        if let v = source.vo2Max { vo2Max = v }
        if let v = source.steps { steps = v }
        if let v = source.activeEnergy { activeEnergy = v }
        if let v = source.exerciseMinutes { exerciseMinutes = v }
        if let v = source.flightsClimbed { flightsClimbed = v }
        if let v = source.sleepHours { sleepHours = v }
        if let v = source.sleepDeepHours { sleepDeepHours = v }
        if let v = source.sleepRemHours { sleepRemHours = v }
        if let v = source.sleepCoreHours { sleepCoreHours = v }
        if let v = source.cardioRecovery { cardioRecovery = v }
        if let v = source.walkingSpeed { walkingSpeed = v }
        if let v = source.walkingDistance { walkingDistance = v }
        if let v = source.walkingAsymmetry { walkingAsymmetry = v }
        if let v = source.walkingDoubleSupport { walkingDoubleSupport = v }
        if let v = source.stairSpeedUp { stairSpeedUp = v }
        if let v = source.stairSpeedDown { stairSpeedDown = v }
        if let v = source.walkingHRAverage { walkingHRAverage = v }
        if let v = source.standMinutes { standMinutes = v }
        if let v = source.basalEnergy { basalEnergy = v }
        if let v = source.breathingDisturbances { breathingDisturbances = v }
        if let v = source.daylightMinutes { daylightMinutes = v }
    }
}
