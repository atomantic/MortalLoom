# Genome Findings: From Deep Well to Actionable

**Status:** Design approved, awaiting implementation plan
**Date:** 2026-04-22
**Scope:** GenomeView and supporting engines/models — make findings actionable, tied into Goals/Habits, and useful at the doctor's office.

## Problem

The current Genome section (`Views/GenomeView.swift`, three tabs: Bio Age / Genome / ClinVar) presents 116 curated markers plus a ClinVar cross-reference. Each finding shows a status pill, a description of what the gene does, and an "implication" sentence. Information density is high, actionability is low. Specifically:

1. **No cross-cutting synthesis.** A user with 30 concerns across 10 categories has no way to know which 3 matter most.
2. **Actions buried in prose.** Many implication strings contain action verbs ("monitor ferritin", "consider methylfolate"), but they're not tappable. The user reads them and forgets them.
3. **Zero integration with Goals/Habits.** `Engine/RecommendationEngine.swift` produces actionable recommendations but only factors in lifestyle data (smoking, exercise, sleep, diet, BMI, alcohol). No genome path exists.
4. **Dead-end navigation.** Findings have no "next step" — a MTHFR T/T result that says "Consider methylfolate" doesn't link to a habit, blood test, goal, or doctor talking point.
5. **ClinVar text truncated to ellipsis.** Critical pathogenic conditions (e.g. CFTR variants) are cut off mid-sentence with no way to expand.
6. **Drug-response variants** sit in a list with no way to package them for a pharmacist.

## Goals

- Every genome finding has at least one tappable action — habit, goal, blood test, lifestyle change, or doctor consult.
- A "Top Priorities" synthesis ranks findings across all 116 markers + all ClinVar hits and surfaces the 7 that matter most for *this* user.
- Genome findings feed `RecommendationEngine` so DNA-driven recs appear on the Overview alongside lifestyle ones.
- Habits and goals created from a genome finding carry their genetic provenance ("🧬 Suggested by your DNA: APOE ε3/ε4").
- A doctor-ready PDF can be generated and printed (AirPrint) for in-office use.
- An iPad "Visit Mode" supports live note-taking against each finding during a doctor visit; notes get appended to the post-visit summary PDF.
- Truncated text is eliminated everywhere; tap on any row opens a full detail sheet (iPhone) or detail pane (iPad).

## Non-Goals

- Real-time AI/LLM-generated advice. Action library is curated and static.
- Re-classification of variant pathogenicity. We surface ClinVar's classifications as-is.
- Integration with electronic health records or any external service. No data leaves the device.
- Server-side anything. Brand promise (`no servers, no telemetry`) is preserved.
- Coverage of all 116 markers in the curated action library on day one. Initial pass covers ~30 high-impact markers + drug responses + top ClinVar pathogenic genes; remaining markers still get the new detail card with description, citations, and ClinVar links.
- Charts in the PDF. Plain text + dots/checkboxes only.

## Architecture

```
MortalLoom/
├── Engine/
│   ├── GenomeActionLibrary.swift    # NEW: per-marker + per-condition action templates (data only)
│   ├── GenomePriorityEngine.swift   # NEW: pure ranking (severity × confidence × actionability × lifestyle × freshness)
│   └── GenomeReportPDF.swift        # NEW: pre-visit + post-visit PDF generator (PDFKit)
├── Models/
│   ├── GenomeAction.swift           # NEW: GenomeAction + state types + GeneticEvidence
│   └── GenomeVisit.swift            # NEW: VisitNote (per-finding doctor notes)
├── Views/
│   ├── GenomeDetailSheet.swift      # NEW: full-height detail card; reused on iPhone (sheet) + iPad (pane)
│   ├── GenomePrioritiesCard.swift   # NEW: pinned-top priorities widget (top 7 of N)
│   ├── GenomeSplitView.swift        # NEW: iPad NavigationSplitView wrapper (sidebar/list/detail)
│   ├── GenomeVisitModeView.swift    # NEW: focused doctor-visit layout with live notes
│   └── GenomeVisitNotesPane.swift   # NEW: per-finding notes capture component
```

