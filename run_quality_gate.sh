#!/bin/bash
set -u -o pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

RUN_BUILD=1
RUN_DRY_RUN=1
RUN_STAGE2=1
RUN_STAGE3=1
RUN_STAGE4=1
RUN_STAGE5=1
RUN_STAGE6=1
RUN_STAGE7=1
RUN_STAGE8=1
RUN_STAGE9=1
RUN_STAGE10=1
RUN_STAGE11=1
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
        --skip-stage3)
            RUN_STAGE3=0
            shift
            ;;
        --skip-stage4)
            RUN_STAGE4=0
            shift
            ;;
        --skip-stage5)
            RUN_STAGE5=0
            shift
            ;;
        --skip-stage6)
            RUN_STAGE6=0
            shift
            ;;
        --skip-stage7)
            RUN_STAGE7=0
            shift
            ;;
        --skip-stage8)
            RUN_STAGE8=0
            shift
            ;;
        --skip-stage9)
            RUN_STAGE9=0
            shift
            ;;
        --skip-stage10)
            RUN_STAGE10=0
            shift
            ;;
        --skip-stage11)
            RUN_STAGE11=0
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
  - Run Stage 3 workflow tests (`./run_stage3_tests.sh`)
  - Run Stage 4 release-tag tests (`./run_stage4_tests.sh`)
  - Run Stage 5 tooling contract tests (`./run_stage5_tests.sh`)
  - Run Stage 6 release automation regression tests (`./run_stage6_tests.sh`)
  - Run Stage 7 CI/release workflow contract tests (`./run_stage7_tests.sh`)
  - Run Stage 8 workflow input and versioning edge tests (`./run_stage8_tests.sh`)
    - Run Stage 9 release report and notes schema tests (`./run_stage9_tests.sh`)
    - Run Stage 10 live smoke safety contract tests (`./run_stage10_tests.sh`)
    - Run Stage 11 release tag provenance contract tests (`./run_stage11_tests.sh`)
  - Lint shell scripts with `bash -n`
  - Validate live smoke script help output

Options:
  --skip-build         Skip app build
  --skip-dry-run       Skip dry-run tests
  --skip-stage2        Skip Stage 2 tests
  --skip-stage3        Skip Stage 3 workflow tests
  --skip-stage4        Skip Stage 4 release-tag tests
  --skip-stage5        Skip Stage 5 tooling contract tests
  --skip-stage6        Skip Stage 6 release-automation regression tests
  --skip-stage7        Skip Stage 7 CI/release workflow contract tests
  --skip-stage8        Skip Stage 8 workflow input and versioning edge tests
    --skip-stage9        Skip Stage 9 release report and notes schema tests
    --skip-stage10       Skip Stage 10 live smoke safety contract tests
    --skip-stage11       Skip Stage 11 release tag provenance contract tests
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

if [ "$RUN_STAGE3" -eq 1 ]; then
    run_step "Stage 3 workflow tests" ./run_stage3_tests.sh
fi

if [ "$RUN_STAGE4" -eq 1 ]; then
    run_step "Stage 4 release-tag tests" ./run_stage4_tests.sh
fi

if [ "$RUN_STAGE5" -eq 1 ]; then
    run_step "Stage 5 tooling contract tests" ./run_stage5_tests.sh
fi

if [ "$RUN_STAGE6" -eq 1 ]; then
    run_step "Stage 6 release automation regression tests" ./run_stage6_tests.sh
fi

if [ "$RUN_STAGE7" -eq 1 ]; then
    run_step "Stage 7 CI/release workflow contract tests" ./run_stage7_tests.sh
fi

if [ "$RUN_STAGE8" -eq 1 ]; then
    run_step "Stage 8 workflow input and versioning edge tests" ./run_stage8_tests.sh
fi

if [ "$RUN_STAGE9" -eq 1 ]; then
    run_step "Stage 9 release report and notes schema tests" ./run_stage9_tests.sh
fi

if [ "$RUN_STAGE10" -eq 1 ]; then
    run_step "Stage 10 live smoke safety contract tests" ./run_stage10_tests.sh
fi

if [ "$RUN_STAGE11" -eq 1 ]; then
    run_step "Stage 11 release tag provenance contract tests" ./run_stage11_tests.sh
fi

if [ "$RUN_SHELL_LINT" -eq 1 ]; then
    run_step "Shell lint run_dry_run_tests.sh" bash -n ./run_dry_run_tests.sh
    run_step "Shell lint run_stage2_tests.sh" bash -n ./run_stage2_tests.sh
    run_step "Shell lint run_stage3_tests.sh" bash -n ./run_stage3_tests.sh
    run_step "Shell lint run_stage4_tests.sh" bash -n ./run_stage4_tests.sh
    run_step "Shell lint run_stage5_tests.sh" bash -n ./run_stage5_tests.sh
    run_step "Shell lint run_stage6_tests.sh" bash -n ./run_stage6_tests.sh
    run_step "Shell lint run_stage7_tests.sh" bash -n ./run_stage7_tests.sh
    run_step "Shell lint run_stage8_tests.sh" bash -n ./run_stage8_tests.sh
    run_step "Shell lint run_stage9_tests.sh" bash -n ./run_stage9_tests.sh
    run_step "Shell lint run_stage10_tests.sh" bash -n ./run_stage10_tests.sh
    run_step "Shell lint run_stage11_tests.sh" bash -n ./run_stage11_tests.sh
    run_step "Shell lint run_live_plex_smoke.sh" bash -n ./run_live_plex_smoke.sh
    run_step "Shell lint run_release_prep.sh" bash -n ./run_release_prep.sh
    run_step "Shell lint generate_release_notes.sh" bash -n ./generate_release_notes.sh
    run_step "Shell lint create_release_tag.sh" bash -n ./create_release_tag.sh
    run_step "Shell lint run_quality_gate.sh" bash -n ./run_quality_gate.sh
    run_step "Shell lint tests/Stage3WorkflowTests.sh" bash -n ./tests/Stage3WorkflowTests.sh
    run_step "Shell lint tests/Stage4ReleaseTagTests.sh" bash -n ./tests/Stage4ReleaseTagTests.sh
    run_step "Shell lint tests/Stage5ToolingContractTests.sh" bash -n ./tests/Stage5ToolingContractTests.sh
    run_step "Shell lint tests/Stage6ReleaseAutomationRegressionTests.sh" bash -n ./tests/Stage6ReleaseAutomationRegressionTests.sh
    run_step "Shell lint tests/Stage7CIWorkflowContractTests.sh" bash -n ./tests/Stage7CIWorkflowContractTests.sh
    run_step "Shell lint tests/Stage8WorkflowInputAndVersioningTests.sh" bash -n ./tests/Stage8WorkflowInputAndVersioningTests.sh
    run_step "Shell lint tests/Stage9ReleaseReportSchemaTests.sh" bash -n ./tests/Stage9ReleaseReportSchemaTests.sh
    run_step "Shell lint tests/Stage10LiveSmokeSafetyContractTests.sh" bash -n ./tests/Stage10LiveSmokeSafetyContractTests.sh
    run_step "Shell lint tests/Stage11ReleaseTagProvenanceTests.sh" bash -n ./tests/Stage11ReleaseTagProvenanceTests.sh
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
