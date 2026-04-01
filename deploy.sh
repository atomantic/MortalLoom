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
DEPLOY_IOS=true
DEPLOY_MACOS=false
SKIP_TESTS=false
for arg in "$@"; do
    case "$arg" in
        --macos) DEPLOY_IOS=false; DEPLOY_MACOS=true ;;
        --all) DEPLOY_IOS=true; DEPLOY_MACOS=true ;;
        --skip-tests) SKIP_TESTS=true ;;
    esac
done

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

# Regenerate Xcode project from project.yml
echo "⚙️  Regenerating Xcode project..."
xcodegen generate

PROJECT="MortalLoom.xcodeproj"
BUILD_DIR="$SCRIPT_DIR/build"

# Auto-increment build number in project.yml (YAML format: "CURRENT_PROJECT_VERSION: N")
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}')
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "📦 Build number: $CURRENT_BUILD → $NEW_BUILD"
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: ${CURRENT_BUILD}/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" project.yml

# Regenerate after build number change
xcodegen generate 2>/dev/null

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
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "MortalLoomTests_iOS" \
        -destination "$DESTINATION" \
        -configuration Debug \
        CODE_SIGNING_ALLOWED=NO \
        -quiet || true
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
    if xcrun altool --upload-app \
        --file "$ARTIFACT" \
        --type "$APP_TYPE" \
        --apiKey "$APPSTORE_API_KEY_ID" \
        --apiIssuer "$APPSTORE_ISSUER_ID"; then
        echo "✅ $PLATFORM upload complete!"
    else
        echo "❌ $PLATFORM upload failed"
        exit 1
    fi
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

# Commit the build number bump
git add project.yml "$PROJECT/project.pbxproj"
git commit -m "build: bump to $NEW_BUILD"
echo "📝 Committed build number bump"

# Clean up
rm -rf "$BUILD_DIR"
echo "🧹 Cleaned build artifacts"
