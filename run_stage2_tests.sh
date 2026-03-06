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

OUT_BIN="/tmp/plex_stage2_tests"

SWIFTC_ARGS=(
    -target arm64-apple-macosx11.0
    -sdk "$SDK_PATH"
    PlexTVEditor/PlexTVEditorViewModel.swift
    PlexTVEditor/PlexDatabaseManager.swift
    PlexTVEditor/TMDBClient.swift
    tests/Stage2ReliabilityTests.swift
    -o "$OUT_BIN"
)

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

    exit $COMPILE_EXIT
done

"$OUT_BIN"
