# CLAUDE.md

## Commands

```bash
# Generate Xcode project (required after project.yml changes)
xcodegen generate

# Build iOS
xcodebuild build -project MortalLoom.xcodeproj -scheme MortalLoom_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet

# Build macOS
xcodebuild build -project MortalLoom.xcodeproj -scheme MortalLoom_macOS \
  -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet

# Run tests
xcodebuild test -project MortalLoom.xcodeproj -scheme MortalLoomTests_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet

# Deploy to TestFlight
./deploy.sh              # iOS only
./deploy.sh --macos      # macOS only
./deploy.sh --all        # Both
./deploy.sh --skip-tests # Skip tests
```

## Product Vision

MortalLoom is a **privacy-first longevity tracking app**. No accounts, no logins, no data collection, no telemetry, no third-party tracking. Your health data stays on your device and in your iCloud — never on our servers (we don't have any). You can export your data anytime, but it's never shared without your explicit action.

This is the core brand promise and must be reflected in all App Store copy, marketing, and in-app messaging.

## Architecture

MortalLoom is a native iOS/macOS SwiftUI app for lifespan health tracking. It mirrors the MeatSpace section of the PortOS web app under a new brand.

- **Bundle ID**: `net.shadowpuppet.MeatSpaceTracker`
- **Team ID**: `TYQ32QCF6K`
- **App Store Connect ID**: `6760883701`
- **Platforms**: iOS 17.0+, macOS 14.0+
- **Language**: Swift 6.0

### Project Structure
```
MortalLoom/
├── App/          # Entry point, Info.plist, entitlements
├── Theme/        # Colors, layout constants, card styles
├── Views/        # SwiftUI views (Overview, Body, Substances, Blood, Genome, Lifestyle, Settings)
├── Engine/       # Pure computation (death clock, risk assessment, rolling averages)
├── Models/       # Data types (health metrics, blood markers, genome variants)
├── Storage/      # Actor-based file I/O, iCloud sync
```

### Key Features
- Death clock countdown with life expectancy calculation
- Epigenetic age tracking
- Alcohol & nicotine substance tracking with NIAAA risk levels
- Blood test results with 50+ reference ranges
- Body composition & eye prescription tracking
- Genome analysis with ClinVar cross-reference
- Apple Health integration
- Lifestyle questionnaire for mortality calculations

### Data Source
- **XcodeGen** (`project.yml`) is the source of truth — never edit xcodeproj directly
- **iCloud Documents** with local fallback for data persistence

## Code Conventions

- **No classes** — use functional programming + actors
- **No try/catch** — errors bubble to centralized handling
- **Pure engine functions** — no side effects, testable in isolation
- **Platform-adaptive** — `#if os(macOS)` / `#if os(iOS)` guards
- **Dark mode default** with light/dark adaptive colors
- **Single-line emoji-prefixed logging**

## iCloud Sync Pattern

Data is stored as a single JSON file (`MortalLoom.json`) dual-written to both local Documents and the iCloud ubiquity container (`iCloud.net.shadowpuppet.MeatSpaceTracker`). Loads use a `newerOf(cloud:local:)` modification-date comparison.

`ICloudMonitor` (Storage/ICloudMonitor.swift) is `@Observable @MainActor` and watches for remote file changes via `NSMetadataQuery`. On detection it debounces 2s, suppresses reloads within 5s of a local write (`markLocalWrite()`), then calls `DataStore.reloadIfNeeded()` and posts `.dataDidSync` + `.profileDidChange` to refresh the UI.

The same pattern is used in ADultingHD (multiple JSON files) and EscapeMint-Swift.

## Git Workflow

- **main**: Active development
- **Push pattern**: `git pull --rebase --autostash && git push`
