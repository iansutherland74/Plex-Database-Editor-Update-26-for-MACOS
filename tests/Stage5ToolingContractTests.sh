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

# Test 1: quality gate help must expose Stage 5 skip switch contract.
QUALITY_HELP="$(./run_quality_gate.sh --help)"
assert_contains_text "$QUALITY_HELP" "--skip-stage5" "Quality gate help should expose --skip-stage5"

# Test 2: make help should include stage5 test target.
MAKE_HELP="$(make help)"
assert_contains_text "$MAKE_HELP" "make stage5-tests" "Make help should include stage5 target"

# Test 3: release-tag make target should fail without VERSION and show usage.
assert_command_fails "make release-tag-dry-run should require VERSION" make release-tag-dry-run
assert_file_contains /tmp/stage5_negative_test.log "Usage: make release-tag-dry-run VERSION=vX.Y.Z" "Missing VERSION should print usage message"

# Test 4: release notes generator should honor custom title contract.
./generate_release_notes.sh --from-tag v1.0.0 --to-ref HEAD --title "Contract Title" --output "$NOTES_PATH"
assert_file_contains "$NOTES_PATH" "# Contract Title" "Release notes should use custom title"

# Test 5: release prep skip modes should report skipped status contract.
./run_release_prep.sh --skip-quality-gate --skip-release-notes --report "$REPORT_PATH"
assert_file_contains "$REPORT_PATH" "Quality gate executed: no" "Release prep report should indicate skipped quality gate"
assert_file_contains "$REPORT_PATH" "Release notes generated: no" "Release prep report should indicate skipped release notes"

echo "PASS: Stage 5 tooling contract tests"
