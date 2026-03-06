#!/bin/bash
set -u -o pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

RUN_BUILD=1
RUN_DRY_RUN=1
RUN_STAGE2=1
RUN_SHELL_LINT=1
RUN_SMOKE_HELP=1
RUN_LIVE_SMOKE=0
LIVE_INCLUDE_WRITE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build)
            RUN_BUILD=0
            shift
            ;;
        --skip-dry-run)
            RUN_DRY_RUN=0
            shift
            ;;
        --skip-stage2)
            RUN_STAGE2=0
            shift
            ;;
        --skip-shell-lint)
            RUN_SHELL_LINT=0
            shift
            ;;
        --skip-smoke-help)
            RUN_SMOKE_HELP=0
            shift
            ;;
        --include-live-smoke)
            RUN_LIVE_SMOKE=1
            shift
            ;;
        --include-live-write)
            RUN_LIVE_SMOKE=1
            LIVE_INCLUDE_WRITE=1
            shift
            ;;
        --help|-h)
            cat <<'HELP'
Usage: ./run_quality_gate.sh [options]

Default behavior:
  - Build app (`./build_swift_app.sh`)
  - Run dry-run tests (`./run_dry_run_tests.sh`)
  - Run Stage 2 reliability tests (`./run_stage2_tests.sh`)
  - Lint shell scripts with `bash -n`
  - Validate live smoke script help output

Options:
  --skip-build         Skip app build
  --skip-dry-run       Skip dry-run tests
  --skip-stage2        Skip Stage 2 tests
  --skip-shell-lint    Skip shell syntax checks
  --skip-smoke-help    Skip live smoke help sanity check
  --include-live-smoke Run live Plex smoke checks (read-only)
  --include-live-write Run live Plex smoke checks including non-destructive write queue checks
  --help               Show this help

Examples:
  ./run_quality_gate.sh
  ./run_quality_gate.sh --skip-build
  ./run_quality_gate.sh --include-live-smoke
  ./run_quality_gate.sh --include-live-write
HELP
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 2
            ;;
    esac
done

PASS_COUNT=0
FAIL_COUNT=0

run_step() {
    local label="$1"
    shift

    echo "==> $label"
    if "$@"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "PASS: $label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "FAIL: $label"
    fi
    echo ""
}

if [ "$RUN_BUILD" -eq 1 ]; then
    run_step "Build app" ./build_swift_app.sh
fi

if [ "$RUN_DRY_RUN" -eq 1 ]; then
    run_step "Dry-run tests" ./run_dry_run_tests.sh
fi

if [ "$RUN_STAGE2" -eq 1 ]; then
    run_step "Stage 2 reliability tests" ./run_stage2_tests.sh
fi

if [ "$RUN_SHELL_LINT" -eq 1 ]; then
    run_step "Shell lint run_dry_run_tests.sh" bash -n ./run_dry_run_tests.sh
    run_step "Shell lint run_stage2_tests.sh" bash -n ./run_stage2_tests.sh
    run_step "Shell lint run_live_plex_smoke.sh" bash -n ./run_live_plex_smoke.sh
    run_step "Shell lint run_quality_gate.sh" bash -n ./run_quality_gate.sh
fi

if [ "$RUN_SMOKE_HELP" -eq 1 ]; then
    run_step "Live smoke script help" ./run_live_plex_smoke.sh --help
fi

if [ "$RUN_LIVE_SMOKE" -eq 1 ]; then
    if [ "$LIVE_INCLUDE_WRITE" -eq 1 ]; then
        run_step "Live Plex smoke (read + non-destructive write)" ./run_live_plex_smoke.sh --include-write
    else
        run_step "Live Plex smoke (read-only)" ./run_live_plex_smoke.sh
    fi
fi

echo "Quality gate summary: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0
