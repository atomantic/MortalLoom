# CLAUDE.md

## Commands

```bash
# Generate Xcode project (required after project.yml changes)
xcodegen generate

# Build iOS
xcodebuild build -project MeatSpace.xcodeproj -scheme MeatSpace_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet

# Build macOS
xcodebuild build -project MeatSpace.xcodeproj -scheme MeatSpace_macOS \
  -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet

# Run tests
xcodebuild test -project MeatSpace.xcodeproj -scheme MeatSpaceTests_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet

# Deploy to TestFlight
./deploy.sh              # iOS only
./deploy.sh --macos      # macOS only
./deploy.sh --all        # Both
./deploy.sh --skip-tests # Skip tests
```

## Architecture

MeatSpace Tracker is a native iOS/macOS SwiftUI app for lifespan health tracking. It mirrors the MeatSpace section of the PortOS web app.

- **Bundle ID**: `net.shadowpuppet.MeatSpaceTracker`
- **Team ID**: `TYQ32QCF6K`
- **App Store Connect ID**: `6760883701`
- **Platforms**: iOS 17.0+, macOS 14.0+
- **Language**: Swift 6.0

### Project Structure
```
MeatSpace/
├── App/          # Entry point, Info.plist, entitlements
├── Theme/        # Colors, layout constants, card styles
├── Views/        # SwiftUI views (Overview, Body, Substances, Blood, Genome, Lifestyle, Settings)
├── Engine/       # Pure computation (death clock, risk assessment, rolling averages)
├── Models/       # Data types (health metrics, blood markers, genome variants)
├── Storage/      # Actor-based file I/O, iCloud sync
```

### Key Features (from PortOS MeatSpace)
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

## Git Workflow

- **main**: Active development
- **Push pattern**: `git pull --rebase --autostash && git push`
