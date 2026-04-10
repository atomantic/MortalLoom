# MortalLoom

<p align="center">
  <img src="LogoSimple.png" alt="MortalLoom" width="200" />
</p>

<p align="center">
  Privacy-first longevity and health tracking for iOS and macOS.
</p>

<p align="center">
  No accounts. No data collection. No servers. Your health data stays on your device and in your iCloud.
</p>

## Features

- **Longevity Clock** — Life expectancy countdown based on actuarial data, genetics, and lifestyle
- **Epigenetic Age** — Track biological vs chronological age
- **Blood Tests** — 50+ lab markers with reference ranges and trend tracking
- **Body Composition** — Weight, body fat, and eye prescription history
- **Substance Tracking** — Alcohol and nicotine logging with NIAAA risk levels
- **Genome Analysis** — Upload 23andMe/AncestryDNA data, cross-reference ClinVar
- **Apple Health** — Steps, heart rate, HRV, sleep, VO2 max, and more
- **Lifestyle Assessment** — Quantify how habits affect your longevity estimate
- **Life Calendar** — 4000-weeks grid visualization of your entire lifespan
- **LEV Tracker** — Monitor progress toward Longevity Escape Velocity (2045)

## Privacy

MortalLoom collects zero data. There are no analytics, no telemetry, no third-party SDKs, and no server-side components. All data is stored locally on your device and optionally synced via your personal iCloud account. You can export your data anytime.

## Development

### Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Apple Developer account (Team ID: TYQ32QCF6K)

### Setup

```bash
# Clone
git clone git@github.com:atomantic/MortalLoom.git
cd MortalLoom

# Configure deployment credentials
cp .env.example .env
# Edit .env with your App Store Connect API key details

# Generate Xcode project
xcodegen generate

# Build
xcodebuild build -project MortalLoom.xcodeproj -scheme MortalLoom_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -quiet
```

### Deploy to TestFlight

```bash
./deploy.sh              # iOS only
./deploy.sh --macos      # macOS only
./deploy.sh --all        # Both platforms
./deploy.sh --skip-tests # Skip test run
```

### Project Structure

```
MortalLoom/
├── App/          # Entry point, Info.plist, entitlements
├── Theme/        # Adaptive colors, layout constants, card styles
├── Views/        # SwiftUI views per feature section
├── Engine/       # Pure computation (longevity clock, risk assessment)
├── Models/       # Data types (health metrics, blood markers)
├── Storage/      # Actor-based file I/O, iCloud sync
```

## Tech Stack

- **Swift 6.0** / **SwiftUI**
- **iOS 17.0+** / **macOS 14.0+**
- **XcodeGen** for project generation
- **HealthKit** for Apple Health integration
- **iCloud Documents** for cross-device sync
- **GitHub Actions** for CI

## License

Proprietary. Copyright 2026 ShadowPuppet, LLC.
