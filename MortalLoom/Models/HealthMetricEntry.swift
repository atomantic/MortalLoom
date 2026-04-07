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

    // Body composition (extended)
    var leanBodyMass: Double?       // lbs

    // Cardiovascular (device synced)
    var bloodPressureSystolic: Double?  // mmHg
    var bloodPressureDiastolic: Double? // mmHg

    // Gait & mobility
    var walkingSpeed: Double?       // m/s (daily average)
    var walkingDistance: Double?     // km (daily sum)
    var walkingStepLength: Double?  // meters (daily average)
    var distanceCycling: Double?    // km (daily sum)
    var walkingAsymmetry: Double?   // % asymmetry (lower is better)
    var walkingDoubleSupport: Double? // % of gait cycle in double support
    var stairSpeedUp: Double?       // m/s ascending stairs
    var stairSpeedDown: Double?     // m/s descending stairs
    var walkingHRAverage: Double?   // bpm average during walks
    var walkingSteadiness: Double?  // % (0-100, Apple Walking Steadiness)

    // Activity
    var standMinutes: Double?       // daily stand time (minutes)
    var basalEnergy: Double?        // basal metabolic rate (kcal/day)
    var physicalEffort: Double?     // kcal/(kg*hr) average physical effort intensity

    // Breathing
    var breathingDisturbances: Double? // events per hour during sleep

    // Metabolic
    var bloodGlucose: Double?       // mg/dL
    var bodyTemperature: Double?    // °F

    // Sleep (extended)
    var wristTemperature: Double?   // °C deviation from baseline (Apple Watch)

    // Mindfulness
    var mindfulMinutes: Double?     // daily mindfulness/meditation minutes

    // Substance (HealthKit correlation)
    var hkAlcoholicBeverages: Double? // drinks logged via HealthKit (not app manual entry)

    // Environment
    var daylightMinutes: Double?    // outdoor light exposure (minutes/day)
    var environmentalAudioExposure: Double? // dB daily average
    var headphoneAudioExposure: Double?     // dB daily average

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
        distanceCycling: Double? = nil,
        walkingStepLength: Double? = nil,
        leanBodyMass: Double? = nil,
        physicalEffort: Double? = nil,
        breathingDisturbances: Double? = nil,
        bloodPressureSystolic: Double? = nil,
        bloodPressureDiastolic: Double? = nil,
        bloodGlucose: Double? = nil,
        bodyTemperature: Double? = nil,
        wristTemperature: Double? = nil,
        mindfulMinutes: Double? = nil,
        hkAlcoholicBeverages: Double? = nil,
        daylightMinutes: Double? = nil,
        environmentalAudioExposure: Double? = nil,
        headphoneAudioExposure: Double? = nil,
        walkingSteadiness: Double? = nil
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
        self.distanceCycling = distanceCycling
        self.walkingStepLength = walkingStepLength
        self.leanBodyMass = leanBodyMass
        self.physicalEffort = physicalEffort
        self.breathingDisturbances = breathingDisturbances
        self.bloodPressureSystolic = bloodPressureSystolic
        self.bloodPressureDiastolic = bloodPressureDiastolic
        self.bloodGlucose = bloodGlucose
        self.bodyTemperature = bodyTemperature
        self.wristTemperature = wristTemperature
        self.mindfulMinutes = mindfulMinutes
        self.hkAlcoholicBeverages = hkAlcoholicBeverages
        self.daylightMinutes = daylightMinutes
        self.environmentalAudioExposure = environmentalAudioExposure
        self.headphoneAudioExposure = headphoneAudioExposure
        self.walkingSteadiness = walkingSteadiness
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
        if let v = source.distanceCycling { distanceCycling = v }
        if let v = source.walkingStepLength { walkingStepLength = v }
        if let v = source.leanBodyMass { leanBodyMass = v }
        if let v = source.physicalEffort { physicalEffort = v }
        if let v = source.breathingDisturbances { breathingDisturbances = v }
        if let v = source.bloodPressureSystolic { bloodPressureSystolic = v }
        if let v = source.bloodPressureDiastolic { bloodPressureDiastolic = v }
        if let v = source.bloodGlucose { bloodGlucose = v }
        if let v = source.bodyTemperature { bodyTemperature = v }
        if let v = source.wristTemperature { wristTemperature = v }
        if let v = source.mindfulMinutes { mindfulMinutes = v }
        if let v = source.hkAlcoholicBeverages { hkAlcoholicBeverages = v }
        if let v = source.daylightMinutes { daylightMinutes = v }
        if let v = source.environmentalAudioExposure { environmentalAudioExposure = v }
        if let v = source.headphoneAudioExposure { headphoneAudioExposure = v }
        if let v = source.walkingSteadiness { walkingSteadiness = v }
    }
}
