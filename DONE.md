# Done Log

Completed items archived from PLAN.md. For release notes, see `.changelogs/`.

## 2026-03-25

- Core infrastructure — all models, actor-based storage with iCloud + local fallback, native HealthKit service
- Death clock engine — SSA baseline life expectancy, lifestyle/genome adjustments, live countdown, LEV tracker
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
