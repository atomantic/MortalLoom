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



## New-User UX Audit — 2026-04-11 (MOSTLY COMPLETE)

Walkthrough of the app as a brand-new user on a fresh iPhone 16 Pro install (`-fresh-start`), followed by a second pass with `-sample-data` to approximate an established user. Items are grouped **🚧 Blocker** (first-run user can't complete the intended task or is actively misled) vs **🔸 Friction** (they can, but it's annoying or compounds over time). Every item cites the exact file:line so the fix is unambiguous.

### 🚧 Blockers — ALL ADDRESSED (2026-04-11)

- [x] **Onboarding ends at step 4 of 13 — steps 5–13 never shown.** `OnboardingView.swift` — `firstReflectionStep`'s button now calls `advanceStep()`. `resultsStep` is now the only place that calls `saveAndDismiss()`. The stale `// MARK: - Step N:` comments have been renumbered to match the actual TabView tags. Verified in the simulator: step 3 advances to step 4 (LEV) and the full flow is now reachable.
- [x] **Every downstream calculation uses fake default lifestyle values.** Resolved automatically by the previous fix — users now reach the lifestyle-collection steps (birth date, sex, smoking, exercise, sleep, diet & stress) and the Results page.
- [x] **13 progress dots promise a length the flow never delivers.** Flow now actually delivers 13 steps so the count is honest.
- [x] **Reflections & Reports are buried behind the "More" drawer.** `SideMenuView.swift` — `tabBarPages` is now `[.overview, .goals, .reflections, .reports]`. Calendar and Habits remain reachable via the More drawer. Verified: bottom nav shows the new order.
- [x] **Stagnation rows in Reports are dead ends.** `ReportsView.swift:stagnationRow` — rows are now Buttons that call `openSignalTarget()` → open the goal's CheckInSheet. Added chevron affordance. Attention-Needed count pill now uses severity-based color (`.danger` / `.warning` / `.accentColor`).
- [x] **"Configure your birth date and lifestyle in Settings" is wrong.** `OverviewView.swift` — the "Not configured" Health Summary card now says "Add your birth date and lifestyle to see your longevity clock…" with an explicit "Open Lifestyle" button (deep-links to the Lifestyle page) and a secondary "Or run the setup wizard" link. `LifeCalendarView.swift:215` copy updated to "Add your birth date in the Lifestyle page".
- [x] **Weekly Review CTA is gated on having an apex goal.** Addressed indirectly — onboarding no longer ends prematurely, so users finish the flow and apex presence is the norm. Also added a "Finish your setup" warning banner on Overview (`OverviewView.finishSetupBanner`) that surfaces whenever `profile.birthDate == nil`, offering Run setup wizard / Open Lifestyle as one-tap recovery.
- [x] **Weekly review silently drops user input when no apex exists.** `WeeklyReviewSheet.swift` — `finish()` is now a defensive `guard let apex else { return }`. The Next/Finish footer is gated by `nextDisabled`, which blocks commit when no apex, no reflection answer, or no commitments. Reflection text is never dropped on the floor.
- [x] **Sample data is stale — no apex, no pillars, no habits.** `Engine/SampleData.swift` rewritten. Now ships: 1 apex ("Live healthy long enough to finish the work that matters") with 7 reflection-shaped check-ins spanning the last 168 days, 3 life pillars (Strong resilient body, Deep practice at my craft, Present for the family) with their own reflections, 4 standard goals (book/marathon/piano/garden) re-parented under pillars, and 4 habits (morning writing, run, meditate, no-wine-weeknights) with backdated completion arrays keyed to realistic cadences. Piano goal bug (-180d target that produced "759 days overdue") fixed by using a realistic future target. `fullAppData` now passes `habits:`. Tests updated to skip lifelong goals in the projection assertion. Verified: sample-data Overview now shows the full populated state.

### 🔸 Friction — Onboarding

