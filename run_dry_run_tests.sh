#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    SDK_PATH="$(xcode-select -p 2>/dev/null || true)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
fi

if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    echo "Could not locate macOS SDK"
    exit 1
fi

OUT_BIN="/tmp/plex_dry_run_tests"

swiftc \
    -target arm64-apple-macosx11.0 \
    -sdk "$SDK_PATH" \
    PlexTVEditor/PlexTVEditorViewModel.swift \
    PlexTVEditor/PlexDatabaseManager.swift \
    PlexTVEditor/TMDBClient.swift \
    tests/DryRunLogicTests.swift \
    -o "$OUT_BIN"

"$OUT_BIN"
