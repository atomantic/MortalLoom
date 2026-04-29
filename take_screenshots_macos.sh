#!/bin/bash
#
# take_screenshots_macos.sh — Capture macOS App Store screenshots.
#
# SAFETY: On 2026-04-09 this script clobbered the developer's real MortalLoom
# data because -sample-data launched the built binary and the old DataStore
# code persisted sample data through to local + iCloud Documents. The fix is
# in DataStore.swift (sampleDataMode short-circuits save()). This script adds
# defense-in-depth in case that fix is ever regressed:
#
#   1. Source verification: aborts if DataStore.swift lacks the sampleDataMode
#      guard. This catches reverts BEFORE we launch the binary.
#   2. Pre-run backup: copies the current local + iCloud MortalLoom.json files
#      to /tmp/mortalloom_screenshot_backup_<ts>_{local,icloud}.json with md5.
#   3. Post-run integrity check (runs via EXIT trap even on crash): re-hashes
#      both files. If either changed, ALERTS LOUDLY and auto-restores from
#      the pre-run backup. If unchanged, the run is declared safe.
#   4. Rotating backups: keeps the last 5 so you can manually recover if
#      something slips through all the other guards.
#
# Prerequisites:
#   Your terminal app needs Screen Recording permission (System Settings >
#   Privacy & Security) to capture the app window.
#
# Usage:
#   ./take_screenshots_macos.sh           # safe mode (recommended)
#   ./take_screenshots_macos.sh --yolo    # skip safety checks (NOT recommended)
#

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/MortalLoom.xcodeproj"
SCHEME="MortalLoom_macOS"
SCREENSHOTS_DIR="$PROJECT_DIR/screenshots"
DERIVED_DATA="$PROJECT_DIR/.build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/MortalLoom.app"

# Real data file paths (the ones we must never clobber)
LOCAL_DATA="$HOME/Library/Containers/net.shadowpuppet.MeatSpaceTracker/Data/Documents/MortalLoom.json"
ICLOUD_DATA="$HOME/Library/Mobile Documents/iCloud~net~shadowpuppet~MeatSpaceTracker/Documents/MortalLoom.json"

YOLO=0
if [[ "${1:-}" == "--yolo" ]]; then
    YOLO=1
    echo "⚠️  --yolo mode: skipping safety checks"
fi

# ---------------------------------------------------------------
# Safety: verify the source has the sampleDataMode guard
# ---------------------------------------------------------------
verify_source_safety() {
    local store="$PROJECT_DIR/MortalLoom/Storage/DataStore.swift"
    local app="$PROJECT_DIR/MortalLoom/App/MortalLoomApp.swift"
    local missing=()

    if ! grep -q 'sampleDataMode' "$store" 2>/dev/null; then
        missing+=("DataStore.swift missing sampleDataMode flag")
    fi
    if ! grep -q 'enableSampleDataMode' "$store" 2>/dev/null; then
        missing+=("DataStore.swift missing enableSampleDataMode()")
    fi
    if ! grep -q 'enableSampleDataMode' "$app" 2>/dev/null; then
        missing+=("MortalLoomApp.swift not calling enableSampleDataMode()")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ SOURCE SAFETY CHECK FAILED:"
        for m in "${missing[@]}"; do
            echo "    - $m"
        done
        echo ""
        echo "   The sampleDataMode regression detector tripped."
        echo "   Refusing to run the screenshot script because -sample-data"
        echo "   could clobber your real iCloud data without those guards."
        echo ""
        echo "   Fix the source, or bypass with --yolo (NOT recommended)."
        exit 2
    fi
    echo "✅ Source safety check passed"
}

# ---------------------------------------------------------------
# Backup: capture md5 + copy both data files to /tmp
# ---------------------------------------------------------------
BACKUP_TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/tmp/mortalloom_screenshot_backup_${BACKUP_TS}"
PRE_LOCAL_MD5=""
PRE_ICLOUD_MD5=""

backup_real_data() {
    mkdir -p "$BACKUP_DIR"

    if [[ -f "$LOCAL_DATA" ]]; then
        cp "$LOCAL_DATA" "$BACKUP_DIR/local.json"
        PRE_LOCAL_MD5=$(md5 -q "$LOCAL_DATA")
        echo "  📦 local  backed up (md5 ${PRE_LOCAL_MD5:0:12}…)"
    else
        echo "  📦 local  file does not exist (nothing to back up)"
    fi

    if [[ -f "$ICLOUD_DATA" ]]; then
        cp "$ICLOUD_DATA" "$BACKUP_DIR/icloud.json"
        PRE_ICLOUD_MD5=$(md5 -q "$ICLOUD_DATA")
        echo "  📦 icloud backed up (md5 ${PRE_ICLOUD_MD5:0:12}…)"
    else
        echo "  📦 icloud file does not exist (nothing to back up)"
    fi

    echo "  📦 backup dir: $BACKUP_DIR"

    # Rotate: keep last 5 screenshot backups, delete the rest
    ls -td /tmp/mortalloom_screenshot_backup_* 2>/dev/null | tail -n +6 | while read -r old; do
        echo "  🗑  pruning old backup $old"
        rm -rf "$old"
    done
}

