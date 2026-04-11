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



## New-User UX Audit — 2026-04-11 (ACTIVE)

Walkthrough of the app as a brand-new user on a fresh iPhone 16 Pro install (`-fresh-start`), followed by a second pass with `-sample-data` to approximate an established user. Items are grouped **🚧 Blocker** (first-run user can't complete the intended task or is actively misled) vs **🔸 Friction** (they can, but it's annoying or compounds over time). Every item cites the exact file:line so the fix is unambiguous.

### 🚧 Blockers

- [ ] **Onboarding ends at step 4 of 13 — steps 5–13 never shown.** `MortalLoom/Views/OnboardingView.swift:840-842` — `firstReflectionStep`'s primary button calls `saveAndDismiss()` instead of `advanceStep()`, so Longevity Escape Velocity, Apple Health, Birth Date, Biological Sex, Smoking, Exercise, Sleep, Diet & Stress, and the Life Expectancy Results page are all skipped. Confirmed via screenshots during live walkthrough. The `// MARK: - Step N:` comments at lines 147, 183, 232, 304, 334, 396, 451, 500, 549, 627, 709, 792 still number against an earlier flow order — the TabView tags (lines 37-49) were reordered but `firstReflectionStep`'s action was never updated. Fix: change the reflection-step button to `advanceStep()`, and only call `saveAndDismiss()` from `resultsStep` (tag 12). Also re-number the stale MARK comments so the next refactor doesn't re-introduce this.
- [ ] **Every downstream calculation uses fake default lifestyle values.** Because of the bug above, `saveAndDismiss` at `OnboardingView.swift:940-995` persists `smokingStatus = .never`, `exerciseMinutes = 150`, `sleepHours = 7.5`, `dietQuality = .good`, `stressLevel = .moderate`, `birthDate = 30 years ago`, `biologicalSex = nil` — the @State defaults at lines 6-12, not user answers. Death clock, longevity chart, LEV math, age-remaining countdowns, Calendar grid, Reports alignment — everything — runs against these fake defaults for users who never saw the form. Verification: fix the blocker above and this resolves automatically.
- [ ] **13 progress dots promise a length the flow never delivers.** `OnboardingView.swift:29` (`totalSteps = 13`) + `OnboardingView.swift:68-79` (dot row). After Bug #1 is fixed this becomes accurate, but until then the user sees "4 of 13" and gets dumped on Overview. Make the dot count reflect `advanceStep()`-reachable steps.
- [ ] **Reflections & Reports are buried behind the "More" drawer.** `MortalLoom/Views/SideMenuView.swift:58` — `tabBarPages = [.overview, .goals, .calendar, .habits]`. Reflections (the journal) and Reports (Attention Needed, Alignment Trend) are the payoff of the goal-alignment loop, yet a new user has to discover the "More" tab to find them. Recommend: swap `Calendar` and `Habits` into More, promote `Reflections` and `Reports` into the tab bar — the calendar/timeline is gorgeous but not a daily destination; reflections are.
- [ ] **Stagnation rows in Reports are dead ends.** `MortalLoom/Views/ReportsView.swift:185-207` — `stagnationRow(_ signal)` renders a plain `HStack` with no `Button`. A user sees "'Run a marathon' hasn't been checked in for 14 days" and "What changed?" prompt — and literally cannot tap it. Wrap the row in a Button that jumps to the goal and opens the CheckInSheet, passing the suggested prompt as the seed answer.
- [ ] **"Configure your birth date and lifestyle in Settings" is wrong — the editor lives in Lifestyle, not Settings.** `MortalLoom/Views/OverviewView.swift:737` and `MortalLoom/Views/LifeCalendarView.swift:215`. Settings has Pro/Appearance/Countdown/Notifications/iCloud/Data/About/Setup Guide — none of which let you edit your birth date. The real editor is `MortalLoom/Views/LifestyleView.swift` (birthDate state at line 5, form at ~99). Either rewrite the empty-state copy to point at the Lifestyle tab, or add a "Health Profile" section to Settings that deep-links there.
- [ ] **Weekly Review CTA is gated on having an apex goal, which users aren't required to set.** `MortalLoom/Views/OverviewView.swift:124` and `:162` — `if WeeklyReview.isDue && apexGoal != nil { weeklyReviewCTA }`. Onboarding's apex step (tag 2) has a "Skip for now" button (`OnboardingView.swift:786`), so users who skip the apex never see the weekly-review card, which is the entire alignment loop. Either require an apex before finishing onboarding, or show a weekly-review CTA that walks the user through setting an apex when it fires.
- [ ] **Weekly review silently drops user input when no apex exists.** `MortalLoom/Views/WeeklyReviewSheet.swift:291-299` — `finish()` returns early when `apex == nil`, discarding the user's answer, alignment rating, commitments AND still stamping `lastWeeklyReviewDate`. If somehow the sheet opens without an apex (e.g. apex deleted between CTA tap and Finish), the user gets told nothing and their data is gone. Either gate the sheet open on apex-present, or fall back to a general "Reflections" bucket.
- [ ] **Sample data is stale — no apex, no pillars, no habits, no reflection-shaped check-ins.** `MortalLoom/Engine/SampleData.swift:357-451` has 4 standard goals (book/marathon/piano/garden) with zero `goalType: .apex` or `.subApex`, no `parentId` linkage, no `alignmentRating`/`blockers`/`commitments` on check-ins. `fullAppData` at `:483-495` never passes `habits:`. The Goal Alignment Reframing (see section above, dated 2026-04-11 COMPLETE) is invisible in `-sample-data`. Blocker for accurate App Store screenshots AND for QA — sample-data runs look like the pre-reframe app. Add: one apex, 2-3 pillars parented to it, habit list with mixed streaks, reflection-shaped check-ins across the last 12 weeks so Reports actually populates.

