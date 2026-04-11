# Development Plan

For project mission and milestones, see [GOALS.md](./GOALS.md).
For completed work, see [DONE.md](./DONE.md).

## Goal Alignment Reframing — 2026-04-11 (ACTIVE)

GOALS.md was rewritten to reflect the real thesis: **MortalLoom is a goal alignment app where the mortality clock is the forcing function and health tracking is the runway extender.** Alignment keeps you from wasting time, longevity extends the time you have. Each reinforces the other.

This section tracks the work to bring the code in line with the reframed mission. It's large — expect it to span multiple milestones.

### Apex / North Star cleanup — COMPLETE (2026-04-11)

- [x] Slimmed the apex/sub-apex goal edit form: hidden deadline, text milestones, calendar scheduler, check-in frequency. Horizon locked to "Lifetime" for apex. Milestones replaced with a "Supporting Goals" section listing real child goals and an "Add supporting goal" button (nested sheet wired through `onAddChild` callback).
- [x] Replaced the Overview apex "Progress" bar with an **Alignment Score**: average `progressPercent` across active *standard* descendants of the apex. Empty state shows "Add supporting goals" prompt instead of a zero bar.
- [x] Rewired apex card CTA: "Schedule next work block" → "Add a supporting goal" / "Review supporting goals". Calendar scheduling is now gated to standard goals only (hidden in the apex/sub-apex edit form).
- [x] `GoalEditSheet.save()` forces `targetDate = nil`, clears text milestones, and skips auto-progress-from-milestones for lifelong goals.
- [x] Nav reorganization: **Goals** section (Overview, Goals, Calendar, Habits) leads the drawer. **Health** section (Body, Sleep, Blood, Lifestyle, Genome) follows. Both `SideMenuView` and `MacContentView` sidebar updated.

### Habits as daily engagement loop — COMPLETE (2026-04-11)

- [x] `Habit`, `HabitCompletion`, `HabitCategory`, `HabitKind`, `HabitCadence` models in `MortalLoom/Models/Habit.swift`. Streaks derived at read time from the completions array — no cached state to desync.
- [x] `AppData.habits` + `DataStore` CRUD (add/update/remove/logCompletion/removeCompletion). Merge-by-ID integrated into iCloud sync.
- [x] `HabitEngine` pure functions: `completionsInPeriod`, `currentStreak`, `targetHitRate`, `alignmentContribution`, `isStagnant`. Weekly cadences bucket by ISO week; daily by local day.
- [x] "My Habits" tab added to the Habits page (`HabitsSection.swift`). Default-selected tab for new installs. Existing Alcohol / Nicotine / Sauna tabs preserved intact.
- [x] Habitica-style habit cards with streak flame, 30-day hit rate, today's count, and a round tap-to-complete button. Optional parent goal link.
- [x] `HabitEditSheet` — icon + color picker (16 SF Symbols, 8 colors), build/break kind toggle, category, daily/weekly cadence with target count, parent goal picker, archive toggle.

### Unified check-in model (reflection + progress) — COMPLETE (2026-04-11)

- [x] `GoalCheckIn` extended with optional `alignmentRating`, `blockers`, `commitments`, `promptAnswered`. Back-compat decoder handles pre-existing check-ins. `isReflection` helper distinguishes reflection-shaped check-ins for filtering.
- [x] `ReflectionPrompts` curated library (general, monthly, stagnation buckets) with `pick(excludingRecent:)` rotation.
- [x] `CheckInSheet` branches by goal type:
  - **Standard goals**: progress slider + milestone checkboxes + note (existing behaviour preserved).
  - **Apex / sub-apex**: alignment rating 1–10, guided prompt picker with rotate button, blockers list, commitments list, note. Progress slider hidden.
- [x] Apex card gets a prominent "Reflect" button. Sub-apex reachable via context menu ("Reflect").
- [x] Recent reflections list inside the check-in sheet shows rating history for lifelong goals.

### Configurable cadence and smart stagnation thresholds — PARTIAL (2026-04-11)

