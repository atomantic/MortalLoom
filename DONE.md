# Done Log

Completed items archived from PLAN.md. For release notes, see `.changelogs/`.

## 2026-08-12

- Blood donation tracking — Blood page is now tabbed (Tests / Donations) with a `BloodDonation` record (product, volume in mL, date, optional location) and `DonationEngine` for same-product eligibility countdowns, rolling-365-day counts against annual caps, and lifetime/year volume totals. Syncs by UUID like every other collection.

## 2026-08-11

- Reports Time Allocation card — cross-pillar breakdown of MortalLoom-tagged calendar work-block minutes over the last 30 days (`TimeAllocationEngine.pillarBreakdown` + share bars, "Other goals" remainder slice, zero-state hint; hidden when Calendar access is unavailable). Ships the time-allocation half of #65.

## 2026-04-28

- Weekly Review 7-day alignment-rating sparkline (Charts inline, Y 1–10, weekday X-axis)
- Substances migration — Alcohol/Nicotine/Sauna split out of Habits tab into dedicated Substances page (`AppPage.substances`, drawer Health section, deep-link routing updated)
- 159 new unit tests across 5 engines (CardioFitness, Gait, GenomeAction, GenomePriority, etc.)

## 2026-04-26

- Genome action goal-template bridge + Overview integration (Phase 5) — `.goalTemplate` opens prefilled goal sheet, 🧬 evidence banners, `.openGenomeFinding` notification, Overview recs include DNA-derived priorities
- Habits credit goal alignment and freshness everywhere
- Hide spent time in Life Calendar + disambiguate same-titled goals
- Restore macOS entitlements stripped by Xcode 'Apply Recommended Settings'

## 2026-04-23

- Defer/snooze goals to a future date + Check-In parent breadcrumb
- Overview Attention Needed card tappable to open Reports
- Replace two 404 citation URLs with working canonical links

## 2026-04-22

- Actionable Genome Findings Phases 1–4 — `GenomeAction`/`GeneticEvidence`/`VisitNote` data model with merge support, `GenomePriorityEngine` (severity × confidence × actionability × lifestyle × freshness), `GenomeActionLibrary` (~25 curated APOE/MTHFR/Factor V/HFE/9p21/TP53/COMT/etc. actions), `GenomeDetailSheet` no-truncation single-surface view with action plan + doctor talking points + visit-note history, `GenomePrioritiesCard` pinned to Genome tab. Spec at `docs/superpowers/specs/2026-04-22-genome-actionable-design.md`.
- Polarity-aware concern counts + beneficial counter on category cards
- macOS detail surface + visit-note presentation + sex filter on priorities
- Unify genome finding types and fix bridge bugs (`/simplify` pass)

## 2026-04-21

- Universalize `deploy.sh` to match PortOS canonical template
- Polarity-aware genome marker display

## 2026-04-11

### Goal Alignment Reframing
- Apex/North Star edit form slimmed (deadline hidden, milestones replaced with Supporting Goals, lifetime horizon)
- Overview Alignment Score replaces apex Progress bar (avg `progressPercent` across active standard descendants)
- Apex card CTA "Add a supporting goal" / "Review supporting goals" (calendar gated to standard goals)
- Nav reorganization: Goals section leads (Overview/Goals/Calendar/Habits), Health section follows (Body/Sleep/Blood/Lifestyle/Genome)

### Habits as daily engagement loop
- `Habit`/`HabitCompletion`/`HabitCategory`/`HabitKind`/`HabitCadence` models with read-time streak derivation
- DataStore CRUD + iCloud merge-by-ID
- `HabitEngine` pure functions (completionsInPeriod, currentStreak, targetHitRate, alignmentContribution, isStagnant)
- "My Habits" tab with Habitica-style cards + `HabitEditSheet` (icon/color/category/cadence/parent goal)

### Unified check-in model
- `GoalCheckIn` extended with alignmentRating/blockers/commitments/promptAnswered (back-compat decoder)
- `ReflectionPrompts` library (general/monthly/stagnation buckets)
- `CheckInSheet` branches by goal type (standard: progress; apex: alignment + prompt + blockers + commitments)
- Apex/sub-apex Reflect button + recent reflections list

### Reflections page
- Chronological journal with filter pills (All/North Star/Pillars/Goals); cards show rating, prompt, blockers, commitments

### Reports page MVP
- Alignment trend chart (12-week 70/30 weighted), Attention Needed (StagnationEngine), Pillar alignment breakdown, Habit streaks
- Compact "Attention Needed" mirror on Overview

### Pillar Dashboards
- Per-pillar sub-alignment score, supporting goals, linked habits, scoped reflections — sheet from sub-apex tap

### Stagnation engine
- `StagnationEngine` pure function with 5 signals (apex no goals, pillar no descendants, missed cadence, projection slip, habit cadence miss) + suggestedPrompt per signal

### Reflection flow + cadence + Calendar integration
- Weekly Review 4-step guided modal with last-week comparison and per-step `nextDisabled`
- `CalendarService` tags events with `mortalloom://goal/<uuid>`; `TimeAllocationEngine` rolls up minutes per pillar; Pillar Dashboards 30-day allocation card
- Overview restructure — collapsible Runway/Health Summary, goal-first hero (apex + alignment + attention)
- Widget alignment view — North Star + alignment + today's prompt
- `NotificationService` — repeating weekly review + reconciled stagnation alerts (opt-in)
- Onboarding reordered — North Star + first reflection step before LEV/health questionnaire; chip-grid category picker
- Per-goal `mutedSignals` + smart-default cadence override UI
- `-fresh-start` launch flag for DEBUG (in-memory empty state, forced onboarding, no disk writes)

