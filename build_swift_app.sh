#!/bin/bash
set -e

# Plex TV Editor - Native Swift App Builder
# Compiles Swift source into a native macOS app with no runtime dependencies

echo "=========================================="
echo "Plex TV Editor - Swift App Builder"
echo "=========================================="

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Plex TV Editor"
APP_PATH="/Applications/$APP_NAME.app"

echo "[1/4] Checking Swift..."
if ! command -v swift &> /dev/null; then
    echo "✗ Swift not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi
SWIFT_VERSION=$(swift --version | awk '{print $NF}')
echo "✓ Swift $SWIFT_VERSION"

echo ""
echo "[2/4] Building app..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Compile Swift sources into app bundle
cd "$PROJECT_DIR/PlexTVEditor"

# Create app bundle structure
BUNDLE="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
mkdir -p "$BUNDLE/Contents/Frameworks"

# Copy Info.plist
cp Info.plist "$BUNDLE/Contents/Info.plist"

# Compile Swift code
echo "Compiling Swift sources..."
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    SDK_PATH="$(xcode-select -p 2>/dev/null || true)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
fi

if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    echo "✗ Could not locate macOS SDK"
    echo "Make sure Xcode or Command Line Tools are installed:"
    echo "  xcode-select --install"
    exit 1
fi

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
FRAMEWORK_SEARCH_PATH="$DEVELOPER_DIR/../Frameworks"

SWIFTC_ARGS=(
    -parse-as-library
    -target arm64-apple-macosx11.0
    -sdk "$SDK_PATH"
    -framework SwiftUI
    -framework Foundation
    -framework Cocoa
    -O
    PlexTVEditorApp.swift
    ContentView.swift
    PlexTVEditorViewModel.swift
    PlexDatabaseManager.swift
    TMDBClient.swift
    -o "$BUNDLE/Contents/MacOS/$APP_NAME"
)

if [ -d "$FRAMEWORK_SEARCH_PATH" ]; then
    SWIFTC_ARGS+=( -F "$FRAMEWORK_SEARCH_PATH" )
fi

MAX_COMPILE_ATTEMPTS=2
COMPILE_ATTEMPT=1

while [ $COMPILE_ATTEMPT -le $MAX_COMPILE_ATTEMPTS ]; do
    set +e
    COMPILE_OUTPUT=$(swiftc "${SWIFTC_ARGS[@]}" 2>&1)
    COMPILE_EXIT=$?
    set -e

    echo "$COMPILE_OUTPUT"

    if [ $COMPILE_EXIT -eq 0 ]; then
        break
    fi

    if echo "$COMPILE_OUTPUT" | grep -q "was modified during the build" && [ $COMPILE_ATTEMPT -lt $MAX_COMPILE_ATTEMPTS ]; then
        echo "Detected transient source write during compile; retrying..."
        COMPILE_ATTEMPT=$((COMPILE_ATTEMPT + 1))
        sleep 1
        continue
    fi

    echo "✗ Compilation failed"
    echo "Make sure Xcode Command Line Tools are installed:"
    echo "  xcode-select --install"
    exit 1
done

echo "✓ App compiled successfully"

echo ""
echo "[3/4] Installing to /Applications..."

# Remove old version
if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
fi

# Copy app to /Applications
cp -r "$BUNDLE" "$APP_PATH"
chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

echo "✓ Installed to $APP_PATH"

echo ""
echo "[4/4] Registering with LaunchServices..."
dseditgroup -o read -t user _lpadmin >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH" 2>/dev/null || true

xattr -d com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo "✓ App registered"

echo ""
echo "=========================================="
echo "✓ Build Complete!"
echo "=========================================="
echo ""
echo "To launch the app:"
echo "  1. Open /Applications/Plex\\ TV\\ Editor.app"
echo "  2. Or: open /Applications/Plex\\ TV\\ Editor.app"
echo "  3. Or search for 'Plex TV Editor' in Spotlight (Cmd+Space)"
echo ""
echo "Build files in: $BUILD_DIR"
echo "=========================================="
