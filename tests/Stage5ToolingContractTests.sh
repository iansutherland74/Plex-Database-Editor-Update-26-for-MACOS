#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

assert_contains_text() {
    local text="$1"
    local needle="$2"
    local message="$3"
    if ! printf '%s' "$text" | grep -Fq -- "$needle"; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_not_contains_text() {
    local text="$1"
    local needle="$2"
    local message="$3"
    if printf '%s' "$text" | grep -Fq -- "$needle"; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_file_contains() {
    local path="$1"
    local needle="$2"
    local message="$3"
    if ! grep -Fq -- "$needle" "$path"; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_command_fails() {
    local message="$1"
    shift
    set +e
    "$@" >/tmp/stage5_negative_test.log 2>&1
    local exit_code=$?
    set -e
    if [ $exit_code -eq 0 ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/plex_stage5_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

NOTES_PATH="$TMP_DIR/notes_contract.md"
REPORT_PATH="$TMP_DIR/report_contract.md"
QUIET_REPORT_PATH="$TMP_DIR/report_quiet_contract.md"

# Test 1: quality gate help must expose Stage 5 skip and quiet switches.
QUALITY_HELP="$(./run_quality_gate.sh --help)"
assert_contains_text "$QUALITY_HELP" "--skip-stage5" "Quality gate help should expose --skip-stage5"
assert_contains_text "$QUALITY_HELP" "--quiet, -q" "Quality gate help should expose --quiet"

# Test 2: release prep and release tag help should expose quiet mode.
RELEASE_PREP_HELP="$(./run_release_prep.sh --help)"
assert_contains_text "$RELEASE_PREP_HELP" "--quiet, -q" "Release prep help should expose --quiet"
RELEASE_TAG_HELP="$(./create_release_tag.sh --help)"
assert_contains_text "$RELEASE_TAG_HELP" "--quiet, -q" "Release tag help should expose --quiet"

# Test 3: stage wrapper help should expose quiet mode contract.
STAGE3_HELP="$(./run_stage3_tests.sh --help)"
assert_contains_text "$STAGE3_HELP" "--quiet, -q" "Stage 3 help should expose --quiet"
STAGE11_HELP="$(./run_stage11_tests.sh --help)"
assert_contains_text "$STAGE11_HELP" "--quiet, -q" "Stage 11 help should expose --quiet"

# Test 4: make help should include stage5 test target.
MAKE_HELP="$(make help)"
assert_contains_text "$MAKE_HELP" "make stage5-tests" "Make help should include stage5 target"

# Test 5: release-tag make target should fail without VERSION and show usage.
assert_command_fails "make release-tag-dry-run should require VERSION" make release-tag-dry-run
assert_file_contains /tmp/stage5_negative_test.log "Usage: make release-tag-dry-run VERSION=vX.Y.Z" "Missing VERSION should print usage message"

# Test 6: release notes generator should honor custom title contract.
./generate_release_notes.sh --from-tag v1.0.0 --to-ref HEAD --title "Contract Title" --output "$NOTES_PATH"
assert_file_contains "$NOTES_PATH" "# Contract Title" "Release notes should use custom title"

# Test 7: release prep skip modes should report skipped status contract.
./run_release_prep.sh --skip-quality-gate --skip-release-notes --report "$REPORT_PATH"
assert_file_contains "$REPORT_PATH" "Quality gate executed: no" "Release prep report should indicate skipped quality gate"
assert_file_contains "$REPORT_PATH" "Release notes generated: no" "Release prep report should indicate skipped release notes"

# Test 8: quality gate quiet mode should hide stage wrapper chatter but retain pass summary.
QUIET_GATE_OUTPUT="$({
    ./run_quality_gate.sh \
        --skip-build \
        --skip-dry-run \
        --skip-stage2 \
        --skip-stage4 \
        --skip-stage5 \
        --skip-stage6 \
        --skip-stage7 \
        --skip-stage8 \
        --skip-stage9 \
        --skip-stage10 \
        --skip-stage11 \
        --skip-shell-lint \
        --skip-smoke-help \
        --quiet
} 2>&1)"
assert_contains_text "$QUIET_GATE_OUTPUT" "PASS: Stage 3 workflow tests" "Quiet quality gate should still report stage pass summary"
assert_not_contains_text "$QUIET_GATE_OUTPUT" "[stage3] Running Stage 3 workflow tests..." "Quiet quality gate should suppress stage runner banner output"

# Test 9: release prep and release tag quiet mode should suppress progress banners.
QUIET_PREP_OUTPUT="$(./run_release_prep.sh --skip-quality-gate --skip-release-notes --quiet --report "$QUIET_REPORT_PATH" 2>&1)"
assert_contains_text "$QUIET_PREP_OUTPUT" "Wrote release prep report: $QUIET_REPORT_PATH" "Quiet release prep should still print report path"
assert_not_contains_text "$QUIET_PREP_OUTPUT" "[release-prep] Starting release prep workflow" "Quiet release prep should suppress banner output"

QUIET_TAG_VERSION="v9.9.9-stage5quiet$$"
QUIET_TAG_CLONE="$TMP_DIR/quiet_tag_clone"
git clone --no-local "$PROJECT_DIR" "$QUIET_TAG_CLONE" >/dev/null 2>&1
QUIET_TAG_OUTPUT="$(cd "$QUIET_TAG_CLONE" && ./create_release_tag.sh --version "$QUIET_TAG_VERSION" --skip-prep --quiet --to-ref HEAD 2>&1)"
assert_contains_text "$QUIET_TAG_OUTPUT" "Dry-run complete. Tag not created." "Quiet release tag dry-run should still print dry-run summary"
assert_not_contains_text "$QUIET_TAG_OUTPUT" "[release-tag] Starting release tag workflow" "Quiet release tag should suppress banner output"

echo "PASS: Stage 5 tooling contract tests"