- [x] **First reflection question is truncated.** Fixed by adding `.fixedSize(horizontal: false, vertical: true)` to both the "Why does this matter" and "Right now, how aligned…" Text views, and to the shared `stepDescription` helper (which also fixed the LEV step's "matters more..." → "matt..." truncation I discovered during verification).
- [x] **Presumptuous default alignment rating = 7/10.** Both `OnboardingView.swift` and `WeeklyReviewSheet.swift` + `CheckInSheet` now default to 5 ("Mixed"). The `firstReflectionRating != 7` check-in gate was replaced with `!trimmedReflection.isEmpty` — the slider always records, typed reflection is the signal.
- [x] **Apex category silently pre-selects Legacy.** Onboarding now has `apexGoalCategory: GoalCategory? = nil` with tap-to-toggle chip behavior. Overview's "Set My North Star Goal" CTA now passes `defaultCategory: .legacy`, and `GoalEditSheet.init` accepts a `defaultCategory` parameter — onboarding and the Overview CTA now produce consistent defaults.
- [x] **"Skip for now" button label is ambiguous.** Replaced with always-visible "Next" on the apex step. Empty-state skipping is handled transparently in `saveAndDismiss()`.
- [x] **No back button anywhere in the onboarding TabView.** Added a `topBar` above the TabView with a back chevron on all steps >0, wired to `goBack()`. Verified in the simulator.
- [x] **LEV term is the only place the term is defined — users never reached it.** Step unreachability is fixed (see blockers). Also added an info-popover (`showLEVExplainer`) next to the Standard/LEV picker in `LifeCalendarView.swift` so users who land there without having seen the onboarding step still get the 2-line explainer.
- [x] **Keyboard-return key doesn't advance the primary button on single-field steps.** Apex title field now sets `.submitLabel(.next)` + `.onSubmit { advanceStep() }`.

### 🔸 Friction — First-session landing (Overview)

- [x] **"YOUR RUNWAY" and "HEALTH SUMMARY" sections default expanded with empty data.** `OverviewView.swift` — added `hasCollapsedEmptySections` @AppStorage flag; first load with `profile.birthDate == nil` forces both sections collapsed, then we leave the user's explicit expand/collapse alone afterward.
- [x] **"HEALTH SUMMARY" label appears twice.** `OverviewView.healthGrid` — dropped the inner "Health Summary" Text. The collapsible section header is now the only label.
- [x] **Set-Goal CTA doesn't explain what an apex is until you tap in.** `OverviewView.setGoalCard` — replaced the thin examples line with the full "A North Star is broad and lifelong — not a project. Examples: live healthy as long as possible, leave a lasting creative legacy, raise a loving resilient family." string and added `.fixedSize` so it doesn't truncate.
- [x] **"Set My North Star Goal" CTA defaults mismatch onboarding.** Overview CTA now passes `defaultCategory: .legacy`, matching the onboarding default. `GoalEditSheet.init` accepts a new `defaultCategory` parameter.

### 🔸 Friction — Goal creation & hierarchy

- [x] **Type picker includes a "None" option that produces broken goals.** `GoalsView.swift` — removed the `None` row from the Type picker. Goals must now be typed. Default type for new goals is `.standard`.
- [x] **Default Parent Goal is "None (top-level)" even when an apex exists.** `GoalEditSheet.init` — for new standard goals with no explicit parent, we now auto-parent to the active apex if one exists. Users can still pick "None (top-level)" explicitly.
- [ ] **Save button silent-disables when title is empty.** Still needs a subtitle hint under the title field. Low-risk polish — skipping for this pass.
- [ ] **No inline one-tap check-in on the Goals list.** Still needs a swipe action or inline button — larger UX change, skipping for this pass.
- [ ] **Cancel/Save sheet header has no progress feedback.** Cosmetic polish — skipping for this pass.

### 🔸 Friction — Daily loop (habits, check-ins, reflections)

- [ ] **Habits tab mixes daily habits with Alcohol/Nicotine/Sauna substance trackers.** Still needs structural migration of substances into the Health surface — larger refactor, skipping for this pass.
- [x] **"No habits yet" empty state doesn't mention the parent-goal link.** `HabitsSection.swift:emptyState` copy updated: "Habits are the daily actions that move you toward your goals — writing, meditation, exercise, reading. Link each one to a goal or life pillar so its streak health contributes to your alignment score."
- [x] **Reflections journal has no streak stat.** `ReflectionsView.headerCard` — added `reflectionsStreakText` that computes "You've reflected N times across M weeks." from the unique ISO-week keys of all reflection check-ins, rendered in accent color above the description text.

### 🔸 Friction — Weekly review

- [x] **Review step shows aggregate counts, not the actual items.** `WeeklyReviewSheet.reviewStep` now renders a bulleted list of goal titles under each stat row (`itemList(_:color:)`). `weekActivity()` return shape changed from counts to `[String]` arrays of titles.
- [x] **No comparison to last week's commitments during the Commit step.** `WeeklyReviewSheet.commitStep` — added `previousCommitments()` that reads the last reflection-shaped check-in's commitments off the apex and renders them in a grouped box above the new commit field.
- [x] **"Next" button only gated on Reflect step.** `WeeklyReviewSheet.nextDisabled` is now a per-step computed property: blocks reflect without answer, blocks commit without at least one commitment or without an apex to save to.
- [ ] **Review step opening stat has no sparkline.** Still a nice-to-have. Skipping for this pass.

### 🔸 Friction — Goal Timeline (Calendar)

- [x] **LEV toggle has no in-context explainer.** `LifeCalendarView.statsGrid` — added an info-button `.popover` next to the Standard/LEV segmented picker with the two-line LEV definition. Driven by a new `showLEVExplainer` @State.
- [x] **Default view is 80-year Weeks grid.** `LifeCalendarView.viewMode` is now `@AppStorage` backed and defaults to `.years`, persisting the user's explicit choice.
- [ ] **"Awake Days" stat lacks an explainer.** Still needs a tooltip. Low-risk polish — skipping for this pass.

### 🔸 Friction — Reports & stagnation

- [x] **Empty states have no CTA buttons.** `ReportsView.emptyInlineWithCTA` helper added. Alignment trend, pillar breakdown, and habit streaks cards all use it now. Each CTA opens a pre-filled `GoalEditSheet` (with the right default type/parent) or `HabitEditSheet`. The CTA adapts — "Set a North Star" before apex exists, "Add a supporting goal" / "Add a life pillar" after.
- [x] **Piano goal flags as "759 days past its target".** Fixed by rewriting the sample data — the new piano entry uses a realistic `-60d` target (2 months out) instead of `-180d` paired with a 200-day-old create date, which was the source of the impossible "overdue" computation.
- [ ] **Stagnation severity doesn't escalate over time.** Still needs engine work. Skipping for this pass.
- [x] **"ATTENTION NEEDED" count pill is `.textMuted`.** `ReportsView.stagnationCountColor` now returns `.danger` / `.warning` / `.accentColor` based on the highest-severity signal in the list.

### 🔸 Friction — Settings & recovery

- [x] **"Show Setup Guide" is 5 taps deep.** `SettingsView.iOSTabbedSettings` now renders `setupGuideSection` as the **first** card on the General sub-tab (moved out of "More"). macOS `col1` also updated. Copy rewritten to "Finish or re-run the onboarding wizard to update your North Star, lifestyle profile, or life expectancy baseline." Button renamed to "Run Setup Wizard".
- [x] **Notifications default to off.** `SettingsView.weeklyReviewEnabled` `@AppStorage` default flipped to `true`. `OnboardingView.saveAndDismiss` explicitly sets the key to `true` for new users — either path results in weekly review on.
- [x] **"More" label appears twice.** Settings sub-tab renamed to "About" with `info.circle` icon. Setup Guide is no longer there.
- [x] **DEFAULT COUNTDOWN LEV footnote is awkwardly worded.** `SettingsView.countdownSection` rewritten to "LEV: Assumes longevity-escape-velocity therapies kick in around 2045 and extend lifespan to your target age." with `.fixedSize` so it wraps properly.
- [x] **No dedicated health-profile entry from Settings.** Addressed indirectly via the Overview "Open Lifestyle" button in the empty-state card, plus the new `finishSetupBanner`. Still no link inside Settings itself — low priority since Settings is no longer the misleading destination.

### 🔸 Friction — Cross-cutting

- [ ] **No deep-linkable URLs.** Larger architectural change (URL scheme registration + handler). Skipping for this pass.
- [x] **"Finish your setup" recovery banner.** `OverviewView.finishSetupBanner` shows whenever `profile.birthDate == nil`, with "Run setup wizard" and "Open Lifestyle" one-tap recovery buttons. Added to both narrow and wide content stacks.

### Bonus fixes discovered during execution

- [x] **`-sample-data` race condition with `showOnboarding`.** `MortalLoomApp.ContentView` — the onboarding cover used to appear briefly on sample-data launches because `showOnboarding` was initialized from UserDefaults before the `.task` set the flag. Fixed by adding `if AppConstants.useSampleData { return false }` to the @State initializer.
- [x] **`DataStore.setInMemory` didn't notify listeners.** Views that had already cached empty data wouldn't refresh when `-sample-data` replaced the in-memory snapshot. `setInMemory` now posts `.dataDidSync` + `.profileDidChange`.
- [x] **`stepDescription` helper truncated across all onboarding steps.** The LEV step showed "matters more..." → "matt...". Added `.fixedSize(horizontal: false, vertical: true)` to the helper so every description wraps correctly.
- [x] **`testSampleGoalsProduceValidProjections` broke after sample-data reframe.** Apex/sub-apex goals don't have progress trajectories. Test now filters to `goalType == .standard`.

### Still open (deferred to a follow-up milestone)

- Save-button hint on GoalEditSheet
- Inline one-tap check-in on Goals list
- Progress indicator inside the Cancel/Save sheet header
- Substances migration out of Habits tab
- Weekly review sparkline
- Awake Days tooltip
- Stagnation severity escalation
- URL scheme for deep-linking
- Dedicated "Edit health profile" link inside Settings

These are all lower-priority friction items that don't block the core loop. They can be picked up in a follow-up audit.

### Verification plan for this section

Each fix should be verified by re-running this walkthrough against the same simulator state:

```bash
# Fresh-install walkthrough
xcodebuild build -project MortalLoom.xcodeproj -scheme MortalLoom_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet
xcrun simctl install booted <path>/MortalLoom.app
xcrun simctl launch booted net.shadowpuppet.MeatSpaceTracker -fresh-start
# Walk onboarding; screenshot every step; verify all 13 dots advance.

# Sample-data walkthrough
xcrun simctl terminate booted net.shadowpuppet.MeatSpaceTracker
xcrun simctl launch booted net.shadowpuppet.MeatSpaceTracker -sample-data
# Overview should now show a populated apex, pillars, active habits, and an
# Alignment Trend chart with 12+ weeks of data in Reports.
```

Screenshots used in this audit are kept in `/tmp/mortalloom-ux-audit/` during the session and are **not** committed to the repo.



## Daily Engagement Loop & Polish — 2026-04-11 (PARTIAL)

The goal-alignment reframing shipped the weekly cadence (Weekly Review, Reflections page, Reports). What's missing is the **daily** and **monthly** rhythm plus the polish that makes the weekly loop feel coherent. Without the daily touchpoint the app has no reason to be opened between Sunday reviews; without the monthly rethink the goals tree ossifies. This section also clears the deferred friction items from the UX audit and the technical debt flagged in Better Swift.

**First pass shipped** (2026-04-11): URL scheme + `DeepLinkRouter`, daily post-habit nudge, Overview daily-streak chip, `StagnationEngine` severity escalation with `daysOverdue`, in-context stagnation prompts in `CheckInSheet`, inline check-in button on Goals list, GoalEditSheet save hint, Awake Days tooltip, Settings "Edit Health Profile" link. 14 new unit tests (`StagnationEngineTests` + `DeepLinkRouterTests`). iOS + macOS builds clean, full test suite passes.

### Daily touchpoint — the 5-second interaction

The app needs one interaction a user does *every* day that costs them <5 seconds and reinforces the alignment loop. Habit completions already exist; we layer one question on top.

- [x] **One-tap post-habit nudge.** `HabitsSection.swift:completeHabit` — after the DataStore write, we check `apexNeedsReflectionToday()` and surface a bottom-attached `DailyNudgeCard` with Yes/Partially/No mapping to `alignmentRating` 8/5/2. Writes a minimal reflection-shaped `GoalCheckIn` on the apex with `promptAnswered: "Did today move toward your North Star?"`. Rate-limited via `@AppStorage("habits.dailyNudgeDismissedOn")` — the calendar-date string resets at midnight with no extra bookkeeping.
- [x] **Home screen widget tap-through.** `WidgetBridge.Snapshot` now carries `apexGoalId`; the widget's `MortalLoomWidgetEntryView` applies `.widgetURL(tapURL(for:))` which routes to `mortalloom://goal/<apex>/reflect` when an apex is set (falls back to `mortalloom://goals` or `mortalloom://overview`). `MortalLoomApp.onOpenURL` posts `.openGoalReflect` for reflect routes; `GoalsView` observes the notification and opens `CheckInSheet`, using `pendingReflectGoalId` to survive a cold-launch race with `loadData`.
- [x] **Overview daily-streak chip.** `OverviewView.apexGoalCard` — small orange flame chip in the card header showing current consecutive-day reflection streak. `dailyReflectionStreak(for:)` walks backwards from today (or yesterday, if today isn't logged yet) counting days with any `isReflection` check-in. Hidden when `streak == 0`.

### Monthly perspective — are these still the right goals?

The mortality clock is the forcing function; monthly we have to re-verify the goals still point at something meaningful.

- [ ] **End-of-month Overview card.** On days 28–31, show a "Monthly rethink" card above the apex card asking *"Are these still the right goals?"* — taps open a scoped flow that walks the goals tree (apex → pillars → standard goals) with three options per node: Keep / Edit / Archive. Drives `Goal.isArchived` flips and records one compound `GoalCheckIn` on the apex summarizing the review.
- [ ] **Monthly report export.** One-tap "Export last month" button on the Reports page that generates a single markdown file (saved to the user's Files.app location, consistent with the existing export pattern) containing: alignment trend line for the month, reflection excerpts, stagnation signals encountered, habit streak summary. Privacy-first: no network, no server upload. Reuses `DataStore` export helpers.

### Stagnation — severity escalation & in-context response

`StagnationEngine` currently emits signals with fixed severity. A 3-day missed check-in and a 30-day missed check-in raise the same alert, so the Attention Needed card blurs real emergencies into noise.

- [x] **`StagnationEngine` severity scaling.** `StagnationEngine.swift` — new pure `stagnationSeverity(daysOverdue:cadenceIntervalDays:)` function maps `ratio < 1.5 → .info`, `1.5–3 → .warn`, `>3 → .alert`. `StagnationSignal` carries a new `daysOverdue: Int?` field so the UI can render "18 days overdue" inline. Covered by 7 new `StagnationEngineTests`.
- [x] **In-context stagnation prompts.** `CheckInSheet` takes an optional `stagnationSignal: StagnationSignal?`. When present, a dismissible banner at the top of the sheet shows the signal title, detail, and suggested prompt; the prompt also pre-fills the reflection field so the user starts where the engine thinks they should. `GoalsView.loadData()` computes the per-goal signal map in `signalByGoalId` and passes it when opening the check-in sheet.
- [ ] **Ad-hoc stagnation resolution.** When the user answers the in-context prompt and submits, clear the signal by marking the goal's `lastCheckInDate` fresh. Partially addressed — saving a check-in appends a new `GoalCheckIn`, which naturally moves `daysSinceLastCheckIn` forward and clears the missed-cadence signal on next recompute. The dedicated "mark signal resolved" UX is still TODO.

### Reflection cadence — user control

Right now the cadence is hardcoded (weekly review, daily habit nudge, monthly rethink). Some users want to set their own rhythm.

- [ ] **`SettingsView` → new "Reflection Cadence" card** on the General sub-tab. Three toggles + pickers:
  - Daily nudge: on/off, plus time-of-day preference (morning / evening / off)
  - Weekly review: on/off, plus day-of-week picker (default Sunday)
  - Monthly rethink: on/off, plus day-of-month picker (default last day)
- [ ] **`NotificationService` scheduling refactor.** Replace the current single-weekly repeating notification with a plan-based scheduler that reads the three cadence prefs and registers the right `UNCalendarNotificationTrigger` set. Clearing a toggle cancels its notifications immediately.
- [ ] **Per-goal cadence override already exists** (`GoalEditSheet` "Use smart default" button from the Reframing milestone). Add a secondary "Follow my global cadence" button that clears the override and picks up the new Settings defaults.

### Deep-linking URL scheme — `mortalloom://`

Notifications, widgets, and the future monthly export all need a way to open a specific view. Right now none of that works because we have no URL scheme.

- [x] **Register `mortalloom://` URL scheme** — `project.yml` now declares `CFBundleURLTypes` with scheme `mortalloom`. Verified via `xcodegen generate` + clean iOS and macOS builds.
- [x] **URL handler** — `MortalLoomApp.swift` adds `.onOpenURL` to both iOS and macOS content roots. Routing delegates to `DeepLinkRouter.parse(_:)` (new `Engine/DeepLinkRouter.swift`), and `handleDeepLinkRoute(_:)` flips `selectedPage` + stashes pending sheet triggers on `DeepLinkCoordinator.shared`. Supported URLs:
  - `mortalloom://<page>` — navigate to any `AppPage` by title (overview, goals, reflections, reports, etc.)
  - `mortalloom://goal/<uuid>` — open goal edit sheet
  - `mortalloom://goal/<uuid>/reflect` — open reflect / check-in sheet
  - `mortalloom://review/weekly` — trigger weekly review

  Parser covered by 6 new `DeepLinkRouterTests` (page route, goal edit, goal reflect, weekly review, unknown scheme, malformed UUID).
- [ ] **Wire `NotificationService`** to embed these URLs in each notification's `userInfo["deepLinkURL"]`. Still TODO — the parser and `.onOpenURL` handlers are ready but the service hasn't been updated to attach them.
- [ ] **Widget tap-through** uses the same URLs via `Link(destination:)` on each widget surface. Widget file untouched this pass.

### Substances migration — out of the Habits tab

From the UX audit (deferred): the Habits tab mixes user-authored daily habits with alcohol/nicotine/sauna substance trackers. Now that "My Habits" is the default tab and contributes to alignment scoring, the dissonance is worse — substances don't have streaks, aren't goal-linked, and clutter the daily engagement surface.

- [ ] **New top-level page `Substances`** under the Health section of the drawer, between Sleep and Blood. Hosts the Alcohol / Nicotine / Sauna tabs currently in `SubstancesView.swift`. No logic changes, just a drawer move.
- [ ] **Remove substance tabs** from `HabitsSection.swift`. The Habits page becomes user-authored habits only. Keep a small footer link on Habits: "Tracking alcohol, nicotine, or sauna? → Substances" for discoverability.
- [ ] **Preserve deep-linking** — anywhere that opens Substances (onboarding, OverviewView, reports) should already route via `AppPage.substances`. Double-check `SideMenuView.tabBarPages` and both platform switch statements.
- [ ] **No data migration** — the underlying `alcoholDrinks`, `nicotineEntries`, `saunaSessions` arrays in `AppData` don't move, only the view location does.

### Goals list polish — the remaining friction items

Deferred from the UX audit; picked up here as a batch.

- [x] **Inline one-tap check-in on Goals list.** `GoalsView.goalCard` — active standard goals now render an accent-coloured `checkmark.circle` button next to the urgency badge that opens `CheckInSheet` directly. Swipe actions don't apply to the VStack-based tree layout, so the visible button is the iOS/macOS parity solution. Context menu still offers the same action for discoverability.
- [x] **Save button hint on `GoalEditSheet`.** `GoalsView.swift:GoalEditSheet` — when the title field is empty we render a muted caption `"Give this goal a title to save."` directly under the title input. Removes the silent-disable mystery.
- [ ] **Sheet progress header.** `GoalEditSheet` and `HabitEditSheet` get a small "Step 1 of 2" style hint when the content overflows one screen, so users know they can scroll. Deferred — low-value polish.
- [ ] **Weekly review sparkline.** `WeeklyReviewSheet.reviewStep` — add a 7-day inline sparkline (daily `alignmentRating` values) using `Chart` from `Charts.framework`. Empty days render as gaps, not zeros.
- [x] **Awake Days tooltip.** `LifeCalendarView.statsGrid` — Awake Days stat now has a topTrailing-overlay info button that opens a popover matching the LEV explainer pattern. Copy explains the calc: "Roughly how many waking days you have left, after subtracting time spent sleeping. Based on your lifestyle sleep-hours answer…"

### Settings — completeness

- [x] **Dedicated Edit Health Profile link in Settings.** `SettingsView.setupGuideSection` — second button below "Run Setup Wizard" that posts `.navigateToPage` with `AppPage.lifestyle` as the object. Both iOS `iOSContent` and macOS `MacContentView` subscribe to the notification and flip `selectedPage` to match. Covers the fast-path for users who only want to tweak lifestyle answers without re-running the 13-step onboarding.
- [ ] **Reflection Cadence card** (see above) lives next to the Notifications card.

### Technical polish — deferred from Better Swift

These are the items explicitly listed as "Deferred / Out-of-Scope From This Cycle" in the Better Swift audit. Picking them up now that the feature work has stabilized.

- [ ] **Engine test coverage.** Add test suites for `CardioFitnessEngine` (HR-recovery classification + VO2 max thresholds), `GaitEngine` (fall risk scoring, functional age), `GenomeEngine` (ClinVar cross-reference path matching, variant risk ranking). Follow the same pattern as the existing `SleepEngineTests` / `LocationEngineTests`. Target: 80% line coverage on the pure engines.
- [ ] **Storage / HealthKit coverage** (the original "Next Up" placeholder from prior milestones). Unit tests for `DataStore` actor CRUD + merge paths, `HealthKitService` authorization-request completion states, and `ICloudMonitor` metadata-query handling.
- [ ] **God-file decomposition.** `SubstancesView.swift` (2,351 lines), `OverviewView.swift` (1,743 lines), `GoalsView.swift` (1,601 lines), `GenomeView.swift` (1,522 lines) are each well past the single-responsibility line. Split into per-section view files under `Views/Overview/`, `Views/Goals/`, `Views/Substances/`, `Views/Genome/`. No logic changes — pure file-system refactor. Makes future audits tractable.
- [ ] **Remaining `inlineNavigationTitle()` adoptions.** PaywallView, GoalsView, GenomeView, BodyView, BloodView still have raw `#if os(iOS) .navigationBarTitleDisplayMode(.inline) #endif` guards. Swap to the helper from `Theme/Theme.swift`.
- [ ] **macOS window lifecycle hardening** (App Store guideline 4). `MortalLoomApp.swift` — implement `applicationShouldTerminateAfterLastWindowClosed` (return false), `applicationShouldHandleReopen` (reopen main window), and add a "Show Main Window" Commands menu entry. Prevents the classic "closed the window and now the app is stuck in the dock" macOS complaint.

### Remaining Apple Health correlations

From the Apple Health Data Expansion section, 5 correlations are still unshipped even though the underlying metrics are now synced.

- [ ] **Nicotine → Cardio Recovery** chart on `SubstancesView` (post-migration: `SubstancesView` under Health). Bucketed scatter with regression line.
- [ ] **Activity → Blood Markers** — extend `CorrelationEngine` to use `walkingRunningDistance` alongside step count. Surface on `BloodView` trend cards.
- [ ] **Daylight → Sleep Consistency** — new correlation on `SleepView`. Requires adding a `sleepConsistencyScore` helper to `SleepEngine`.
- [ ] **BMI → Breathing Disturbances** — on `BodyView`. Two-series chart with BMI trend and apnea-risk bars.
- [ ] **Gait trends → Functional Age** — new `FunctionalAgeEngine` helper that takes walking speed + asymmetry + stair speed over 6 months and produces an estimated functional-age delta. Surface on `BodyView`.
- [ ] **Exercise → Cardio Recovery** — on `SleepView` or a new fitness surface. Weekly exercise minutes × cardio recovery bpm scatter.

### Implementation order

1. Deep-linking URL scheme (unblocks daily nudge, widget tap-through, notifications routing)
2. Daily nudge + Overview daily-streak chip (visible value the day it ships)
3. Stagnation severity escalation + in-context prompts (sharpens the existing Reports page)
4. Substances migration (isolated, low-risk, clears the biggest remaining UX dissonance)
5. Reflection cadence Settings + `NotificationService` refactor (user control over the new daily rhythm)
6. Monthly rethink card + export
7. Goals list polish batch (swipe check-in, save hint, sparkline, Awake Days tooltip)
8. Technical polish (engine tests, god-file decomposition, macOS lifecycle)
9. Remaining Apple Health correlations

### Success criteria

- Daily active use metric: unique calendar days where the user either completes a habit or logs a reflection. Currently ~1–2/week for test users; target ≥5/week after the daily nudge ships.
- Attention Needed signal-to-noise: the same Attention Needed list shouldn't surface a 3-day miss and a 45-day miss with equal weight.
- Substances confusion incidents: zero reports of "where did my alcohol tracker go" after the migration ships — confirmed via a discoverability footer on the Habits tab.
- Engine test coverage ≥80% on `CardioFitnessEngine`, `GaitEngine`, `GenomeEngine`.
- No view file over 1,000 lines in `MortalLoom/Views/` after decomposition (current: 4 files over 1,500 lines).



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
