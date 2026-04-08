# Development Plan

For project mission and milestones, see [GOALS.md](./GOALS.md).
For completed work, see [DONE.md](./DONE.md).

## Better Swift Audit — 2026-04-06 (COMPLETE)

Shipped 5 PRs against `main` covering 17 files + 2 new test suites (70 new test cases).
Platforms verified: iOS 17.0+, macOS 14.0+. All iOS tests pass on the post-merge `main`.

### PRs

| Category | PR | Status | Iterations | Notes |
|---|---|---|---|---|
| Security | atomantic/MortalLoom#3 | merged | 4 Copilot rounds | Fixed `.completeFileProtectionUnlessOpen` → `UntilFirstUserAuthentication` (the former does NOT permit widget background reads while locked) |
| Bugs & Perf | atomantic/MortalLoom#4 | merged | 8 Copilot rounds (10-iteration guardrail) | Reverted bad Task.detached → Task change; added file protection in `reloadIfNeeded()`; logged silent write failures |
| Code Quality | atomantic/MortalLoom#5 | merged | 5 Copilot rounds | Renamed `authorized` → `authorizationRequestCompleted` (HealthKit read auth never reports user denial — Apple privacy feature) |
| DRY & YAGNI | atomantic/MortalLoom#6 | merged | 5 Copilot rounds | Added missing sauna test for `allTimeAverage<T>` helper; fixed timezone bug in new test |
| Tests | atomantic/MortalLoom#7 | merged | 3 Copilot rounds | Split entitlements into iOS/macOS files; renamed clamp tests to reflect what they actually verify |

### Foundation — Shared Utilities

- `View.inlineNavigationTitle()` (in `Theme/Theme.swift`) — wraps `.navigationBarTitleDisplayMode(.inline)` in `#if os(iOS)`. Replaced 6 inline guards in `SubstancesView`. The remaining 6 occurrences (PaywallView, GoalsView, GenomeView, BodyView, BloodView) are deferred for a follow-up cleanup PR.
- `weeklyXAxis()` chart helper — deferred (originally planned but skipped because the chart axis pattern only existed in 5 SubstancesView call sites, and the `@AxisContentBuilder` extraction was more complex than the savings).
- `SubstanceEngine.allTimeAverage<T>(items:date:value:now:)` — generic helper that replaced 3 copies of the same date-bucket arithmetic.

### Notable Findings During the Cycle

These are the things future-self should know:

- **HealthKit read-only authorization is always `.notDetermined` for privacy.** `HKHealthStore.requestAuthorization(toShare:read:)` does NOT throw when the user denies access for read types — there is no way to detect denial. The previous `authorized: Bool` flag was a misleading name because `true` only meant "the request call returned without error", which is true even when the user denied everything. Renamed to `authorizationRequestCompleted` to avoid the trap.
- **`.completeFileProtectionUnlessOpen` does NOT allow widget background reads when the file is closed.** Only `.completeFileProtectionUntilFirstUserAuthentication` does. The widget App Group snapshot had to use the latter; the original audit-PR change had it wrong.
- **`Task.detached` vs attached `Task` inside an actor**: an attached `Task` inherits actor isolation, so it BLOCKS the actor for the duration of the work. For a widget snapshot write that happens after `DataStore.save()`, `Task.detached` is correct. The audit briefly tried switching to attached `Task` and the Copilot reviewer caught the regression.
- **Swift `??` binds TIGHTER than `>`**: `NilCoalescingPrecedence` is higher than `ComparisonPrecedence`, so `a ?? b > c ?? d` is `(a ?? b) > (c ?? d)`. Audit Agent 2 flagged a `Goal` sort closure as a precedence bug; it was already correct. Always verify Swift operator precedence claims against the language reference.
- **`ISO8601DateFormatter` is documented thread-safe since iOS 10** (not iOS 7 — `NSDateFormatter` was thread-safe since iOS 7, but `ISO8601DateFormatter` was introduced in iOS 10 and inherited the same guarantee). Cached as `nonisolated(unsafe) static let`.
- **HealthKit IS available on macOS 13+** with limited functionality. Audit Agent 6 flagged the unguarded `import HealthKit` in HealthKitService.swift, BodyView.swift, OnboardingView.swift as a CRITICAL macOS-build-break — but macOS builds clean today, so the finding was a false positive. Always verify "this won't compile on platform X" claims by actually building on platform X.
- **`Data.WritingOptions.completeFileProtection` is iOS-specific** but compiles cleanly as a no-op on macOS — no `#if os(iOS)` guard needed.
- **XcodeGen drift in entitlements**: the committed `MortalLoom.entitlements` file was missing keys that `project.yml` declared (`com.apple.security.app-sandbox`, etc.). XcodeGen regenerates from project.yml on every run. Phase 4c had to split into iOS/macOS-specific entitlements files because the macOS app uses sandbox capabilities that don't apply to iOS.

