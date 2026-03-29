# Development Plan

For project mission and milestones, see [GOALS.md](./GOALS.md).
For completed work, see [DONE.md](./DONE.md).

## Next Up

1. **Storage/HealthKit test coverage**: Unit tests for DataStore actor, HealthKitService auth states, ICloudMonitor metadata queries

## Apple Health Data Expansion

### Gap Analysis

PortOS ingests 60+ Apple Health metric types from day-partitioned JSON files. MortalLoom requests HealthKit permission for 22 quantity types + sleep, but `HealthKitSync.syncHealthMetrics()` only stores 11 of them into `HealthMetricEntry`. Several high-value longevity metrics available in Apple Health are not yet synced or correlated.

### Tier 1 — Strong Longevity Evidence (Recommend Adding)

#### 1. Sleep Stage Breakdown (deep / REM / core hours)
- **What**: HealthKit already provides `asleepDeep`, `asleepCore`, `asleepREM` values in `dailySleepHours()` — MortalLoom sums them into total hours but discards the stage breakdown
- **PortOS data**: Full stage breakdown stored per night (deep, rem, core, awake hours)
- **Longevity evidence**: Deep sleep % is linked to cognitive health, memory consolidation, glymphatic brain waste clearance, and all-cause mortality. REM is tied to emotional regulation and cardiovascular health. Stages matter more than total duration.
- **Correlations**: Alcohol suppresses deep/REM (correlate with drinking days). Sauna may improve deep sleep. Exercise timing affects stage distribution.
- **Death clock integration**: Adjust sleep impact beyond just hours — penalize consistently low deep sleep %
- **Implementation**: Add `deepSleepHours`, `remSleepHours`, `coreSleepHours` to `HealthMetricEntry`. Modify `dailySleepHours()` to return stage breakdown. Extend `SleepEngine` with stage quality rating.

#### 2. Cardio Recovery (HR Recovery after exercise)
- **What**: `HKQuantityTypeIdentifier.heartRateRecovery` — 1-minute HR drop after exercise
- **PortOS data**: `cardio_recovery` metric with bpm values
- **Longevity evidence**: Abnormal HR recovery (<12 bpm drop in 1 min) is associated with 4x cardiovascular mortality risk (Cole et al., NEJM 1999). One of the strongest single predictors of cardiac death.
- **Correlations**: Track improvement with exercise habits. Alcohol and nicotine impair recovery. VO2 max and HR recovery are complementary fitness markers.
- **Death clock integration**: Add to `CardioFitnessEngine` alongside VO2 max — poor recovery = mortality penalty
- **Implementation**: Add `cardioRecovery` to `HealthMetricEntry`. New classification in `CardioFitnessEngine`. Factor into health score.

#### 3. Walking Steadiness & Gait Metrics
- **What**: `walkingAsymmetryPercentage`, `walkingDoubleSupportPercentage`, `walkingSteadiness`, `stairSpeedUp`, `stairSpeedDown`, `walkingHeartRateAverage`
- **PortOS data**: Daily gait metrics from Apple Watch (asymmetry, double support %, stair speeds, walking HR)
- **Longevity evidence**: Walking speed is called "the 6th vital sign" — a strong independent predictor of mortality. Gait asymmetry and double support % predict fall risk (falls are a top-5 cause of death in 65+). Declining stair speed indicates functional capacity loss.
- **Correlations**: Track functional age trajectory. Correlate with body composition changes, blood markers (inflammation), and exercise habits.
- **Death clock integration**: Create a "functional fitness" score that adjusts healthspan estimate. Declining gait → shorter healthy years remaining.
- **Implementation**: Add `walkingAsymmetry`, `walkingDoubleSupport`, `stairSpeedUp`, `stairSpeedDown`, `walkingHRAverage` to `HealthMetricEntry`. New `GaitEngine` for fall risk classification and functional age estimation. MortalLoom already requests `walkingSpeed` and `walkingStepLength` but doesn't sync them — add these too.

#### 4. Breathing Disturbances (Sleep Apnea Detection)
- **What**: Apple Watch tracks breathing disturbances during sleep
- **PortOS data**: `breathing_disturbances` count per night
- **Longevity evidence**: Untreated sleep apnea increases cardiovascular mortality 2-3x, raises stroke risk, and accelerates cognitive decline. Elevated breathing disturbances (>15/hr) indicate moderate-to-severe apnea.
- **Correlations**: Correlate with alcohol (alcohol worsens apnea), BMI (obesity is primary risk factor), sleep quality, and blood pressure.
- **Death clock integration**: Persistent high breathing disturbances → mortality penalty and recommendation to get a sleep study
- **Implementation**: Add `breathingDisturbances` to `HealthMetricEntry`. Extend `SleepEngine` with apnea risk classification (AHI thresholds: <5 normal, 5-15 mild, 15-30 moderate, >30 severe).