**Modified:**
- `Views/GenomeView.swift` — adds priorities card; replaces inline truncated text with "tap for details"; routes to `GenomeSplitView` on regular size class.
- `Engine/RecommendationEngine.swift` — accepts `genomePriorities: [PriorityFinding] = []`; adds DNA-derived recs (capped at 3, attenuated 0.7×).
- `Models/Habit.swift` and `Models/Goal.swift` — add `var geneticEvidence: GeneticEvidence?` (Codable, `decodeIfPresent` for back-compat).
- `Models/AppData.swift` — add `genomeActionStates: [String: GenomeActionState]` and `genomeVisitNotes: [VisitNote]`, both back-compat decoded.

**Why this shape:**
- `GenomeActionLibrary` is data-only, parallel in spirit to `Engine/CuratedMarkers.swift`. Easily testable, easy to extend without touching UI.
- `GenomePriorityEngine` is a pure function (inputs → ranked list). Independently testable.
- `GenomeDetailSheet` is one component reused on both iPhone (presented as a sheet) and iPad (embedded as a pane). Single source of truth for marker presentation kills the truncation problem everywhere.
- Goals/Habits get `geneticEvidence`, so the bridge is bidirectional — the genome detail can show "linked to 2 active habits", and the habit detail can show "🧬 Suggested by your DNA."

## Data Model

```swift
// MARK: - Action Library

/// A specific actionable suggestion for a marker or ClinVar condition.
/// Stored declaratively in GenomeActionLibrary.swift.
struct GenomeAction: Sendable, Identifiable {
    let id: String                    // stable: "mthfr-c677t-methylfolate"
    let kind: GenomeActionKind
    let title: String                 // "Supplement methylfolate (400-800 mcg/day)"
    let detail: String                // 1-3 sentences with thresholds & framing
    let urgency: GenomeActionUrgency  // routine, soon, prompt
    let conditions: [GenomeActionCondition]  // when to surface (genotype/severity gates)
    let bridge: GenomeActionBridge?   // optional link into Goals/Habits/Blood/Lifestyle
    let citationIds: [String]
    let doctorTalkingPoint: String?   // single sentence framed for clinician conversation
}

enum GenomeActionKind: Sendable, Codable {
    case bloodTest      // "Order homocysteine + B12 panel" → bridges to BloodMarkers.key
    case screening      // "Annual carotid ultrasound after 50"
    case habit          // "Cardio 150+ min/wk" → bridges to Habit template
    case lifestyle      // "Limit caffeine after 2pm" → bridges to LifestyleData
    case supplement     // "Methylfolate 400mcg" → general "discuss with doctor"
    case doctorConsult  // "Discuss with primary care / genetic counselor"
    case partnerScreen  // "Carrier screening for partner before conception"
    case research       // pure educational link-out
}

enum GenomeActionUrgency: String, Sendable, Codable {
    case routine    // grey
    case soon       // amber
    case prompt     // red — pathogenic / majorConcern
}

struct GenomeActionCondition: Sendable {
    let rsid: String                  // "rs1801133"
    let genotypes: [String]?          // nil = any matching genotype with non-typical status
    let minStatus: GenomeMarkerStatus?  // e.g. .concern (surface for concern + majorConcern)
}

enum GenomeActionBridge: Sendable {
    case habitTemplate(HabitTemplate)
    case goalTemplate(GoalTemplate)
    case bloodMarkerKey(String)       // jumps to Blood section, pre-filtered to that marker
    case lifestyleField(LifestyleField)  // jumps to Lifestyle section, scrolled to field
    case external(URL)                // ClinVar, OMIM, study DOI
}

struct HabitTemplate: Sendable {
    let title: String
    let detail: String
    let icon: String
    let category: HabitCategory
    let kind: HabitKind
    let cadence: HabitCadence
}

struct GoalTemplate: Sendable {
    let title: String
    let notes: String
    let category: GoalCategory
    let horizon: GoalHorizon
}

enum LifestyleField: String, Sendable {
    case smokingStatus, exerciseMinutesPerWeek, sleepHoursPerNight,
         dietQuality, stressLevel, alcoholDrinksPerWeek
}

// MARK: - Action State (per user, per action)

struct GenomeActionState: Sendable, Codable {
    let key: String                   // "<rsid>:<actionId>"
    var status: GenomeActionStatus
    var updatedAt: String             // ISO date
    var note: String?                 // freeform user note
    var linkedGoalId: UUID?           // if user accepted -> goal/habit
    var linkedHabitId: UUID?
    var linkedVisitNoteId: UUID?      // set when status flipped via "Discussed with doctor"
}

enum GenomeActionStatus: String, Sendable, Codable {
    case pending      // shown in priorities
    case inProgress   // user accepted (linked to habit/goal/blood test)
    case discussed    // talked about with doctor (visit note attached)
    case done         // completed (e.g. blood test ordered, supplement started)
    case snoozed      // hidden for 6 months
    case dismissed    // hidden permanently ("not relevant to me")
}

// MARK: - Genetic Provenance on Habits/Goals

struct GeneticEvidence: Sendable, Codable {
    let rsid: String
    let gene: String
    let reason: String                // "Suggested for your APOE ε3/ε4 — neuroprotective"
    let actionId: String
}

// Habit and Goal each get: var geneticEvidence: GeneticEvidence?
// All decoders use decodeIfPresent so existing user data keeps loading.

// MARK: - Visit Notes

struct VisitNote: Sendable, Codable, Identifiable {
    let id: UUID
    let date: String                  // ISO date
    let providerLabel: String?        // "Dr. Smith, PCP"
    let findingKey: String            // rsid for marker, "<rsid>:<condition>" for ClinVar
    var body: String                  // doctor's response
    var followUp: String?             // "Recheck in 6 months", "Order panel"
}

// AppData additions:
// var genomeActionStates: [String: GenomeActionState]
// var genomeVisitNotes: [VisitNote]

// MARK: - Priority Engine output

struct PriorityFinding: Sendable, Identifiable {
    let id: String                    // rsid for marker, "<rsid>:<condition>" for ClinVar hit
    let source: PriorityFindingSource // .marker | .clinvar | .apoe
    let score: Double                 // 0.0 – 1.0
    let topAction: GenomeAction?      // single most-actionable next step
    let actionCount: Int              // total actions available
    let stateCounts: ActionStateCounts // pending / inProgress / discussed / done
}

enum PriorityFindingSource: Sendable {
    case marker(MarkerResult)
    case clinvar(ClinVarHit)
    case apoe(APOEResult)
}

struct ActionStateCounts: Sendable {
    let pending: Int
    let inProgress: Int
    let discussed: Int
    let done: Int
}
```

