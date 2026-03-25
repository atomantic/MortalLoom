# MortalLoom Feature Parity Plan

Port all MeatSpace features from PortOS web app to native iOS/macOS SwiftUI.

## Phase 1: Core Infrastructure
- [x] Models — all data types (health metrics, blood markers, substances, genome, lifestyle, eye exams, epigenetic tests)
- [x] Storage — actor-based file I/O with iCloud Documents + local fallback
- [x] HealthKit service — native Apple Health read access (not CSV/XML import)

## Phase 2: Death Clock + Overview
- [x] Death clock engine — SSA baseline life expectancy, lifestyle adjustments, genome adjustments
- [x] Live countdown timer on Overview (Y:Mo:W:D:H:M:S ticking every second)
- [x] Life progress bar
- [x] LEV (Longevity Escape Velocity) tracker
- [x] Health summary tiles linking to each section

## Phase 3: Lifestyle Questionnaire
- [x] Profile — birth date, biological sex
- [x] Smoking status, exercise minutes/week, sleep hours/night
- [x] Diet quality, stress level, BMI
- [x] Impact preview showing year adjustments per factor

## Phase 4: Substance Tracking
- [x] Alcohol — log drinks (name, oz, ABV%, count, date), quick-add presets, NIAAA risk levels
- [x] Nicotine — log products (name, mg/unit, count, date), quick-add presets
- [x] Rolling averages (today, 7d, 30d, weekly, all-time)
- [x] Charts (Swift Charts) for consumption trends

## Phase 5: Blood, Body, Eyes
- [x] Blood tests — manual entry for 50+ markers with reference ranges, status colors
- [x] Body composition — weight/body fat tracking with chart
- [x] Eye prescriptions — CRUD with SPH/CYL/AXIS per eye

## Phase 6: Genome + Epigenetic Age
- [x] Raw genome file import (23andMe, AncestryDNA text format)
- [x] On-device variant parsing + category classification
- [x] Epigenetic age tracking (biological vs chronological, pace of aging, organ scores)

## Phase 7: Data Export/Import + Charts
- [x] JSON export of all user data
- [x] JSON import to restore data
- [x] Alcohol + HRV correlation chart (dual-axis: bars + line, summary stats)
- [x] Nicotine + Heart Rate correlation chart (HR + resting HR lines, summary stats)
- [x] HealthMetricEntry model with iCloud sync (HRV, HR, steps, etc.)
- [x] Comprehensive test suite (118 unit tests + UI screenshot automation)
- [x] Sample data factory for screenshots (-sample-data launch arg)
- [x] Activity + blood marker correlation chart

## Phase 8: Goal Tracking
- [x] Goal model with check-ins, milestones, priority, status, target dates
- [x] GoalEngine — progress velocity projection, deadline slippage, cognitive/lifespan warnings
- [x] GoalsView — full CRUD, check-in sheets, edit sheets, context menus
- [x] Life Calendar integration — goal target/projected dates as teal markers on all grid modes
- [x] Sample goals (book, marathon, piano, garden)
- [x] 12 new tests (Goal model, GoalEngine projections, sample data validation)

## Not Porting (web-specific)
- Apple Health XML/JSON file import (replaced by native HealthKit)
- Server-side API calls (all local/on-device)
- ClinVar database sync (too large for on-device, defer to future)
- WebSocket progress updates