#### 5. Time in Daylight
- **What**: `HKQuantityTypeIdentifier.timeInDaylight` — daily minutes of outdoor light exposure
- **PortOS data**: Per-minute daylight readings summed daily
- **Longevity evidence**: Circadian disruption is linked to metabolic syndrome, depression, and cancer risk (Lancet Psychiatry 2018). Daylight drives vitamin D synthesis, melatonin regulation, and mood. Low outdoor time correlates with myopia progression (relevant to eye health tracking).
- **Correlations**: Correlate with sleep quality/consistency, HRV, eye prescription changes, and mood/stress.
- **Death clock integration**: Chronic low daylight → stress and sleep quality proxy affecting lifestyle adjustment
- **Implementation**: Add `daylightMinutes` to `HealthMetricEntry`. Show trend with recommendation for minimum 30 min/day.

### Tier 2 — Moderate Evidence (Should Add)

#### 6. Stand Time & Sedentary Behavior
- **What**: `appleStandTime` — already in HealthKit readTypes but not synced
- **Longevity evidence**: Sedentary behavior is independently associated with all-cause mortality even after controlling for exercise (Ekelund et al., Lancet 2016). Standing breaks improve metabolic markers.
- **Correlations**: Correlate with blood glucose, triglycerides, and body composition trends.
- **Implementation**: Add `standMinutes` to `HealthMetricEntry`. Sync in `syncHealthMetrics()`.

#### 7. Basal Energy Burned (Resting Metabolic Rate)
- **What**: `basalEnergyBurned` — already in readTypes but not synced
- **Longevity evidence**: Declining RMR can indicate thyroid dysfunction, sarcopenia, or metabolic slowdown. Trends over months are clinically meaningful.
- **Correlations**: Correlate with body composition (lean mass changes), TSH blood markers, and age trajectory.
- **Implementation**: Add `basalEnergy` to `HealthMetricEntry`. Trend analysis for metabolic health.

#### 8. Walking/Running Distance
- **What**: `distanceWalkingRunning` — already in readTypes but not synced to HealthMetricEntry
- **Longevity evidence**: Total daily movement distance provides a richer activity picture than step count alone (stride length variation, running vs walking). More total distance = better cardiovascular outcomes.
- **Correlations**: Better exercise quantification for blood marker correlation (CorrelationEngine currently only uses steps).
- **Implementation**: Add `walkingRunningDistance` to `HealthMetricEntry`. Enhance CorrelationEngine to use distance alongside steps.

### Tier 3 — Nice to Have

#### 9. Physical Effort
- **What**: `physicalEffort` — workout intensity metric
- **Useful for**: Training load tracking, recovery needs assessment

#### 10. Six-Minute Walk Test Distance
- **What**: `sixMinuteWalkTestDistance` — clinical functional capacity
- **Useful for**: Functional age estimation (strong clinical predictor)

#### 11. Audio Exposure
- **What**: `environmentalAudioExposure`, `headphoneAudioExposure` — already in readTypes
- **Useful for**: Hearing health tracking, noise-related stress

#### 12. Cycling Distance/Metrics
- **What**: `distanceCycling` — already in readTypes
- **Useful for**: More complete exercise tracking

### New Correlations to Build

Once the above metrics are synced, these cross-domain analyses become possible:

| Correlation | Inputs | Insight |
|---|---|---|
| Alcohol → Sleep Quality | Drinking days × deep/REM % | Quantify alcohol's true sleep cost |
| Sauna → HRV/Sleep | Sauna sessions × next-day HRV × deep sleep | Validate sauna's recovery benefit |
| Nicotine → Cardio Recovery | Nicotine mg × HR recovery bpm | Quantify nicotine's cardiac impact |
| Activity → Blood Markers | Steps + distance + exercise × blood panels | Strengthen existing CorrelationEngine |
| Daylight → Sleep Consistency | Daily daylight min × sleep consistency score | Circadian regulation feedback |
| BMI → Breathing Disturbances | Weight trend × apnea severity | Weight loss motivation tied to apnea |
| Gait Trends → Functional Age | Walking speed + asymmetry over months | Early decline detection |
| Exercise → Cardio Recovery | Weekly exercise min × HR recovery trend | Fitness trajectory validation |

### Death Clock Enhancements

With the new data, `DeathClockEngine.lifestyleAdjustment()` and `healthScore()` can incorporate:

1. **Cardio Recovery Score** (+2 to -2 years) — based on HR recovery classification
2. **Sleep Quality Score** (adjust existing sleep impact) — penalize consistently poor deep/REM ratios
3. **Functional Fitness Score** (+1 to -2 years) — based on gait metrics and walking speed trends
4. **Apnea Risk** (-1 to -3 years) — based on breathing disturbance severity

### Implementation Priority

1. Sleep stages (modify existing sleep code, high-value quick win)
2. Cardio recovery (new metric, strongest single mortality predictor after VO2 max)
3. Breathing disturbances (apnea detection, simple addition)
4. Time in daylight (new metric, easy sync)
5. Sync already-requested-but-unused types (stand time, basal energy, distance, walking speed)
6. Gait engine (new engine, more complex but high long-term value)
7. New correlation charts
8. Death clock enhancement with new factors

## Backlog

- [ ] VoiceOver testing pass on iOS

## Not Porting (web-specific)

- Apple Health XML/JSON file import (replaced by native HealthKit)
- Server-side API calls (all local/on-device)
- ClinVar database sync (too large for on-device, defer to future)
- WebSocket progress updates