### New-User UX Audit (blockers + friction)
- Onboarding flow now reaches step 4 → results (`firstReflectionStep` advances; only `resultsStep` saves)
- Overview "Configure your birth date and lifestyle in Settings" copy fixed → "Open Lifestyle" deep-link + setup wizard fallback
- Sample data rewritten — 1 apex + 7 reflections, 3 pillars, 4 standard goals, 4 habits with backdated completions; piano `-180d` overdue bug fixed
- Reflections & Reports promoted to bottom tab bar (Overview/Goals/Reflections/Reports)
- Stagnation rows in Reports tap-through to CheckInSheet; severity-coloured count pill
- "Finish your setup" recovery banner on Overview when birthDate is nil
- Onboarding back chevron, `.submitLabel(.next)`, default alignment rating 5, apex category nil-default + tap-to-toggle
- Goals: Type picker "None" removed; new standard goals auto-parent to active apex
- Empty Runway/Health Summary collapsed first-load; healthGrid duplicate label fixed; Set-Goal CTA expanded with examples
- LifeCalendarView: LEV explainer popover, view mode `@AppStorage` defaulting to Years
- Reports empty states have CTA buttons (Set North Star / Add supporting goal / Add habit)
- Settings: Setup Guide promoted to first General card; weeklyReviewEnabled defaults true; About sub-tab renamed; LEV footnote rewrite
- Sample-data race fix (showOnboarding); `setInMemory` posts dataDidSync; `testSampleGoalsProduceValidProjections` filter

### Daily Engagement Loop first pass
- `mortalloom://` URL scheme registered; `DeepLinkRouter.parse` + `.onOpenURL` on iOS/macOS roots; supports page/goal-edit/goal-reflect/weekly-review URLs (`DeepLinkRouterTests`)
- One-tap post-habit nudge with Yes/Partially/No → `alignmentRating` 8/5/2; rate-limited via `dailyNudgeDismissedOn`
- Widget tap-through to apex reflect via `mortalloom://goal/<apex>/reflect`
- Overview daily-streak chip (orange flame on apex card)
- `StagnationEngine` severity scaling (info/warn/alert by ratio) + `daysOverdue` field; in-context stagnation prompts in `CheckInSheet` (`StagnationEngineTests`)
- Inline one-tap check-in on Goals list; save hint on `GoalEditSheet`; Awake Days tooltip
- Settings: Edit Health Profile deep-link to Lifestyle page

## 2026-04-06

### Better Swift Audit (5 PRs merged: #3–#7)
- Security — file protection class corrected from `.completeFileProtectionUnlessOpen` → `.untilFirstUserAuthentication` (widget background reads while locked)
- Bugs & Perf — reverted bad Task.detached → Task; file protection in `reloadIfNeeded()`; silent-write-failure logging
- Code Quality — HealthKit `authorized` → `authorizationRequestCompleted` rename (read auth never reports user denial)
- DRY — `SubstanceEngine.allTimeAverage<T>` generic helper replaces 3 copies; sauna test added
- Tests — entitlements split into iOS/macOS files; clamp tests renamed
- Foundation — `View.inlineNavigationTitle()` helper in `Theme/Theme.swift` (6 of 12 call sites migrated)

## 2026-03-31

- macOS fix — WidgetBridge.update() guarded with #if os(iOS) to prevent cross-app-data sandbox alert
- macOS fix — BodyView falls back to DataStore.bodyEntries when HealthKit unavailable; subscribes to dataDidSync for live iCloud updates
- LEV mode — configurable target lifespan (default 120yr, user-adjustable via stepper in Settings, persisted to iCloud)
- MortalLoom Pro — one-time IAP + secret code unlock (SHA-256/Keychain), Pro section in Settings
- Feature gates — Blood, Genome, Substances, Body views fully gated; epigenetic tile and data export section gated via .proGated() overlay

## 2026-03-25

- Core infrastructure — all models, actor-based storage with iCloud + local fallback, native HealthKit service
- Longevity clock engine — SSA baseline life expectancy, lifestyle/genome adjustments, live countdown, LEV tracker
- Lifestyle questionnaire — profile, smoking, exercise, sleep, diet, stress, BMI with impact preview
- Substance tracking — alcohol/nicotine logging with presets, NIAAA risk levels, rolling averages, Swift Charts
- Blood tests — manual entry for 50+ markers with reference ranges and status colors
- Body composition — weight/body fat tracking with chart
- Eye prescriptions — CRUD with SPH/CYL/AXIS per eye
- Genome analysis — raw file import (23andMe, AncestryDNA), on-device variant parsing, category classification
- Epigenetic age tracking — biological vs chronological age, pace of aging, organ scores
- Data export/import — full JSON export and restore
- Correlation charts — alcohol+HRV, nicotine+HR, activity+blood markers
- HealthMetricEntry model with iCloud sync
- Sample data factory for screenshots (-sample-data launch arg)
- Goal tracking — model with check-ins/milestones/priority/status, GoalEngine projections, GoalsView CRUD
- Life Calendar integration — goal target/projected dates as teal markers
- Test suite — 252 unit tests across 23 classes with comprehensive engine/model coverage
- Engine extractions — SubstanceEngine, GenomeParser, CorrelationEngine, GoalEngine refactored for testability
- Onboarding wizard — first-launch setup flow with HealthKit step
- Health trajectory chart and calendar view modes
- iCloud sync monitor
