# Development Plan

For project mission and milestones, see [GOALS.md](./GOALS.md).
For completed work, see [DONE.md](./DONE.md).

## Next Up

1. **Monthly rethink card + export**: End-of-month Overview card walking the goals tree with Keep/Edit/Archive per node (drives `Goal.isArchived`, records one compound `GoalCheckIn` on apex). One-tap "Export last month" markdown report from Reports — alignment trend, reflection excerpts, stagnation signals, habit streak summary. Privacy-first, reuses `DataStore` export helpers.
2. **Reflection Cadence Settings**: New General sub-tab card with on/off + picker for daily nudge (time of day), weekly review (day of week), monthly rethink (day of month). Refactor `NotificationService` to a plan-based scheduler reading the three prefs and registering matching `UNCalendarNotificationTrigger`s. Add "Follow my global cadence" button on `GoalEditSheet` to clear per-goal override.
3. **Genome Phase 6 — iPad split layout**: `GenomeSplitView` `NavigationSplitView` (sidebar / list / detail), detail-sheet content embedded as right pane on iPad regular size class.
4. **Genome Phase 7 — Visit Mode**: focused two-column layout (priorities list + current finding with live notes + checkboxes + Save & Next), `GenomeVisitNotesPane` on iPad.
5. **Genome Phase 8 — PDF export**: `GenomeReportPDF` via PDFKit — pre-visit prep PDF (top priorities + drug-response variants + talking points) and post-visit summary PDF (with captured notes appended); AirPrint via share sheet.

## Backlog

- [x] [hk-corr-daylight-sleep-consistency] **Daylight→Sleep Consistency**: 7-day sliding-window scatter of average daylight minutes vs sleep consistency score (CV-based), Pearson r badge, plain-language interpretation card on SleepView. New `daylightConsistencyCorrelation` / `daylightConsistencyCorrelationCoefficient` in `SleepEngine`.
- [ ] [hk-corr-nicotine-cardio-recovery] **Nicotine→Cardio Recovery**: scatter on Substances pairing daily nicotine units with next-day `cardioRecovery` (HR drop in 1 min post-exercise from HealthKit). Add a `nicotineCardioRecoveryCorrelation` function to `CorrelationEngine` analogous to `alcoholSleepCorrelation`.
- [ ] [hk-corr-activity-blood-markers] **Activity→Blood Markers**: surface `avgDailyDistance` (already on `CorrelationDataPoint`) in `BloodView` correlation UI; consider promoting `distanceCycling` and total-active-distance as additional series.
- [ ] [hk-corr-bmi-breathing] **BMI→Breathing Disturbances**: two-series chart on `BodyView` overlaying historical BMI (from `BodyEntry.weight` + profile height) against `breathingDisturbances` per night to surface obesity↔apnea risk.
- [ ] [hk-corr-gait-functional-age] **Gait Trends→Functional Age**: new `FunctionalAgeEngine` synthesizing `walkingSpeed`, `walkingAsymmetry`, `stairSpeedUp`/`stairSpeedDown` into an age-adjusted functional-age estimate; surface on Body or Overview.
- [ ] [hk-corr-exercise-cardio-recovery] **Exercise→Cardio Recovery**: scatter / line chart pairing weekly `exerciseMinutes` with weekly average `cardioRecovery` — fitness-improvement feedback loop.
- [ ] **Storage/HealthKit test coverage**: `DataStore` actor CRUD/merge paths, `HealthKitService` authorization-completion states, `ICloudMonitor` metadata-query handling
- [ ] **God-file decomposition**: Split `SubstancesView.swift` (2,449), `GoalsView.swift` (1,990), `GenomeView.swift` (1,928), `OverviewView.swift` (1,886) into per-section files under `Views/<Page>/`. No logic changes.
- [ ] **macOS window lifecycle hardening (App Store guideline 4)**: `applicationShouldTerminateAfterLastWindowClosed` returns false, `applicationShouldHandleReopen` reopens main window, "Show Main Window" Commands menu entry
- [ ] **End-to-end deep-link wiring for sheets**: embed `mortalloom://` URLs in each notification's `userInfo["deepLinkURL"]`, AND finish the receiving side in `DeepLinkRouter` — sheet-presenting routes (`goalEdit`, `goalReflect`, `weeklyReview`) currently navigate to the owning page but don't open the target sheet (pending-sheet state is the open TODO at `Engine/DeepLinkRouter.swift:11`)
- [ ] **Per-goal stagnation polish**: dedicated "mark signal resolved" UX (currently signals self-clear on next compute); push-notification surfacing for raised signals
- [ ] **Pillar Dashboard CTAs**: "Add supporting goal" and "Add habit" buttons on the dashboard itself (currently must navigate back to GoalsView/HabitsView)
- [ ] **Remaining `.inlineNavigationTitle()` adoptions**: PaywallView, GenomeView, BodyView, BloodView (swap raw `.navigationBarTitleDisplayMode(.inline)` to the helper from `Theme/Theme.swift`; GoalsView already migrated)
- [ ] **Non-health pillar templates**: category-specific goal templates (creative projects, financial milestones, relationship rituals, legacy artifacts) so non-health pillars feel first-class

## Future / Ideas

- Sheet progress header on `GoalEditSheet`/`HabitEditSheet` for overflow-scroll discoverability
- Bottom tab bar rethink — currently `[Overview, Goals, Reflections, Reports]`; revisit once Reports settles
- Goal velocity chart and time-allocation analysis on Reports
- Habit streak heat map; yearly review export

## Not Porting (web-specific)

- Apple Health XML/JSON file import (replaced by native HealthKit)
- Server-side API calls (all local/on-device)
- WebSocket progress updates