- [x] `GoalEngine.defaultCheckInIntervalDays(for:)` derives cadence from goal timeline. 7-day goal → 2-day cadence; 30-day goal → every 5; 30+ day goal → weekly; lifelong → 14 day reflection default.
- [x] `StagnationEngine` pure function returning `[StagnationSignal]` sorted by severity. Detects: apex with no supporting goals, pillar with no concrete descendants, missed check-in cadence, projected deadline slippage (via `GoalEngine.project`), and habits missing cadence 3+ periods.
- [x] Each signal carries a `suggestedPrompt` from `ReflectionPrompts.stagnation` so the user always gets a way out of the stall.
- [ ] **Remaining**: per-goal threshold override ("mute this signal"), push-notification surfacing, cadence override UI in edit form (smart default is computed but not yet shown to the user).

### Reflections page — COMPLETE (2026-04-11)

- [x] `ReflectionsView.swift` — chronological journal grouped and filtered to check-ins with reflection content (filter pills: All / North Star / Pillars / Goals).
- [x] Each reflection card shows: goal title with type icon, date, alignment rating with color-coded label, prompt answered, note, blockers list, commitments list.
- [x] Empty state prompts the user to tap Reflect on their North Star.
- [x] New `AppPage.reflections` wired into drawer, macOS sidebar, and both platform switch statements.

### Reports page MVP — COMPLETE (2026-04-11)

- [x] `ReportsView.swift` with four widgets:
  - **Alignment trend chart**: 12-week line+area chart combining 70% standard-goal progress + 30% reflection ratings, plus week-over-week delta.
  - **Attention Needed (stagnation alerts)**: grouped list from `StagnationEngine` with severity icon, detail, and suggested prompt.
  - **Pillar alignment breakdown**: horizontal bars showing each life pillar's sub-alignment score.
  - **Habit streaks**: compact table of active habits with streak flame + 30-day hit rate.
- [x] New `AppPage.reports` wired into drawer, macOS sidebar, and switch statements.
- [x] **Overview mirror**: compact "Attention Needed" card on Overview (narrow + wide stacks) showing top 3 stagnation signals. Only renders when signals exist.
- [ ] **Later**: goal velocity chart, time allocation analysis, at-risk goal projections beyond the projection-slippage signal already in StagnationEngine, habit streak heat map, monthly/yearly review export.

### Pillar Dashboards — COMPLETE (2026-04-11)

- [x] `PillarDashboardView.swift` — drill-in detail for any sub-apex (life pillar).
- [x] Header with pillar title, notes, category, reflect CTA.
- [x] Pillar-level **sub-alignment** score = 70% average of active standard descendants + 30% habit streak health across linked habits (same weighting as the Overview apex rollup).
- [x] Supporting goals list with per-goal progress bars, tap to edit.
- [x] Linked habits section with streak + 30-day hit rate. Deep pillar ↔ habit link via `Habit.parentGoalId`.
- [x] Recent reflections list scoped to the pillar.
- [x] Opened from GoalsView via tap on any sub-apex in the hierarchy. Presented as a sheet with `NavigationStack` so inner edit/reflect sheets work naturally.
- [ ] **Remaining**: "Add supporting goal" / "Add habit" CTAs on the dashboard itself (currently must navigate back to GoalsView or HabitsView); time allocation summary (requires `TimeAllocationEngine` from the Calendar Integration phase).

### Next — Reflection flow (the core weekly loop)

The daily/weekly/monthly cadence is the app's heartbeat. Implementation lives on top of the unified check-in model and the Reflections/Reports pages above.

- [ ] **Daily lightweight nudge**: one-line prompt after the user logs a habit completion. "Did today move toward your North Star? Yes / Partially / No" — writes a light-touch `GoalCheckIn` with `alignmentRating` set, no other fields. Dismissible.
- [ ] **Weekly Review** *(substantive)*: guided 5-minute modal flow, triggered from Overview CTA or notification:
  1. Show last week's calendar blocks tagged to goals, plus progress deltas on active goals.
  2. Show current alignment score and week-over-week delta.
  3. Prompt the user to answer one of 3–5 rotating reflection prompts.
  4. Plan next week's work blocks: suggest slots for top-priority goals, let the user accept/modify/skip.
