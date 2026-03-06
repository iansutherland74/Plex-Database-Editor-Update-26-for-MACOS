#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --quiet|-q)
            QUIET=1
            shift
            ;;
        --help|-h)
            cat <<'HELP'
Usage: ./run_stage2_tests.sh [--quiet]

Options:
  --quiet, -q  Reduce output; print full logs only on failure
  --help       Show this help
HELP
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 2
            ;;
    esac
done

log() {
    if [ "$QUIET" -eq 0 ]; then
        echo "$*"
    fi
}

START_TIME="$(date +%s)"
log "[stage2] Running Stage 2 reliability tests..."

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    SDK_PATH="$(xcode-select -p 2>/dev/null || true)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
fi

if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    echo "[stage2] FAIL: Could not locate macOS SDK"
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

    if [ "$QUIET" -eq 0 ] && [ -n "$COMPILE_OUTPUT" ]; then
        echo "$COMPILE_OUTPUT"
    fi

    if [ $COMPILE_EXIT -eq 0 ]; then
        break
    fi

    if echo "$COMPILE_OUTPUT" | grep -q "was modified during the build" && [ $COMPILE_ATTEMPT -lt $MAX_COMPILE_ATTEMPTS ]; then
        log "[stage2] WARN: Detected transient source write during compile; retrying..."
        COMPILE_ATTEMPT=$((COMPILE_ATTEMPT + 1))
        sleep 1
        continue
    fi

    if [ -n "$COMPILE_OUTPUT" ]; then
        echo "$COMPILE_OUTPUT"
    fi
    echo "[stage2] FAIL: Compile failed"
    exit $COMPILE_EXIT
done

run_binary() {
    if [ "$QUIET" -eq 1 ]; then
        local binary_log
        binary_log="$(mktemp /tmp/stage2_tests.XXXXXX)"
        if "$OUT_BIN" >"$binary_log" 2>&1; then
            rm -f "$binary_log"
            return 0
        fi
        cat "$binary_log"
        rm -f "$binary_log"
        return 1
    fi

    "$OUT_BIN"
}

if run_binary; then
    END_TIME="$(date +%s)"
    log "[stage2] Completed in $((END_TIME - START_TIME))s"
else
    echo "[stage2] FAIL: Stage 2 reliability binary exited non-zero"
    exit 1
fi