### Deferred / Out-of-Scope From This Cycle

- God-file decomposition (Substances/Genome/Overview/Goals at 1000+ lines)
- Architectural file moves (Engine → Services for stateful services)
- macOS window lifecycle hardening (App Store guideline 4 — `applicationShouldTerminateAfterLastWindowClosed`, `applicationShouldHandleReopen`, "Show Main Window" command)
- ClinVar streaming decompression rewrite (the gzip is still loaded into memory before streaming)
- Test coverage for `CardioFitnessEngine`, `GaitEngine`, `GenomeEngine` (Agent 7 flagged but only `SleepEngineTests` and `LocationEngineTests` shipped this cycle)
- 6 remaining `#if os(iOS) .navigationBarTitleDisplayMode #endif` guards in PaywallView, GoalsView, GenomeView, BodyView, BloodView

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
| ~~Alcohol → Sleep Quality~~ ✅ | Drinking days × deep/REM % | Quantify alcohol's true sleep cost |
| Sauna → HRV/Sleep | Sauna sessions × next-day HRV × deep sleep | Validate sauna's recovery benefit |
| Nicotine → Cardio Recovery | Nicotine mg × HR recovery bpm | Quantify nicotine's cardiac impact |
| Activity → Blood Markers | Steps + distance + exercise × blood panels | Strengthen existing CorrelationEngine |
| Daylight → Sleep Consistency | Daily daylight min × sleep consistency score | Circadian regulation feedback |
| BMI → Breathing Disturbances | Weight trend × apnea severity | Weight loss motivation tied to apnea |
| Gait Trends → Functional Age | Walking speed + asymmetry over months | Early decline detection |
| Exercise → Cardio Recovery | Weekly exercise min × HR recovery trend | Fitness trajectory validation |

### Death Clock Enhancements

`healthMetricsAdjustment()` is now wired into `DeathClockEngine.calculate()` — cardio recovery, walking speed, and apnea risk all affect the final life expectancy estimate. Individual factors are visible in the Overview Life Expectancy Factors card.

1. **Cardio Recovery Score** (+2 to -2 years) — ✅ integrated via `healthMetricsAdjustment()`
2. **Sleep Quality Score** (adjust existing sleep impact) — ✅ integrated via `enhancedLongevityImpact()`
3. **Functional Fitness Score** (+1 to -2 years) — ✅ integrated via `healthMetricsAdjustment()`
4. **Apnea Risk** (-1 to -3 years) — ✅ integrated via `healthMetricsAdjustment()`

### Implementation Priority

1. ~~Sleep stages (modify existing sleep code, high-value quick win)~~ ✅
2. ~~Cardio recovery (new metric, strongest single mortality predictor after VO2 max)~~ ✅
3. ~~Breathing disturbances (apnea detection, simple addition)~~ ✅
4. ~~Time in daylight (new metric, easy sync)~~ ✅
5. ~~Sync already-requested-but-unused types (stand time, basal energy, distance, walking speed)~~ ✅
6. ~~Gait engine (new engine, more complex but high long-term value)~~ ✅
7. New correlation charts (Alcohol → Sleep chart wired up; 6 remaining)
8. ~~Death clock enhancement with new factors~~ ✅

## Backlog

- [x] VoiceOver testing pass on iOS

## Not Porting (web-specific)

- Apple Health XML/JSON file import (replaced by native HealthKit)
- Server-side API calls (all local/on-device)
- WebSocket progress updates