- [ ] **Monthly perspective** *(light)*: end-of-month card on Overview asking "Are these still the right goals?" — links to a monthly reflection entry and opens the goals tree for editing.
- [ ] **Ad hoc stagnation response**: when `StagnationEngine` raises a signal, surface a targeted reflection prompt ("You haven't logged progress on your Creative pillar in 23 days. What's blocking you?").
- [ ] **Configurable cadence**: user chooses daily/weekly/monthly rhythms in Settings → Reflection Cadence.

### Next — Calendar integration verification

Calendar ↔ goal tagging exists in `CalendarSchedulerSheet` but has not been tested end-to-end. Needs verification before Reports can trust "time allocation per pillar" data.

- [ ] Audit `CalendarSchedulerSheet` — confirm it writes a goal ID reference on the created calendar event (custom URL, notes field, or a local mapping table).
- [ ] Build a `TimeAllocationEngine` that reads recent calendar events and maps them to goals/pillars via the tag, producing minutes-per-pillar rollups.
- [ ] Surface time allocation on Pillar Dashboards and as a secondary Reports widget.
- [ ] Test on both iOS (EventKit) and macOS (EventKit) — the integration may differ.

### Later — Goal-centered Overview

The Overview currently leads with the Longevity Clock / LEV card. Under the reframed mission it should lead with **the North Star + Alignment Score + today's prompt** and treat longevity as a supporting strip.

- [ ] Reorder Overview so the apex/alignment card is the first card (both narrow and wide layouts). Partially done via recent commits; audit and finalize.
- [ ] Reposition Longevity Clock / LEV card as a "time remaining" strip rather than the hero.
- [ ] Make Health Summary collapsible / demotable for users whose North Star doesn't touch health.
- [ ] Goal-centered empty states for users with no apex set — today's empty Overview is still health-first.
- [ ] Surface Reports widgets (alignment this week + attention needed) in their compact form on Overview.

### Later — Cross-cutting features

- [ ] **Home screen widget**: alignment score + today's reflection prompt as a 1-tap entry point. Extends existing MortalLoomWidget.
- [ ] **Notifications**: weekly review reminder (opt-in), stagnation alerts as detected.
- [ ] **Onboarding extensions**: after the user names their North Star and first life pillar during onboarding, immediately prompt a first reflection ("Why does this matter to you?") to seed the journal and ground the experience. See also the `shadowpuppet-onboarding` skill for shared patterns across the net.shadowpuppet.* app family.
- [ ] **Non-health pillar support**: category-specific goal templates (creative projects, financial milestones, relationship rituals, legacy artifacts). Pillar dashboards make non-health pillars feel first-class.
- [ ] **Bottom tab bar rethink**: currently `[Overview, Goals, Calendar, Habits]`. With Reflections and Reports coming, consider `[Overview, Goals, Habits, Reports]` or similar. Defer decision until Reports ships.

### Implementation order and status

1. ✅ **Unified check-in model** — `GoalCheckIn` extended; CheckInSheet branches; Reflect button on apex.
2. ✅ **Smart cadence + `StagnationEngine` skeleton** — `defaultCheckInIntervalDays` + 5-signal engine.
3. ✅ **Habits expansion** — full custom habit model, My Habits tab, edit sheet, HabitEngine streak math.
4. ✅ **Reflections page** — read-only chronological journal with scope filters.
5. ✅ **Reports page MVP** — alignment trend, stagnation alerts, pillar breakdown, habit streaks.
6. ✅ **Pillar Dashboards** — per-pillar sub-alignment, supporting goals, habits, reflections.
7. ✅ **Overview Reports mirror** — compact Attention Needed card on Overview.
8. ✅ **Weekly Review flow** — 4-step guided modal triggered from Overview when due.
9. ✅ **Calendar integration** — `CalendarService` tags events with `mortalloom://goal/<uuid>` URL; `TimeAllocationEngine` rolls up minutes through the goal tree; Pillar Dashboards surface a 30-day time-allocated card.
10. ✅ **Overview restructure** — collapsible "Your Runway" and "Health Summary" sections with @AppStorage persistence. Goal-first hero (apex card + alignment + attention) leads.
11. ✅ **Widget alignment view** — Small and Medium widgets lead with North Star title + alignment score + today's prompt when an apex is set.
12. ✅ **Notifications** — `NotificationService` schedules repeating weekly-review reminder + reconciled one-shot stagnation alerts. Opt-in via Settings → General → Notifications.
13. ✅ **Onboarding reordered + first reflection** — North Star + first reflection step moved ahead of LEV / health questionnaire so longevity lands as "how to extend the runway for the thing you just named." Category picker swapped from truncating segmented control to a 3-column chip grid. Reflection rating is seeded as the first `GoalCheckIn` on the apex.
14. ✅ **Cadence override UI** — GoalEditSheet exposes "Use smart default" button that derives cadence from timeline.
15. ✅ **Per-goal signal muting** — `Goal.mutedSignals` array + toggles in GoalEditSheet. StagnationEngine filters muted signals before sorting.
16. ✅ **Fresh-start simulator mode** — `-fresh-start` launch flag for DEBUG builds: empty in-memory state, onboarding forced, no writes to disk or iCloud.