### Decoder back-compat

Every new field on existing models (`geneticEvidence` on `Habit`/`Goal`, the `AppData` additions) decodes with `decodeIfPresent`. Existing JSON files keep loading without migration.

### Action library coverage (initial scope)

The action library ships covering ~30 high-impact markers plus drug-response and top ClinVar pathogenic genes:

- **Longevity**: APOE haplotype (all 6 forms), FOXO3A, CETP, IGF1R
- **Cardiovascular**: Factor V Leiden, 9p21 CAD, LPA, MTHFR (cardiovascular angle)
- **Iron**: HFE C282Y, HFE H63D
- **Methylation**: MTHFR C677T, MTHFR A1298C, COMT
- **Detox & inflammation**: SOD2, IL-6, TNF-α
- **Caffeine**: ADA, CYP1A2 (if present in scan)
- **All `majorConcern`-capable risk markers** in the existing library
- **All ClinVar pathogenic hits** (≥3 stars) get a generic doctor-consult action plus a "carrier screening for partner" action where condition is recessive
- **All drug-response variants** get a generic pharmacist-handoff action

Other ~86 markers still get the new detail card (full description, citations, ClinVar links) but no curated actions — they show "No specific actions yet for this finding" and a research link.

Library grows by appending entries to `GenomeActionLibrary.swift` — no schema changes needed.

## Detail Sheet (`GenomeDetailSheet`)