# ---------------------------------------------------------------
# Verify integrity: compare md5 to pre-run values, restore if changed
# ---------------------------------------------------------------
verify_and_restore() {
    echo ""
    echo "=========================================="
    echo "  Post-run integrity check"
    echo "=========================================="

    local local_ok=1
    local icloud_ok=1

    if [[ -n "$PRE_LOCAL_MD5" && -f "$LOCAL_DATA" ]]; then
        local post_local_md5
        post_local_md5=$(md5 -q "$LOCAL_DATA")
        if [[ "$post_local_md5" == "$PRE_LOCAL_MD5" ]]; then
            echo "  ✅ local  unchanged (md5 match)"
        else
            echo "  🚨 local  CHANGED — expected ${PRE_LOCAL_MD5:0:12}… got ${post_local_md5:0:12}…"
            local_ok=0
        fi
    fi

    if [[ -n "$PRE_ICLOUD_MD5" && -f "$ICLOUD_DATA" ]]; then
        local post_icloud_md5
        post_icloud_md5=$(md5 -q "$ICLOUD_DATA")
        if [[ "$post_icloud_md5" == "$PRE_ICLOUD_MD5" ]]; then
            echo "  ✅ icloud unchanged (md5 match)"
        else
            echo "  🚨 icloud CHANGED — expected ${PRE_ICLOUD_MD5:0:12}… got ${post_icloud_md5:0:12}…"
            icloud_ok=0
        fi
    fi

    if [[ $local_ok -eq 1 && $icloud_ok -eq 1 ]]; then
        echo ""
        echo "  ✅ SAFE: no real data was touched during the screenshot run"
        return 0
    fi

    # Something wrote to real data — restore from backup
    echo ""
    echo "  🚨🚨🚨 REAL DATA WAS MODIFIED DURING THE SCREENSHOT RUN 🚨🚨🚨"
    echo "  Restoring from pre-run backup at $BACKUP_DIR"

    # Kill the app first so it doesn't re-write while we restore
    killall MortalLoom 2>/dev/null || true
    sleep 1

    if [[ $local_ok -eq 0 && -f "$BACKUP_DIR/local.json" ]]; then
        cp "$BACKUP_DIR/local.json" "$LOCAL_DATA"
        echo "  ♻️  local  restored from backup"
    fi
    if [[ $icloud_ok -eq 0 && -f "$BACKUP_DIR/icloud.json" ]]; then
        cp "$BACKUP_DIR/icloud.json" "$ICLOUD_DATA"
        echo "  ♻️  icloud restored from backup"
    fi

    # Re-verify the restore
    local restored_ok=1
    if [[ -n "$PRE_LOCAL_MD5" && -f "$LOCAL_DATA" ]]; then
        [[ "$(md5 -q "$LOCAL_DATA")" == "$PRE_LOCAL_MD5" ]] || restored_ok=0
    fi
    if [[ -n "$PRE_ICLOUD_MD5" && -f "$ICLOUD_DATA" ]]; then
        [[ "$(md5 -q "$ICLOUD_DATA")" == "$PRE_ICLOUD_MD5" ]] || restored_ok=0
    fi

    if [[ $restored_ok -eq 1 ]]; then
        echo "  ✅ restore verified — real data is back to pre-run state"
        echo ""
        echo "  ACTION REQUIRED: The sampleDataMode guard regressed. Do NOT"
        echo "  run this script again until DataStore.swift is fixed."
        return 1
    else
        echo "  ❌ RESTORE FAILED — checksums still mismatch after restore"
        echo "  Manual recovery needed. Backup is at $BACKUP_DIR"
        return 2
    fi
}

# Run the integrity check on any exit path so even a crash/Ctrl-C triggers it
cleanup() {
    local rc=$?
    killall MortalLoom 2>/dev/null || true
    if [[ -n "${CAFFEINATE_PID:-}" ]]; then
        kill "$CAFFEINATE_PID" 2>/dev/null || true
    fi
    if [[ $YOLO -eq 0 && -n "$PRE_LOCAL_MD5$PRE_ICLOUD_MD5" ]]; then
        verify_and_restore
    fi
    exit $rc
}
trap cleanup EXIT INT TERM

# Pages to capture: "page_name|output_filename|extra_args"
# extra_args lets us pass additional launch flags (e.g. -habits-tab nicotine)
PAGES=(
    "overview|01_overview|"
    "goals|02_goals|"
    "habits|03_habits_alcohol|-habits-tab alcohol"
    "habits|04_habits_nicotine|-habits-tab nicotine"
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

# Safety preflight: verify source has the sampleDataMode guard
if [[ $YOLO -eq 0 ]]; then
    echo "🛡  Running safety preflight…"
    verify_source_safety
    backup_real_data
    echo ""
fi

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

# Quit (cleanup trap will also run killall + integrity check)
killall MortalLoom 2>/dev/null || true
kill "$CAFFEINATE_PID" 2>/dev/null || true
CAFFEINATE_PID=""
sleep 1

COUNT=$(ls "$OUT_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "=========================================="
echo "  macOS Screenshot Capture Complete"
echo "=========================================="
echo "  en/macos: $COUNT screenshots"

echo ""
echo "Done! Upload to App Store Connect under the macOS platform."
# Integrity check runs via the EXIT trap
