# Development Plan

For project mission and milestones, see [GOALS.md](./GOALS.md).
For completed work, see [DONE.md](./DONE.md).

## Next Up

1. **Genome adjustment in death clock**: Implement actual genome risk calculation (TODO at `DeathClockEngine.swift:83` — currently stubbed to baseline)
2. **Accessibility audit**: Add `.accessibilityLabel`, `.accessibilityHint`, `.accessibilityValue` across all 12 Views — zero a11y coverage currently
3. **Storage/HealthKit test coverage**: Unit tests for DataStore actor, HealthKitService auth states, ICloudMonitor metadata queries

## Backlog

- [ ] VoiceOver testing pass on iOS

## Not Porting (web-specific)

- Apple Health XML/JSON file import (replaced by native HealthKit)
- Server-side API calls (all local/on-device)
- ClinVar database sync (too large for on-device, defer to future)
- WebSocket progress updates