Single component used everywhere a marker, ClinVar hit, or APOE result is tapped. Compact width: presented as `.sheet(.large)`. Regular width: lives in the right pane of `GenomeSplitView`.

Layout (top to bottom):

1. **Header** — gene + marker name, status pill (color-coded), your genotype, ClinVar review stars, rsid.
2. **What this means** — full description (no truncation) + the implication for the user's actual genotype.
3. **Action plan** — list of `GenomeAction` rows. Each row shows urgency dot + kind label + title, with primary CTA from the `bridge` (e.g. "Order in Blood ▸", "Add as habit ▸") and secondary "Mark discussed".
4. **Doctor talking point** — single copyable paragraph framed for clinician. Buttons: `[Copy]` `[Add to visit notes]`. Hidden if no curated talking point exists for this finding.
5. **Visit notes** — collapsible chronological list of past `VisitNote`s for this finding. Each row: date · provider · body excerpt.
6. **Linked items** — bidirectional bridge: any active habit/goal with `geneticEvidence.rsid` matching this finding, with current streak / progress.
7. **Evidence** — full ClinVar metadata (review stars, submissions, full untruncated condition list) + tappable `CitationBadge` for academic sources.
8. **Snooze / Dismiss** — low-emphasis bottom row: `[Snooze 6 months]` `[Not relevant — dismiss]`.

**Key rule:** no text in this sheet is ever truncated. Every `lineLimit(...)` modifier present in `GenomeView.swift` today gets removed in the sheet rendering. The sheet is the floor of the deep well — past it there is no further "tap to expand".

## iPad Layout (`GenomeSplitView`)

`NavigationSplitView` with three columns at regular size class:

- **Sidebar (260pt)**: existing app side menu with a new "Start Visit" button at the bottom.
- **List (360pt)**: pinned "Your Top Priorities" card at the top (collapsible), then the existing category breakdown — exactly the same grouping the iPhone view uses today, just always-visible. ClinVar themes get the same treatment.
- **Detail (flex, ≥520pt)**: `GenomeDetailSheet` content embedded directly — no sheet presentation.

Empty detail state: "Select a finding to see details, action plan, and visit notes."

Compact-width iPad (split-screen multitasking): falls back to iPhone single-column layout. Three panes are not maintained below 600pt.

## Visit Mode (`GenomeVisitModeView`)

**Activation**: "Start Visit" button in the iPad sidebar (or Genome toolbar on iPhone) opens a small sheet asking for visit date + optional provider label, then `[Begin Visit]`.

**Active layout**: two columns, no sidebar, larger base font (`.title3` body / `.title2` headings).

- **Left (priorities)**: only the user's top priorities (not the full category browse). Each row shows status (pending / discussed). A "Discussed: 2 / 4" counter and `[End Visit & Print Summary]` button below.
- **Right (current finding)**: focused single-finding view with:
  - Big talking-point block at top
  - Multi-line "Notes from this visit" textarea
  - Optional "Follow-up" single-line field
  - Action checkboxes (auto-marked `discussed` on Save & Next)
  - `[Save & Next ▸]` button — saves a `VisitNote`, flips that finding's pending actions to `discussed`, advances to next undiscussed priority.

**End Visit**: generates the post-visit summary PDF and presents share sheet (AirPrint included).

**iPhone fallback**: single-column paginated; same data flow, less ideal but viable.

## Top Priorities Engine (`GenomePriorityEngine`)

Pure function:

```swift
static func rank(
    summary: GenomeScanSummary,
    clinvarHits: [ClinVarHit],
    library: [GenomeAction],
    states: [String: GenomeActionState],
    lifestyle: LifestyleData?
) -> [PriorityFinding]
```

Returns up to **7** priorities. Score formula:

```
score = severity × confidence × actionability × lifestyleAmplifier × freshness
```

