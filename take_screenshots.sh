#!/bin/bash
#
# take_screenshots.sh — Capture App Store Connect screenshots for iPhone and iPad.
#
# Usage:
#   ./take_screenshots.sh                       # all devices
#   ./take_screenshots.sh --iphone-only         # iPhone only
#   ./take_screenshots.sh --ipad-only           # iPad only
#   ./take_screenshots.sh --screen 01_overview  # only capture one screen
#

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/MortalLoom.xcodeproj"
SCHEME="MortalLoom_iOS"
SCREENSHOTS_DIR="$PROJECT_DIR/screenshots"
CONFIG_FILE_PROJECT="$PROJECT_DIR/.screenshot_config.json"
CONFIG_FILE_TMP="/tmp/mortalloom_screenshot_config.json"
DERIVED_DATA="$PROJECT_DIR/.build/DerivedData"
BUNDLE_ID="net.shadowpuppet.MeatSpaceTracker"

# App Store Connect screenshot device specs
# Format: "Simulator Name|OS version|folder_name|test_method"
IPHONE_DEVICE="iPhone 16 Pro Max|18.6|iphone_6.7|testCaptureIPhoneScreenshots"
IPAD_DEVICE="iPad Pro 13-inch (M4)|18.6|ipad_13|testCaptureIPadScreenshots"

# Parse arguments
DEVICES=()
SCREEN=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iphone-only) DEVICES=("$IPHONE_DEVICE") ; shift ;;
        --ipad-only)   DEVICES=("$IPAD_DEVICE") ; shift ;;
        --screen)      SCREEN="$2" ; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--iphone-only|--ipad-only] [--screen <name>]"
            echo ""
            echo "Devices: iPhone 16 Pro Max (6.7\"), iPad Pro 13\" (M4)"
            echo "Screens: 01_overview 02_overview_scroll 03_goals 04_calendar 05_habits"
            echo "         05a_substances_alcohol 06_substances_nicotine 07_body 08_blood"
            echo "         09_sleep 10_lifestyle"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" ; exit 1 ;;
    esac
done

# Defaults
[[ ${#DEVICES[@]} -eq 0 ]] && DEVICES=("$IPHONE_DEVICE" "$IPAD_DEVICE")

TOTAL_DEVICES=${#DEVICES[@]}
CURRENT_RUN=0
FAILED=()

echo "=========================================="
echo "  MortalLoom App Store Screenshot Capture"
echo "=========================================="
echo "  Devices:   $TOTAL_DEVICES"
echo "  Total runs: $TOTAL_DEVICES"
[[ -n "$SCREEN" ]] && echo "  Screen:    $SCREEN"
echo "  Output:    $SCREENSHOTS_DIR/en/{device}/"
echo "=========================================="
echo ""

# Ensure xcodegen project is up to date
echo "🔧 Generating Xcode project..."
cd "$PROJECT_DIR" && xcodegen generate --quiet 2>&1
echo ""

write_config() {
    local device="$1"
    cat > "$CONFIG_FILE_PROJECT" <<JSONEOF
{
    "device": "$device",
    "output_dir": "$SCREENSHOTS_DIR",
    "target_screen": "$SCREEN"
}
JSONEOF
    cp "$CONFIG_FILE_PROJECT" "$CONFIG_FILE_TMP" 2>/dev/null || true
}

# Build test bundles (once per device)
for device_spec in "${DEVICES[@]}"; do
    IFS='|' read -r DEVICE_NAME DEVICE_OS DEVICE_FOLDER TEST_METHOD <<< "$device_spec"

    echo "🔨 Building test bundle for $DEVICE_NAME..."
    xcodebuild build-for-testing \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=$DEVICE_OS" \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO \
        -quiet 2>&1 || {
            echo "❌ Build failed for $DEVICE_NAME"
            exit 1
        }
    echo "✅ Build complete for $DEVICE_NAME"
    echo ""
done

# Boot simulators and pre-grant permissions
for device_spec in "${DEVICES[@]}"; do
    IFS='|' read -r DEVICE_NAME _ _ _ <<< "$device_spec"
    echo "🚀 Booting $DEVICE_NAME simulator..."
    xcrun simctl boot "$DEVICE_NAME" 2>/dev/null || true
done
sleep 3
for device_spec in "${DEVICES[@]}"; do
    IFS='|' read -r DEVICE_NAME _ _ _ <<< "$device_spec"
    xcrun simctl privacy "$DEVICE_NAME" grant notifications "$BUNDLE_ID" 2>/dev/null || true
done

# Capture screenshots
for device_spec in "${DEVICES[@]}"; do
    IFS='|' read -r DEVICE_NAME DEVICE_OS DEVICE_FOLDER TEST_METHOD <<< "$device_spec"
    CURRENT_RUN=$((CURRENT_RUN + 1))

    echo "📸 [$CURRENT_RUN/$TOTAL_DEVICES] en on $DEVICE_NAME..."

    write_config "$DEVICE_FOLDER"

    if xcodebuild test-without-building \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=$DEVICE_OS" \
        -derivedDataPath "$DERIVED_DATA" \
        -only-testing:"MortalLoomUITests_iOS/ScreenshotTests/$TEST_METHOD" \
        CODE_SIGNING_ALLOWED=NO \
        -quiet 2>&1; then
        echo "   ✅ en / $DEVICE_FOLDER complete"
    else
        echo "   ⚠️  en / $DEVICE_FOLDER had failures (screenshots may still be saved)"
        FAILED+=("en/$DEVICE_FOLDER")
    fi
done

# Clean up config files
rm -f "$CONFIG_FILE_PROJECT" "$CONFIG_FILE_TMP"

# Summary
echo ""
echo "=========================================="
echo "  Screenshot Capture Complete"
echo "=========================================="

for device_spec in "${DEVICES[@]}"; do
    IFS='|' read -r _ _ DEVICE_FOLDER _ <<< "$device_spec"
    DIR="$SCREENSHOTS_DIR/en/$DEVICE_FOLDER"
    if [[ -d "$DIR" ]]; then
        COUNT=$(ls "$DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
        echo "  en/$DEVICE_FOLDER: $COUNT screenshots"
    fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "⚠️  Runs with failures:"
    for f in "${FAILED[@]}"; do
        echo "  - $f"
    done
fi

echo ""
echo "Done! Upload screenshots to App Store Connect via Transporter or the web UI."