### Data migration safety (TestFlight → new fields)

All model changes this milestone are **additive with decodeIfPresent fallbacks**, so the TestFlight JSON file decodes cleanly:

- `AppData.habits: [Habit]` — decoded with `decodeIfPresent` default `[]`. A TestFlight file without this field loads as "no custom habits yet."
- `GoalCheckIn.alignmentRating / blockers / commitments / promptAnswered` — custom decoder uses `decodeIfPresent` with safe defaults (nil, [], [], nil). Old check-ins remain progress-only.
- `Goal.mutedSignals: [String]` — custom decoder uses `decodeIfPresent` default `[]`. Old goals have no muted signals.
- `WidgetBridge.Snapshot.apexTitle / alignmentScore / todaysPrompt` — the widget's copy of the Snapshot struct has a custom decoder that defaults these to nil. Old widget snapshot files (if still cached) decode without issue.

**No breaking changes** to existing fields. Your TestFlight habit data (alcohol, nicotine, sauna) is stored in `alcoholDrinks`, `nicotineEntries`, `saunaSessions` — none of which were touched this milestone. Restoring from backup or continuing with the upgraded build is safe.

### Fresh-start simulator usage

In Xcode simulator, edit the MortalLoom_iOS scheme → Run → Arguments → add `-fresh-start` under Arguments Passed On Launch. The app will:

- Skip iCloud monitoring entirely (no chance of touching your real container)
- Skip HealthKit sync
- Load `AppData.empty` in memory
- Force the onboarding flow to run on every launch
- Write no files to the local Documents directory

Remove the flag to return to normal mode. The `-sample-data` flag (pre-existing) still works the same way but seeds realistic fake data instead of empty state.



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
- **Longevity clock integration**: Adjust sleep impact beyond just hours — penalize consistently low deep sleep %
- **Implementation**: Add `deepSleepHours`, `remSleepHours`, `coreSleepHours` to `HealthMetricEntry`. Modify `dailySleepHours()` to return stage breakdown. Extend `SleepEngine` with stage quality rating.

#### 2. Cardio Recovery (HR Recovery after exercise)
- **What**: `HKQuantityTypeIdentifier.heartRateRecovery` — 1-minute HR drop after exercise
- **PortOS data**: `cardio_recovery` metric with bpm values
- **Longevity evidence**: Abnormal HR recovery (<12 bpm drop in 1 min) is associated with 4x cardiovascular mortality risk (Cole et al., NEJM 1999). One of the strongest single predictors of cardiac death.
- **Correlations**: Track improvement with exercise habits. Alcohol and nicotine impair recovery. VO2 max and HR recovery are complementary fitness markers.
- **Longevity clock integration**: Add to `CardioFitnessEngine` alongside VO2 max — poor recovery = mortality penalty
- **Implementation**: Add `cardioRecovery` to `HealthMetricEntry`. New classification in `CardioFitnessEngine`. Factor into health score.

