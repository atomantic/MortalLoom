import Foundation
#if os(iOS)
import HealthKit
import os

private let logger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "HealthKitSync")

/// Pulls HealthKit metrics into AppData so they sync to macOS via iCloud.
/// Runs on iOS only since macOS doesn't have direct HealthKit access.
@MainActor
final class HealthKitSync {
    static let shared = HealthKitSync()

    private let hk = HealthKitService.shared

    /// Pull latest weight and body fat from HealthKit into bodyEntries.
    /// Merges with existing data — HealthKit entries won't duplicate manual entries.
    func syncBodyMetrics() async {
        guard hk.isAvailable, hk.authorizationRequestCompleted else { return }

        var data = await DataStore.shared.getData()
        var changed = false

        // Sync weight
        if let result = await hk.latestValue(for: .bodyMass, unit: .pound()) {
            let dateStr = DateFormatting.dateString(result.date)
            if let idx = data.bodyEntries.firstIndex(where: { $0.date == dateStr }) {
                if data.bodyEntries[idx].weightLbs != result.value {
                    data.bodyEntries[idx].weightLbs = result.value
                    changed = true
                }
            } else {
                data.bodyEntries.append(BodyEntry(date: dateStr, weightLbs: result.value))
                changed = true
            }
        }

        // Sync body fat percentage
        if let result = await hk.latestValue(for: .bodyFatPercentage, unit: .percent()) {
            let dateStr = DateFormatting.dateString(result.date)
            let pct = result.value * 100 // HealthKit returns 0-1
            if let idx = data.bodyEntries.firstIndex(where: { $0.date == dateStr }) {
                if data.bodyEntries[idx].bodyFatPct != pct {
                    data.bodyEntries[idx].bodyFatPct = pct
                    changed = true
                }
            } else {
                data.bodyEntries.append(BodyEntry(date: dateStr, bodyFatPct: pct))
                changed = true
            }
        }

        // Sync BMI into lifestyle profile if available
        if let result = await hk.latestValue(for: .bodyMassIndex, unit: .count()) {
            if data.profile.lifestyle.bmi != result.value {
                data.profile.lifestyle.bmi = result.value
                changed = true
            }
        }

        if changed {
            await DataStore.shared.save(data)
            NotificationCenter.default.post(name: .profileDidChange, object: nil)
        }
    }

    /// Pull historical weight data for the last 90 days.
    func syncWeightHistory() async {
        guard hk.isAvailable, hk.authorizationRequestCompleted else { return }

        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -90, to: to) ?? to

        let weightData = await hk.dailyStats(for: .bodyMass, unit: .pound(), aggregation: .average, from: from, to: to)
        guard !weightData.isEmpty else { return }

        var data = await DataStore.shared.getData()
        let existingDates = Set(data.bodyEntries.map(\.date))
        var changed = false

        for entry in weightData {
            let dateStr = DateFormatting.dateString(entry.date)
            if !existingDates.contains(dateStr) {
                data.bodyEntries.append(BodyEntry(date: dateStr, weightLbs: entry.value))
                changed = true
            }
        }

