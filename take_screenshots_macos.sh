#!/bin/bash
#
# take_screenshots_macos.sh — Capture macOS App Store screenshots.
#
# Prerequisites:
#   Your terminal app needs Screen Recording permission (System Settings > Privacy & Security)
#   to capture the app window.
#
# Usage:
#   ./take_screenshots_macos.sh
#

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/MortalLoom.xcodeproj"
SCHEME="MortalLoom_macOS"
SCREENSHOTS_DIR="$PROJECT_DIR/screenshots"
DERIVED_DATA="$PROJECT_DIR/.build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/MortalLoom.app"

# Pages to capture: "page_name|output_filename|extra_args"
# extra_args lets us pass additional launch flags (e.g. -substance-tab nicotine)
PAGES=(
    "overview|01_overview|"
    "goals|02_goals|"
    "habits|03_habits_alcohol|-substance-tab alcohol"
    "habits|04_habits_nicotine|-substance-tab nicotine"
    "body|05_body|"
    "blood|06_blood|"
    "sleep|07_sleep|"
    "calendar|08_calendar|"
    "lifestyle|09_lifestyle|"
    "genome|10_genome|"
)

echo "=========================================="
echo "  MortalLoom macOS Screenshot Capture"
echo "=========================================="
echo "  Pages:  ${#PAGES[@]}"
echo "  Output: $SCREENSHOTS_DIR/en/macos/"
echo "=========================================="
echo ""

# Ensure xcodegen project is up to date
echo "🔧 Generating Xcode project..."
cd "$PROJECT_DIR" && xcodegen generate --quiet 2>&1
echo ""

# Build macOS app
echo "🔨 Building macOS app..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet 2>&1 || {
        echo "❌ Build failed"
        exit 1
    }
echo "✅ Build complete"
echo ""

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ App not found at $APP_PATH"
    exit 1
fi

# Get window ID for MortalLoom (largest window > 100px tall)
get_window_id() {
    swift -e '
    import Cocoa
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
    var best = 0
    var bestArea = 0
    for w in windowList {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        guard owner == "MortalLoom" else { continue }
        let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let h = bounds["Height"] as? Int ?? 0
        let w2 = bounds["Width"] as? Int ?? 0
        let area = h * w2
        if area > bestArea {
            bestArea = area
            best = w[kCGWindowNumber as String] as? Int ?? 0
        }
    }
    if best > 0 { print(best) }
    ' 2>/dev/null
}

# Take screenshot of MortalLoom window, then resize to App Store dimensions
capture_window() {
    local output_path="$1"
    sleep 1
    local wid
    wid=$(get_window_id)
    if [[ -n "$wid" ]]; then
        screencapture -l "$wid" -o -x "$output_path" 2>/dev/null
        # Resize to exact App Store dimensions (2880x1800 for Retina)
        if [[ -f "$output_path" ]]; then
            sips --resampleHeightWidth 1800 2880 "$output_path" >/dev/null 2>&1
        fi
    else
        echo "   ⚠️  Could not find MortalLoom window"
    fi
}

OUT_DIR="$SCREENSHOTS_DIR/en/macos"
mkdir -p "$OUT_DIR"

# Keep display awake during capture
caffeinate -u -t 300 &
CAFFEINATE_PID=$!

echo "📸 Capturing macOS screenshots..."

CURRENT=0
for page_spec in "${PAGES[@]}"; do
    IFS='|' read -r PAGE_NAME OUTPUT_NAME EXTRA_ARGS <<< "$page_spec"
    CURRENT=$((CURRENT + 1))
    echo "  [$CURRENT/${#PAGES[@]}] $OUTPUT_NAME..."

    # Kill any existing instance
    killall MortalLoom 2>/dev/null || true
    sleep 2

    # Launch with sample data and target page (plus any per-page extra args)
    # shellcheck disable=SC2086
    open "$APP_PATH" --args \
        -sample-data \
        -hasCompletedOnboarding 1 \
        -force-pro \
        -start-page "$PAGE_NAME" \
        $EXTRA_ARGS

    sleep 5
    capture_window "$OUT_DIR/${OUTPUT_NAME}.png"
done

# Quit
killall MortalLoom 2>/dev/null || true
kill "$CAFFEINATE_PID" 2>/dev/null || true
sleep 1

COUNT=$(ls "$OUT_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "=========================================="
echo "  macOS Screenshot Capture Complete"
echo "=========================================="
echo "  en/macos: $COUNT screenshots"

echo ""
echo "Done! Upload to App Store Connect under the macOS platform."
