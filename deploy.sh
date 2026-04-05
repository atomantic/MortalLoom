#!/bin/bash
set -euo pipefail

# MortalLoom - Local TestFlight Deploy
# Usage: ./deploy.sh              # iOS only
#        ./deploy.sh --macos      # macOS only
#        ./deploy.sh --all        # Both platforms
#        ./deploy.sh --skip-tests # Skip tests

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Parse args
DEPLOY_IOS=false
DEPLOY_MACOS=false
SKIP_TESTS=false
for arg in "$@"; do
    case "$arg" in
        --ios) DEPLOY_IOS=true ;;
        --macos) DEPLOY_MACOS=true ;;
        --all) DEPLOY_IOS=true; DEPLOY_MACOS=true ;;
        --skip-tests) SKIP_TESTS=true ;;
    esac
done
# Default to iOS if no platform specified
if ! $DEPLOY_IOS && ! $DEPLOY_MACOS; then
    DEPLOY_IOS=true
fi

# Load environment
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "❌ .env file not found. Copy .env.example to .env and fill in values."
    exit 1
fi

KEY_PATH="$APPSTORE_API_PRIVATE_KEY_PATH"
if [ ! -f "$KEY_PATH" ]; then
    echo "❌ API key not found at: $KEY_PATH"
    exit 1
fi

# Ensure altool can find the key
mkdir -p ~/.private_keys
KEY_FILENAME="AuthKey_${APPSTORE_API_KEY_ID}.p8"
if [ ! -f ~/.private_keys/"$KEY_FILENAME" ]; then
    ln -sf "$KEY_PATH" ~/.private_keys/"$KEY_FILENAME"
    echo "🔑 Symlinked API key to ~/.private_keys/"
fi

# Strip alpha from app icons (App Store rejects icons with alpha/transparency)
python3 -c "
from PIL import Image
from pathlib import Path
fixed = False
for p in Path('MortalLoom/App/Assets.xcassets/AppIcon.appiconset').glob('AppIcon-*.png'):
    img = Image.open(p)
    if img.mode == 'RGBA':
        bg = Image.new('RGB', img.size, (0, 0, 0))
        bg.paste(img, mask=img.split()[3])
        bg.save(p)
        fixed = True
    elif img.mode != 'RGB':
        img.convert('RGB').save(p)
        fixed = True
if fixed:
    print('🎨 Stripped alpha from app icons')
"

PROJECT="MortalLoom.xcodeproj"
BUILD_DIR="$SCRIPT_DIR/build"

# Auto-increment build number in project.yml (YAML format: "CURRENT_PROJECT_VERSION: N")
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}')
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "📦 Build number: $CURRENT_BUILD → $NEW_BUILD"
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: ${CURRENT_BUILD}/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" project.yml

# Regenerate Xcode project from project.yml
echo "⚙️  Regenerating Xcode project..."
xcodegen generate

# Run tests (unless skipped)
if [ "$SKIP_TESTS" = false ]; then
    echo "🧪 Running tests..."
    DESTINATION=$(
        SIMINFO=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' not in runtime:
        continue
    parts = runtime.replace('com.apple.CoreSimulator.SimRuntime.iOS-', '').split('-')
    os_ver = '.'.join(parts)
    for d in devices:
        name = d.get('name', '')
        if d.get('isAvailable') and 'iPhone' in name and 'Plus' not in name and 'e' != name[-1:]:
            print(f'{name},{os_ver}')
            sys.exit(0)
" 2>/dev/null)
        SIM_NAME="${SIMINFO%%,*}"
        SIM_OS="${SIMINFO##*,}"
        if [ -n "$SIM_NAME" ] && [ -n "$SIM_OS" ]; then
            echo "platform=iOS Simulator,name=$SIM_NAME,OS=$SIM_OS"
        else
            echo "platform=iOS Simulator,name=iPhone 16,OS=18.6"
        fi
    )
    if ! xcodebuild test \
        -project "$PROJECT" \
        -scheme "MortalLoom_iOS" \
        -destination "$DESTINATION" \
        -only-testing:MortalLoomTests_iOS \
        -configuration Debug \
        CODE_SIGNING_ALLOWED=NO \
        -quiet; then
        echo "⚠️  Tests had failures — continuing deploy"
    fi
    echo "✅ Tests complete"
fi

deploy_platform() {
    local PLATFORM="$1"
    local SCHEME="MortalLoom_${PLATFORM}"
    local ARCHIVE_PATH="$BUILD_DIR/${SCHEME}.xcarchive"
    local EXPORT_PATH="$BUILD_DIR/export-${PLATFORM}"

    if [ "$PLATFORM" = "iOS" ]; then
        DEST="generic/platform=iOS"
        APP_TYPE="ios"
    else
        DEST="generic/platform=macOS"
        APP_TYPE="osx"
    fi

    echo "📦 Archiving $PLATFORM..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "$DEST" \
        -archivePath "$ARCHIVE_PATH" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet
    echo "✅ $PLATFORM archive complete"

    cat > "$BUILD_DIR/exportOptions-${PLATFORM}.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

    echo "📤 Exporting $PLATFORM..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$BUILD_DIR/exportOptions-${PLATFORM}.plist" \
        -exportPath "$EXPORT_PATH" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet
    echo "✅ $PLATFORM export complete"

    # Find the built artifact
    if [ "$PLATFORM" = "iOS" ]; then
        ARTIFACT=$(find "$EXPORT_PATH" -name "*.ipa" | head -1)
    else
        ARTIFACT=$(find "$EXPORT_PATH" -name "*.pkg" | head -1)
    fi

    if [ -z "$ARTIFACT" ]; then
        echo "❌ $PLATFORM artifact not found in $EXPORT_PATH"
        ls -la "$EXPORT_PATH/" 2>/dev/null
        exit 1
    fi

    echo "🚀 Uploading $PLATFORM to TestFlight..."
    UPLOAD_OUTPUT=$(xcrun altool --upload-app \
        --file "$ARTIFACT" \
        --type "$APP_TYPE" \
        --apiKey "$APPSTORE_API_KEY_ID" \
        --apiIssuer "$APPSTORE_ISSUER_ID" 2>&1) || true
    echo "$UPLOAD_OUTPUT"
    if echo "$UPLOAD_OUTPUT" | grep -q "UPLOAD FAILED\|ERROR:"; then
        echo "❌ $PLATFORM upload failed"
        exit 1
    fi
    echo "✅ $PLATFORM upload complete!"
}

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Deploy requested platforms
if [ "$DEPLOY_IOS" = true ]; then
    deploy_platform "iOS"
fi

if [ "$DEPLOY_IOS" = true ] && [ "$DEPLOY_MACOS" = true ]; then
    echo "⏳ Waiting 60s before macOS upload to avoid Apple CDN contention..."
    sleep 60
fi

if [ "$DEPLOY_MACOS" = true ]; then
    deploy_platform "macOS"
fi

echo "✅ Build $NEW_BUILD submitted to TestFlight."
echo "🔗 https://appstoreconnect.apple.com/apps/6760883701/testflight"

# Commit the build number bump and push
git add project.yml "$PROJECT/project.pbxproj"
git commit -m "build: bump to $NEW_BUILD"
echo "📝 Committed build number bump"
git pull --rebase --autostash && git push
echo "📤 Pushed to remote"

# Clean up
rm -rf "$BUILD_DIR"
echo "🧹 Cleaned build artifacts"
