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
        flightsClimbed: Double? = nil
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
    }
}
