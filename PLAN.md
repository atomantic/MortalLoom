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

- [ ] **Apple Health correlations (5 remaining)**: Nicotine→Cardio Recovery (scatter on Substances), Activity→Blood Markers (extend `CorrelationEngine` with `walkingRunningDistance`), Daylight→Sleep Consistency (new `sleepConsistencyScore` in `SleepEngine`), BMI→Breathing Disturbances (two-series chart on Body), Gait Trends→Functional Age (new `FunctionalAgeEngine` from walking speed + asymmetry + stair speed), Exercise→Cardio Recovery
- [ ] **Storage/HealthKit test coverage**: `DataStore` actor CRUD/merge paths, `HealthKitService` authorization-completion states, `ICloudMonitor` metadata-query handling
- [ ] **God-file decomposition**: Split `SubstancesView.swift` (2,351), `OverviewView.swift` (1,743), `GoalsView.swift` (1,601), `GenomeView.swift` (1,522) into per-section files under `Views/<Page>/`. No logic changes.
- [ ] **macOS window lifecycle hardening (App Store guideline 4)**: `applicationShouldTerminateAfterLastWindowClosed` returns false, `applicationShouldHandleReopen` reopens main window, "Show Main Window" Commands menu entry
- [ ] **NotificationService deep-links**: embed `mortalloom://` URLs in each notification's `userInfo["deepLinkURL"]` so taps open the right surface
- [ ] **Per-goal stagnation polish**: dedicated "mark signal resolved" UX (currently signals self-clear on next compute); push-notification surfacing for raised signals
- [ ] **Pillar Dashboard CTAs**: "Add supporting goal" and "Add habit" buttons on the dashboard itself (currently must navigate back to GoalsView/HabitsView)
- [ ] **Remaining `.inlineNavigationTitle()` adoptions**: PaywallView, GoalsView, GenomeView, BodyView, BloodView (swap raw `#if os(iOS)` guards to the helper from `Theme/Theme.swift`)
- [ ] **Non-health pillar templates**: category-specific goal templates (creative projects, financial milestones, relationship rituals, legacy artifacts) so non-health pillars feel first-class

## Future / Ideas

- Sheet progress header on `GoalEditSheet`/`HabitEditSheet` for overflow-scroll discoverability
- Bottom tab bar rethink — currently `[Overview, Goals, Reflections, Reports]`; revisit once Reports settles
- Goal velocity chart and time-allocation analysis on Reports
- Habit streak heat map; monthly/yearly review export
- Daily nudge time-of-day picker (morning/evening/off)

## Not Porting (web-specific)

- Apple Health XML/JSON file import (replaced by native HealthKit)
- Server-side API calls (all local/on-device)
- WebSocket progress updates