#### 3. Walking Steadiness & Gait Metrics
- **What**: `walkingAsymmetryPercentage`, `walkingDoubleSupportPercentage`, `walkingSteadiness`, `stairSpeedUp`, `stairSpeedDown`, `walkingHeartRateAverage`
- **PortOS data**: Daily gait metrics from Apple Watch (asymmetry, double support %, stair speeds, walking HR)
- **Longevity evidence**: Walking speed is called "the 6th vital sign" — a strong independent predictor of mortality. Gait asymmetry and double support % predict fall risk (falls are a top-5 cause of death in 65+). Declining stair speed indicates functional capacity loss.
- **Correlations**: Track functional age trajectory. Correlate with body composition changes, blood markers (inflammation), and exercise habits.
- **Longevity clock integration**: Create a "functional fitness" score that adjusts healthspan estimate. Declining gait → shorter healthy years remaining.
- **Implementation**: Add `walkingAsymmetry`, `walkingDoubleSupport`, `stairSpeedUp`, `stairSpeedDown`, `walkingHRAverage` to `HealthMetricEntry`. New `GaitEngine` for fall risk classification and functional age estimation. MortalLoom already requests `walkingSpeed` and `walkingStepLength` but doesn't sync them — add these too.

#### 4. Breathing Disturbances (Sleep Apnea Detection)
- **What**: Apple Watch tracks breathing disturbances during sleep
- **PortOS data**: `breathing_disturbances` count per night
- **Longevity evidence**: Untreated sleep apnea increases cardiovascular mortality 2-3x, raises stroke risk, and accelerates cognitive decline. Elevated breathing disturbances (>15/hr) indicate moderate-to-severe apnea.
- **Correlations**: Correlate with alcohol (alcohol worsens apnea), BMI (obesity is primary risk factor), sleep quality, and blood pressure.
- **Longevity clock integration**: Persistent high breathing disturbances → mortality penalty and recommendation to get a sleep study
- **Implementation**: Add `breathingDisturbances` to `HealthMetricEntry`. Extend `SleepEngine` with apnea risk classification (AHI thresholds: <5 normal, 5-15 mild, 15-30 moderate, >30 severe).

#### 5. Time in Daylight
- **What**: `HKQuantityTypeIdentifier.timeInDaylight` — daily minutes of outdoor light exposure
- **PortOS data**: Per-minute daylight readings summed daily
- **Longevity evidence**: Circadian disruption is linked to metabolic syndrome, depression, and cancer risk (Lancet Psychiatry 2018). Daylight drives vitamin D synthesis, melatonin regulation, and mood. Low outdoor time correlates with myopia progression (relevant to eye health tracking).
- **Correlations**: Correlate with sleep quality/consistency, HRV, eye prescription changes, and mood/stress.
- **Longevity clock integration**: Chronic low daylight → stress and sleep quality proxy affecting lifestyle adjustment
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
| ~~Sauna → HRV/Sleep~~ ✅ | Sauna sessions × next-day HRV × deep sleep | Validate sauna's recovery benefit |
| Nicotine → Cardio Recovery | Nicotine mg × HR recovery bpm | Quantify nicotine's cardiac impact |
| Activity → Blood Markers | Steps + distance + exercise × blood panels | Strengthen existing CorrelationEngine |
| Daylight → Sleep Consistency | Daily daylight min × sleep consistency score | Circadian regulation feedback |
| BMI → Breathing Disturbances | Weight trend × apnea severity | Weight loss motivation tied to apnea |
| Gait Trends → Functional Age | Walking speed + asymmetry over months | Early decline detection |
| Exercise → Cardio Recovery | Weekly exercise min × HR recovery trend | Fitness trajectory validation |

### Longevity Clock Enhancements

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
7. New correlation charts (Alcohol → Sleep ✅, Sauna → HRV/Sleep ✅; 5 remaining)
8. ~~Longevity clock enhancement with new factors~~ ✅

## Backlog

- [x] VoiceOver testing pass on iOS

## Not Porting (web-specific)

- Apple Health XML/JSON file import (replaced by native HealthKit)
- Server-side API calls (all local/on-device)
- WebSocket progress updates