        if changed {
            await DataStore.shared.save(data)
            NotificationCenter.default.post(name: .profileDidChange, object: nil)
        }
    }

    /// Pull 90 days of daily health metrics (HRV, heart rate, steps, etc.) into AppData.
    /// These persist to iCloud so macOS can render correlation charts without HealthKit.
    func syncHealthMetrics() async {
        guard hk.isAvailable, hk.authorizationRequestCompleted else { return }

        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -90, to: to) ?? to

        // Fetch all metric types in parallel
        async let hrvData = hk.dailyStats(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), aggregation: .average, from: from, to: to)
        async let hrData = hk.dailyStats(for: .heartRate, unit: .count().unitDivided(by: .minute()), aggregation: .average, from: from, to: to)
        async let rhrData = hk.dailyStats(for: .restingHeartRate, unit: .count().unitDivided(by: .minute()), aggregation: .average, from: from, to: to)
        async let stepsData = hk.dailyStats(for: .stepCount, unit: .count(), aggregation: .sum, from: from, to: to)
        async let activeEnergyData = hk.dailyStats(for: .activeEnergyBurned, unit: .kilocalorie(), aggregation: .sum, from: from, to: to)
        async let exerciseData = hk.dailyStats(for: .appleExerciseTime, unit: .minute(), aggregation: .sum, from: from, to: to)
        async let flightsData = hk.dailyStats(for: .flightsClimbed, unit: .count(), aggregation: .sum, from: from, to: to)
        async let vo2Data = hk.dailyStats(for: .vo2Max, unit: HKUnit(from: "mL/min*kg"), aggregation: .average, from: from, to: to)
        async let spo2Data = hk.dailyStats(for: .oxygenSaturation, unit: .percent(), aggregation: .average, from: from, to: to)
        async let respData = hk.dailyStats(for: .respiratoryRate, unit: .count().unitDivided(by: .minute()), aggregation: .average, from: from, to: to)
        async let sleepStageData = hk.dailySleepStages(from: from, to: to)

        // Cardio recovery, gait, activity, environment
        async let cardioRecoveryData = hk.dailyStats(for: .heartRateRecoveryOneMinute, unit: .count().unitDivided(by: .minute()), aggregation: .average, from: from, to: to)
        async let walkingSpeedData = hk.dailyStats(for: .walkingSpeed, unit: HKUnit.meter().unitDivided(by: .second()), aggregation: .average, from: from, to: to)
        async let walkingDistanceData = hk.dailyStats(for: .distanceWalkingRunning, unit: .meterUnit(with: .kilo), aggregation: .sum, from: from, to: to)
        async let walkingAsymmetryData = hk.dailyStats(for: .walkingAsymmetryPercentage, unit: .percent(), aggregation: .average, from: from, to: to)
        async let walkingDoubleSupportData = hk.dailyStats(for: .walkingDoubleSupportPercentage, unit: .percent(), aggregation: .average, from: from, to: to)
        async let stairUpData = hk.dailyStats(for: .stairAscentSpeed, unit: HKUnit.meter().unitDivided(by: .second()), aggregation: .average, from: from, to: to)
        async let stairDownData = hk.dailyStats(for: .stairDescentSpeed, unit: HKUnit.meter().unitDivided(by: .second()), aggregation: .average, from: from, to: to)
        async let walkingHRData = hk.dailyStats(for: .walkingHeartRateAverage, unit: .count().unitDivided(by: .minute()), aggregation: .average, from: from, to: to)
        async let standData = hk.dailyStats(for: .appleStandTime, unit: .minute(), aggregation: .sum, from: from, to: to)
        async let basalEnergyData = hk.dailyStats(for: .basalEnergyBurned, unit: .kilocalorie(), aggregation: .sum, from: from, to: to)
        async let daylightData = hk.dailyStats(for: .timeInDaylight, unit: .minute(), aggregation: .sum, from: from, to: to)

        // Previously requested but not synced
        async let cyclingData = hk.dailyStats(for: .distanceCycling, unit: .meterUnit(with: .kilo), aggregation: .sum, from: from, to: to)
        async let stepLengthData = hk.dailyStats(for: .walkingStepLength, unit: .meter(), aggregation: .average, from: from, to: to)
        async let leanMassData = hk.dailyStats(for: .leanBodyMass, unit: .pound(), aggregation: .average, from: from, to: to)
        async let envAudioData = hk.dailyStats(for: .environmentalAudioExposure, unit: .decibelAWeightedSoundPressureLevel(), aggregation: .average, from: from, to: to)
        async let headphoneAudioData = hk.dailyStats(for: .headphoneAudioExposure, unit: .decibelAWeightedSoundPressureLevel(), aggregation: .average, from: from, to: to)

        // New longevity-relevant types
        async let bpSystolicData = hk.dailyStats(for: .bloodPressureSystolic, unit: .millimeterOfMercury(), aggregation: .average, from: from, to: to)
        async let bpDiastolicData = hk.dailyStats(for: .bloodPressureDiastolic, unit: .millimeterOfMercury(), aggregation: .average, from: from, to: to)
        async let glucoseData = hk.dailyStats(for: .bloodGlucose, unit: HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)), aggregation: .average, from: from, to: to)
        async let bodyTempData = hk.dailyStats(for: .bodyTemperature, unit: .degreeFahrenheit(), aggregation: .average, from: from, to: to)
        async let wristTempData = hk.dailyStats(for: .appleSleepingWristTemperature, unit: .degreeCelsius(), aggregation: .average, from: from, to: to)
        async let hkAlcoholData = hk.dailyStats(for: .numberOfAlcoholicBeverages, unit: .count(), aggregation: .sum, from: from, to: to)
        async let steadinessData = hk.dailyStats(for: .appleWalkingSteadiness, unit: .percent(), aggregation: .average, from: from, to: to)
        async let physicalEffortData = hk.dailyStats(for: .physicalEffort, unit: HKUnit.kilocalorie().unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour())), aggregation: .average, from: from, to: to)
        async let mindfulData = hk.dailyMindfulMinutes(from: from, to: to)
        async let breathingDisturbanceData: [(date: Date, value: Double)] = {
            if #available(iOS 18.0, *) {
                // Native unit is the dimensionless HKUnit.count() — the raw
                // per-sample value already represents events per hour. The
                // earlier .count()/.hour() form added a time dimension and
                // raised an NSException inside HKQuantity.doubleValue(for:).
                return await hk.dailyStats(for: .appleSleepingBreathingDisturbances, unit: .count(), aggregation: .average, from: from, to: to)
            }
            return []
        }()

        // Collect all results
        let hrv = await hrvData
        let hr = await hrData
        let rhr = await rhrData
        let steps = await stepsData
        let energy = await activeEnergyData
        let exercise = await exerciseData
        let flights = await flightsData
        let vo2 = await vo2Data
        let spo2 = await spo2Data
        let resp = await respData
        let sleepStages = await sleepStageData

        let cardioRecovery = await cardioRecoveryData
        let walkSpeed = await walkingSpeedData
        let walkDist = await walkingDistanceData
        let walkAsym = await walkingAsymmetryData
        let walkDS = await walkingDoubleSupportData
        let stairUp = await stairUpData
        let stairDown = await stairDownData
        let walkHR = await walkingHRData
        let stand = await standData
        let basalE = await basalEnergyData
        let daylight = await daylightData

        // Previously requested but not synced
        let cycling = await cyclingData
        let stepLength = await stepLengthData
        let leanMass = await leanMassData
        let envAudio = await envAudioData
        let headphoneAudio = await headphoneAudioData

        // New longevity types
        let bpSystolic = await bpSystolicData
        let bpDiastolic = await bpDiastolicData
        let glucose = await glucoseData
        let bodyTemp = await bodyTempData
        let wristTemp = await wristTempData
        let hkAlcohol = await hkAlcoholData
        let steadiness = await steadinessData
        let physicalEffort = await physicalEffortData
        let mindful = await mindfulData
        let breathingDisturbances = await breathingDisturbanceData

        // Build a date-keyed dictionary of all metrics
        var byDate: [String: HealthMetricEntry] = [:]

        func merge(_ data: [(date: Date, value: Double)], into path: WritableKeyPath<HealthMetricEntry, Double?>, transform: ((Double) -> Double)? = nil) {
            for item in data {
                let dateStr = DateFormatting.dateString(item.date)
                var entry = byDate[dateStr] ?? HealthMetricEntry(date: dateStr)
                entry[keyPath: path] = transform?(item.value) ?? item.value
                byDate[dateStr] = entry
            }
        }

        merge(hrv, into: \.hrv)
        merge(hr, into: \.heartRate)
        merge(rhr, into: \.restingHeartRate)
        merge(steps, into: \.steps)
        merge(energy, into: \.activeEnergy)
        merge(exercise, into: \.exerciseMinutes)
        merge(flights, into: \.flightsClimbed)
        merge(vo2, into: \.vo2Max)
        merge(resp, into: \.respiratoryRate)

        // Sleep stages — merge total + breakdown
        for stage in sleepStages {
            let dateStr = DateFormatting.dateString(stage.date)
            var entry = byDate[dateStr] ?? HealthMetricEntry(date: dateStr)
            entry.sleepHours = stage.totalHours
            entry.sleepDeepHours = stage.deepHours
            entry.sleepRemHours = stage.remHours
            entry.sleepCoreHours = stage.coreHours
            byDate[dateStr] = entry
        }

        // Cardio recovery, gait, activity, environment
        merge(cardioRecovery, into: \.cardioRecovery)
        merge(walkSpeed, into: \.walkingSpeed)
        merge(walkDist, into: \.walkingDistance)
        merge(stairUp, into: \.stairSpeedUp)
        merge(stairDown, into: \.stairSpeedDown)
        merge(walkHR, into: \.walkingHRAverage)
        merge(stand, into: \.standMinutes)
        merge(basalE, into: \.basalEnergy)
        merge(daylight, into: \.daylightMinutes)

        // Previously requested but not synced
        merge(cycling, into: \.distanceCycling)
        merge(stepLength, into: \.walkingStepLength)
        merge(leanMass, into: \.leanBodyMass)
        merge(envAudio, into: \.environmentalAudioExposure)
        merge(headphoneAudio, into: \.headphoneAudioExposure)

        // New longevity types
        merge(bpSystolic, into: \.bloodPressureSystolic)
        merge(bpDiastolic, into: \.bloodPressureDiastolic)
        merge(glucose, into: \.bloodGlucose)
        merge(bodyTemp, into: \.bodyTemperature)
        merge(wristTemp, into: \.wristTemperature)
        merge(hkAlcohol, into: \.hkAlcoholicBeverages)
        merge(physicalEffort, into: \.physicalEffort)
        merge(mindful, into: \.mindfulMinutes)
        merge(breathingDisturbances, into: \.breathingDisturbances)

        // HealthKit returns these as 0-1 fractions; convert to 0-100 percentages
        let toPercent: (Double) -> Double = { $0 * 100 }
        merge(walkAsym, into: \.walkingAsymmetry, transform: toPercent)
        merge(walkDS, into: \.walkingDoubleSupport, transform: toPercent)
        merge(spo2, into: \.oxygenSaturation, transform: toPercent)
        merge(steadiness, into: \.walkingSteadiness, transform: toPercent)

        guard !byDate.isEmpty else { return }

        await DataStore.shared.upsertHealthMetrics(Array(byDate.values))
        NotificationCenter.default.post(name: .dataDidSync, object: nil)

        // Sync 30-day average sleep hours into lifestyle profile (HealthKit as source of truth)
        let recentSleepNights = sleepStages.filter { $0.totalHours > 0 }.suffix(30)
        if recentSleepNights.count >= 3 {
            let avgSleep = (recentSleepNights.map(\.totalHours).reduce(0, +) / Double(recentSleepNights.count) * 10).rounded() / 10
            var profileData = await DataStore.shared.getData()
            if abs(profileData.profile.lifestyle.sleepHoursPerNight - avgSleep) >= 0.05 {
                profileData.profile.lifestyle.sleepHoursPerNight = avgSleep
                await DataStore.shared.save(profileData)
                NotificationCenter.default.post(name: .profileDidChange, object: nil)
                // Average is a rolling 30-day mean — privacy: .private keeps the
                // numeric value out of system log streams, but the sync event is
                // worth recording for diagnostics.
                logger.info("💤 Synced sleep avg from HealthKit: \(avgSleep, privacy: .private)h/night")
            }
        }
    }
}
#endif