### 🔸 Friction — Onboarding

- [ ] **First reflection question is truncated on iPhone 16 Pro: "Right now, how aligned does your life feel wit..."** `OnboardingView.swift:820-822`. The `Text` uses `.font(.subheadline).fontWeight(.semibold)` without `.fixedSize(horizontal: false, vertical: true)` or an explicit `.lineLimit(nil)`, so the SwiftUI layout truncates rather than wrapping. Add the fixedSize modifier; already used correctly on the `rateStep` text at `WeeklyReviewSheet.swift:210`.
- [ ] **Presumptuous default alignment rating = 7/10 "Mostly aligned".** Two places: `OnboardingView.swift:27` `firstReflectionRating: Double = 7` and `WeeklyReviewSheet.swift:28` `alignmentRating: Double = 7`. Slider lands on a strong positive before the user has engaged — the app is telling them how they feel. Default to 5 (neutral "Mixed") or require an explicit tap before the rating counts. Related: `saveAndDismiss` at `OnboardingView.swift:974` uses `firstReflectionRating != 7` as the "user touched it" signal, which means users who actually feel 7/10 get no check-in recorded.
- [ ] **Apex category silently pre-selects Legacy.** `OnboardingView.swift:21` `apexGoalCategory: GoalCategory = .legacy` — the chip is highlighted before the user picks anything, confirmed in screenshot `/tmp/mortalloom-ux-audit/03-onboarding-apex.png`. Meanwhile `GoalEditSheet.init` at `MortalLoom/Views/GoalsView.swift:865` defaults `_category = State(initialValue: g?.category)` which is `nil` → "None". Pick one behaviour; inconsistency confuses users who try to match onboarding and edit-form defaults.
- [ ] **"Skip for now" button label is ambiguous.** `OnboardingView.swift:786` — `primaryButton(apexGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip for now" : "Next")`. Same button, two meanings depending on text-field state. A user tapping "Skip for now" to "save and move on" may or may not realise their partial input is being discarded. Split into a always-visible primary "Next" + a secondary "Skip this" text link when title is empty.
- [ ] **No back button anywhere in the onboarding TabView.** `OnboardingView.swift:33-54` uses `.page(indexDisplayMode: .never)` and only `advanceStep()` is wired. Users who fat-finger the birth-date wheel or pick the wrong sex can't correct without quitting and running "Show Setup Guide" (which is itself buried — see Settings blockers). Add a header back chevron on steps >0.
- [ ] **Longevity Escape Velocity step is the only place the term is defined — and users never reach it.** `OnboardingView.swift:186-230` (escapeVelocityStep, tag 4, currently unreachable per blocker #1). But the Calendar's "Standard / LEV" toggle (`LifeCalendarView.swift:240-251`) and Settings' "DEFAULT COUNTDOWN" toggle use the LEV acronym with no in-context explainer. Once the onboarding bug is fixed this resolves, but still: add an info-popover on the LEV chips so users who didn't do full onboarding aren't locked out.
- [ ] **Keyboard-return key doesn't advance the primary button on single-field steps.** Minor SwiftUI nit: none of the onboarding text fields set `.onSubmit { advanceStep() }`. Users who finish typing their North Star expect Return to move on.

### 🔸 Friction — First-session landing (Overview)

- [ ] **"YOUR RUNWAY" and "HEALTH SUMMARY" sections default expanded with empty data.** `OverviewView.swift:31-32` — both `@AppStorage` flags default to `true`. On first launch with no profile, both sections render "—" placeholders (screenshot `/tmp/mortalloom-ux-audit/11-overview-sample.png`). Collapse them by default when `profile.birthDate == nil`, and surface a single "Set up your health profile →" card in their place.
- [ ] **"HEALTH SUMMARY" label appears twice in close vertical proximity.** The collapsible `collapsibleHeader(title: "HEALTH SUMMARY", …)` at `OverviewView.swift:144-147` and a card labelled "Health Summary" rendered inside it. Confirmed visually in the sample-data Overview. De-dupe.
- [ ] **Set-Goal CTA doesn't explain what an apex is until you tap in.** `OverviewView.swift:567-613` — the `setGoalCard` has a one-liner ("What's the one big thing…") + examples, then the button opens `GoalEditSheet` which has the "(i)" popover with the full explanation. Pull that explainer up onto the set-goal card itself (or add it as a 2nd line below the examples).
- [ ] **"Set My North Star Goal" CTA and the onboarding's apex form produce goals with different defaults.** Overview CTA at `OverviewView.swift:61-81` passes `defaultGoalType: .apex, defaultHorizon: .lifetime, defaultPriority: .high` but no `defaultCategory`, so category shows "None". Onboarding's apex step at `OnboardingView.swift:21` defaults to `.legacy`. A user who skipped apex in onboarding and creates it from Overview gets a subtly different starting state. Align both.

### 🔸 Friction — Goal creation & hierarchy

- [ ] **Type picker includes a "None" option that produces broken goals.** `GoalsView.swift:935-944` — Picker includes `Text("None").tag(GoalType?.none)`. A user who picks None creates a goal with no type, which can't participate in the hierarchy or alignment scoring. Remove the None option; require a type on save.
- [ ] **Default Parent Goal is "None (top-level)" even when an apex exists.** `GoalsView.swift:968-969` — `Picker("Parent Goal", selection: $parentId)` with `Text("None (top-level)").tag(UUID?.none)` as the first row. A new standard goal created from Goals page has no parent and therefore contributes zero to any alignment score. Default `parentId` to the user's apex (or the most recently-edited pillar) if one exists.
- [ ] **Save button silent-disables when title is empty.** No explanatory subtext under the title field. A user who hasn't filled it in can't tell whether the form is broken, waiting, or expects them to scroll. Add a one-line hint: "Name your goal to save."
- [ ] **No inline one-tap check-in on the Goals list.** `GoalsView.swift` goal rows — tapping opens the full edit sheet; to check in you need to open Check-In sheet separately. A user who just wants to bump progress % on a marathon goal has to tap goal → pencil → CheckInSheet → slider → Save. Add a swipe-action or compact inline "Check in" button on goal rows.
- [ ] **Cancel/Save sheet header has no progress feedback.** New users spend a long time on the first goal form — add the section label ("Classification", "Priority") as a scroll anchor or a "3 of 7" progress strip like the weekly review.

### 🔸 Friction — Daily loop (habits, check-ins, reflections)

- [ ] **Habits tab mixes daily habits with Alcohol/Nicotine/Sauna substance trackers.** `MortalLoom/Views/SubstancesView.swift` sub-tab bar at the top is `My Habits / Alcohol / Nicotine / Sauna`. Substances belong in the Health surface, not the Habits daily loop. Screenshot `/tmp/mortalloom-ux-audit/14-habits-sample.png`. Move substance tracking into a separate page under Health (or merge substances as typed habits in the unified list).
- [ ] **"No habits yet" empty state doesn't mention the parent-goal link.** `HabitsSection.swift` empty-state copy says "daily actions that move you toward your goals" but doesn't tell users that tying a habit to a parent goal is what makes it contribute to alignment. Add one line: "Link each habit to a goal so it shows up on your alignment score."
- [ ] **Reflections journal is reverse-chronological with no "streak" or "weeks reflected" stat.** `MortalLoom/Views/ReflectionsView.swift` — a user who opens this after 6 months of weekly reviews sees a flat list. Add a header card: "You've reflected 23 times across 21 weeks. 🪴 Keep going."

### 🔸 Friction — Weekly review

- [ ] **Review step shows aggregate counts, not the actual items.** `WeeklyReviewSheet.swift:116-151` — "3 check-ins, 1 goal completed, 8 habit completions" as three `statRow`s. A user wants to feel the week, not read a tally. Show the titles: "✓ Marathon: ran half marathon", "✓ Garden bed built", "🔁 Writing practice ×4". Use the same data that `weekActivity()` at `:324-347` already iterates.
- [ ] **No comparison to last week's commitments during the Commit step.** `WeeklyReviewSheet.swift:229-247` — users commit to "Two 45-minute writing sessions", next week there's no echo of that commitment or a "did you do it?" checkbox. Pull the previous week's commitments from the apex's prior `GoalCheckIn.commitments` and render them above the new commit field with checkboxes.
- [ ] **"Next" button only gated on Reflect step.** `WeeklyReviewSheet.swift:284` — `.disabled(step == .reflect && answer.trimmingCharacters(in: .whitespaces).isEmpty)`. Rate can be left at the default 7 and Commit can be empty, both producing valid-but-meaningless saves. Gate Commit on at least one non-empty line too.
- [ ] **Review step opening stat is raw `Int(score)` with no sparkline.** `WeeklyReviewSheet.swift:130-144` shows current alignment as a single large number. A week-over-week delta arrow or 4-week sparkline would turn the review step from a look-back into a narrative.

### 🔸 Friction — Goal Timeline (Calendar)

- [ ] **LEV toggle has no in-context explainer.** `LifeCalendarView.swift:240-251` — segmented picker labelled `Standard / LEV`. Add an info-icon `.popover` next to the picker with the 2-line LEV definition, same copy as `OnboardingView.swift:197-220`. Unblocks users who skipped the onboarding LEV step.
- [ ] **Default view is 80-year Weeks grid, which is nearly-empty at first launch.** `LifeCalendarView.swift:253-264` — the grid renders 4,000+ cells but first-run users have no scheduled goals and the "Show lived time" toggle is off by default. They see a wall of grey boxes. Default to `years` mode on first open or scale the grid to zoom into the next-5-years range.
- [ ] **"Awake Days" stat (8,747) conflates with "Days" (13,121) with no explanation of the 33% sleep assumption.** `LifeCalendarView.swift:263`. Add a `?` tooltip: "Awake Days = Days × 2/3, assuming 8 hours of sleep".

### 🔸 Friction — Reports & stagnation

- [ ] **Empty states have no CTA buttons, only descriptive text.** `ReportsView.swift:145-150` (alignment trend), `:231-235` (pillar breakdown), and the habit card empty state. A user sees "Add supporting goals and reflect on your North Star to start building an alignment history" and nothing to tap. Add primary buttons under each: "+ Add a supporting goal", "+ Add a life pillar", "+ Add a habit". Wire each to the appropriate pre-filled `GoalEditSheet` or `HabitEditSheet`.
- [ ] **Piano goal in sample data flags as "759 days past its target".** `Engine/SampleData.swift:407-425` — `createdDate: dateStr(daysAgo: 200)` with `targetDate: dateStr(daysAgo: -180)` (i.e. 180 days in the future). StagnationEngine is computing 759 days past deadline, which means either the sample data's target math is off or the engine has a sign/offset bug. Investigate via `MortalLoom/Engine/StagnationEngine.swift` against the piano sample.
- [ ] **Stagnation severity doesn't escalate over time.** Piano is 90 days behind check-in and still rendering at the same visual weight as marathon at 14 days (screenshot `/tmp/mortalloom-ux-audit/16-reflections-empty.png`). Promote 30+ days to `.alert` severity and surface an "Archive?" quick action.
- [ ] **"ATTENTION NEEDED" count pill (`ReportsView.swift:164-167`) is `.textMuted` — visually indistinguishable from a disabled badge.** On a 3-item alert list the number "3" should be `.danger` or `.accentColor`.

### 🔸 Friction — Settings & recovery

- [ ] **"Show Setup Guide" is 5 taps deep and below "About".** `SettingsView.swift:128` — lives in the Settings sub-tab "More", which is itself inside the bottom-nav "More" drawer. For users who ended up on Overview without a health profile (common due to the step-4 blocker), this should be the most prominent action in Settings. Move to the top of the General sub-tab under a new `SETUP` section, with copy like "Finish your health profile to unlock the longevity clock."
- [ ] **Notifications default to off.** `SettingsView.swift:notificationsSection` starts with `Weekly review reminder` and `Stagnation alerts` as unchecked toggles (screenshot `/tmp/mortalloom-ux-audit/17-settings.png`). The entire alignment loop depends on weekly reminders; turning them off by default guarantees users forget. Turn Weekly Review on during `saveAndDismiss()`; leave Stagnation opt-in.
- [ ] **"More" label appears twice in the same screen (bottom nav + Settings sub-tab).** `SettingsView.swift:132` — the Settings TabView's third tab is labelled `"More"`, directly above the already-`More` bottom nav tab. Rename Settings sub-tab to `"About"` and move Setup Guide into General.
- [ ] **DEFAULT COUNTDOWN LEV footnote is awkwardly worded.** Screenshot `/tmp/mortalloom-ux-audit/17-settings.png` shows `"(defaults to (past 2045))"` — nested parentheticals. Rewrite as "(defaults to 2045)" in `SettingsView.swift` countdownSection.
- [ ] **No dedicated health-profile section in Settings.** Mirrors the blocker about wrong empty-state copy — Settings should at minimum have a one-tap "Edit Health Profile →" link that deep-jumps to `LifestyleView`.

### 🔸 Friction — Cross-cutting

- [ ] **No deep-linkable URLs for reflection or weekly-review entry.** CLAUDE.md says "All UI views must be deep-linkable routes (/page/sub-tab/edit), not modals without URLs" but the bottom tab bar only mutates state (`CustomTabBar` at `SideMenuView.swift:204`). A user who gets a "time to reflect" notification can't deep-link into the reflection sheet. Add a URL scheme for `mortalloom://weekly-review`, `mortalloom://goal/new?type=apex`, `mortalloom://reflections`.
- [ ] **No "you've skipped onboarding — finish it" recovery banner.** For users currently stuck in the step-4 half-onboarded state, a one-time banner at the top of Overview ("Your longevity clock needs a few more answers to start ticking. Finish setup →") would recover them without forcing a full onboarding re-run. Once the step-4 blocker is fixed this becomes unnecessary, but it's cheap insurance.

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