| Factor | Range | Source |
|---|---|---|
| **severity** | 0.2 – 1.0 | `majorConcern` / pathogenic = 1.0, `concern` / risk_factor = 0.7, drug_response = 0.5, beneficial = 0.2 |
| **confidence** | 0.5 – 1.0 | ClinVar stars (4★ = 1.0, 1★ = 0.6); curated markers default to 0.85 |
| **actionability** | 0.4 – 1.0 | 1.0 if library has ≥1 action with `kind ≠ research`; 0.4 if research-only |
| **lifestyleAmplifier** | 1.0 – 1.4 | Boost when modifiable lifestyle is mismatched (APOE ε4 + low exercise = 1.4; 9p21 CAD + smoker = 1.4; ADH/ALDH + heavy drinker = 1.3). Small rule table. |
| **freshness** | 0.7 – 1.0 | 1.0 if no actions accepted; 0.85 if ≥1 `inProgress`; 0.7 if all `discussed` / `done` |

**Filtering rules:**

- Finding excluded if all of its actions are `dismissed`.
- Finding excluded while any action is `snoozed` and snooze unexpired (6mo hardcoded).
- `beneficial` markers without monitoring actions are excluded ("your FOXO3A is great" doesn't belong at the top).
- Drug-response variants always shown if no `discussed` state, regardless of severity.

## Goals/Habits Bridge

### Add flow (genome → habit/goal)

1. User taps a `GenomeAction` row's primary CTA (`Add as habit ▸` / `Set as goal ▸`).
2. The existing `AddHabitSheet` / `AddGoalSheet` opens, **prefilled** from the action's `HabitTemplate` / `GoalTemplate`.
3. A banner at the top reads: `🧬 Suggested by your DNA: APOE ε3/ε4 — Cardio strengthens cardiovascular & cognitive resilience…`
4. User can edit any field. On save:
   - The new habit/goal is created with `geneticEvidence` populated.
   - The corresponding `GenomeActionState` flips `pending` → `inProgress` and stores `linkedHabitId` / `linkedGoalId`.

### Reverse view (habit/goal → genome)

`HabitDetailView` and goal detail screens get a `🧬 Suggested by your DNA` section when `geneticEvidence != nil`. Tap `View finding ▸` to open the corresponding `GenomeDetailSheet` (or select it in the iPad split view).

### State sync rules

- **Habit/Goal completed/abandoned/archived** → action state stays `inProgress`. Doesn't auto-flip to `done` — archiving a habit doesn't mean the underlying genetic concern is resolved.
- **Habit/Goal deleted** → action state's `linkedHabitId` / `linkedGoalId` gets nil'd lazily on next load. Action returns to `pending`.
- **Re-prompting allowed** — even if a previous habit was archived, the user can tap "Add as habit" again to start fresh.

### `RecommendationEngine` integration

```swift
static func generate(
    lifestyle: LifestyleData,
    alcoholRisk: AlcoholRisk,
    hasGenomeData: Bool,
    hasEpigeneticData: Bool,
    hasBloodTests: Bool,
    genomePriorities: [PriorityFinding] = []   // NEW
) -> [Recommendation]
```

Up to **3** unaccepted genome priorities translate to `Recommendation`s:

- `id: "genome-<actionId>"` — stable for dedup.
- `icon`: from action `kind` (e.g. `figure.run`, `drop.fill`).
- `title`: from action title.
- `detail`: prefixed with the source — `"Your DNA: APOE ε3/ε4. Cardio is neuroprotective for ε4 carriers."`
- `yearsGained`: from a small genome-impact lookup, attenuated 0.7× vs measured-lifestyle so they don't dominate.
- `targetPage: 6` (genome) — tap takes you to the priorities card.

**Dedup**: if a genome action is already `inProgress` (linked to habit/goal), it does NOT generate a recommendation. Overview shouldn't double-prompt.

## PDF Export (`GenomeReportPDF`)

Two flavors, same generator.

### A. Pre-Visit Prep PDF

Generated from the **Genome → "Export PDF"** button (sidebar, priorities card, detail sheet toolbar).

Contents:
- Header (date, optional patient name from profile, source: 23andMe / AncestryDNA / build).
- "About this report" disclaimer (consumer DTC, not diagnostic, CLIA confirmation recommended).
- **Top Priorities** section — for each, status, rsid, genotype, ClinVar stars, conditions, talking point, suggested actions, citations.
- **Drug-Response Variants** table — gene, rsid, genotype, significance, stars. Pharmacist-friendly.
- **All findings by category** — optional appendix, off by default.
- Privacy footer on every page: "Generated by MortalLoom · No data leaves your device."

### B. Post-Visit Summary PDF

Generated from "End Visit & Print Summary" at the end of Visit Mode. Same content as A, but each priority gets a **Discussed [date] with [provider]** block underneath the talking point with the captured note + follow-up. Suggested actions become checkboxes reflecting visit-time status.

### Generation tech

- **PDFKit** via `UIGraphicsPDFRenderer` (iOS) and `NSGraphicsContext` PDF context (macOS). Tiny shared layout layer.
- No third-party dependency (per project dependency rules).
- Letter-size, single-column, 11pt body, 14pt headers.
- B/W-friendly: dots and checkboxes preserve meaning when printed monochrome.
- Page numbers + footer: "MortalLoom · Genetic Pre-Visit Notes · p.X/Y".

### Sharing & printing

After generation, present `UIActivityViewController` (iOS) / `NSSharingServicePicker` (macOS) with the PDF:
- **Print** (AirPrint — primary path for in-clinic use)
- **Save to Files** (iCloud Drive, on-device)
- **Share via Mail** (manual, user-initiated)
- **Markup** (annotate before printing)

No automatic upload. PDF lives in the temp dir until the user explicitly chooses what to do with it.

### Toolbar / button placement

- Genome tab toolbar (top-right): `square.and.arrow.up` → "Export Pre-Visit PDF"
- Priorities card bottom: `[Export PDF]` button
- Detail sheet toolbar: `square.and.arrow.up` → "Export Single Finding PDF"
- Visit Mode end: `[End Visit & Print Summary]` → Post-Visit PDF

## Privacy

The brand promise is preserved end-to-end:

- All new data (`GenomeActionState`, `VisitNote`, `GeneticEvidence`) lives in the existing local `MortalLoom.json` + iCloud ubiquity container.
- No telemetry, no analytics, no server roundtrip.
- PDF generation is local. The temp file is never auto-shared.
- The doctor PDF includes the disclaimer that the data is consumer DTC and was generated locally.

## Testing Strategy

- **`GenomeActionLibrary`**: unit tests asserting every entry has stable `id`, valid `citationIds`, and at least one `GenomeActionCondition`.
- **`GenomePriorityEngine.rank(...)`**: pure function — comprehensive unit tests for severity/confidence/actionability/freshness math, lifestyle amplifier rules, snooze/dismiss filtering, and the cap of 7.
- **`RecommendationEngine.generate(...)`**: regression tests that existing lifestyle recommendations still appear unchanged when `genomePriorities = []`; new tests covering DNA-derived recs and the dedup-against-`inProgress` rule.
- **Decoder back-compat**: tests that load fixture JSON files lacking the new fields and verify decoding still succeeds.
- **`GenomeReportPDF`**: snapshot tests of generated PDFs (deterministic content given fixed inputs).
- **UI**: SwiftUI previews for `GenomeDetailSheet`, `GenomePrioritiesCard`, `GenomeSplitView`, `GenomeVisitModeView` covering empty / loading / loaded / dismissed states.

## Migration

No migration needed. All new fields decode with `decodeIfPresent`; all new top-level `AppData` collections default to empty.

## Open Questions / Future Work

These are deliberately out of scope for this design but worth noting:

- **Stagnation engine integration**: `Engine/StagnationEngine.swift` could later weight genome-linked habits higher when nudging. Data is already there.
- **Trend charts in PDF**: when blood test data is linked to a genome finding (e.g. homocysteine for MTHFR), include a small trend chart. Future enhancement; current PDF is text-only.
- **Action library breadth**: reaching all 116 markers takes ongoing curation. Tracked as a follow-up content task, not a blocker for shipping.
- **Family history input**: many genetic actions are modulated by family history. Current design ignores it; could be a follow-up enhancement.
