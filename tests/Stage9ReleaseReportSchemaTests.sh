#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

assert_file_contains() {
    local path="$1"
    local needle="$2"
    local message="$3"
    if ! grep -Fq -- "$needle" "$path"; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_file_not_contains() {
    local path="$1"
    local needle="$2"
    local message="$3"
    if grep -Fq -- "$needle" "$path"; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_file_exists() {
    local path="$1"
    local message="$2"
    if [ ! -f "$path" ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_command_fails() {
    local message="$1"
    shift
    set +e
    "$@" >/tmp/stage9_negative_test.log 2>&1
    local exit_code=$?
    set -e
    if [ "$exit_code" -eq 0 ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/plex_stage9_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLONE_DIR="$TMP_DIR/repo"
git clone --quiet --no-local "$PROJECT_DIR" "$CLONE_DIR"

chmod +x "$CLONE_DIR"/run_release_prep.sh \
         "$CLONE_DIR"/generate_release_notes.sh \
         "$CLONE_DIR"/run_quality_gate.sh 2>/dev/null || true

REPORT_OK="$TMP_DIR/release_prep_ok.md"
NOTES_OK="$TMP_DIR/release_notes_ok.md"

# Test 1: release prep success path should produce stable schema sections and metadata fields.
bash -lc "cd '$CLONE_DIR' && ./run_release_prep.sh --skip-quality-gate --skip-build --report '$REPORT_OK' --notes-output '$NOTES_OK' --notes-to-ref HEAD --notes-title 'Schema Contract Notes'"
assert_file_exists "$REPORT_OK" "Release prep report should be generated on success"
assert_file_exists "$NOTES_OK" "Release notes should be generated on success"
assert_file_contains "$REPORT_OK" "# Release Prep Report" "Report heading should be present"
assert_file_contains "$REPORT_OK" "Quality gate executed: no" "Report should show skipped quality gate"
assert_file_contains "$REPORT_OK" "Quality gate exit: 0" "Skipped quality gate should keep exit code 0"
assert_file_contains "$REPORT_OK" "Release notes generated: yes" "Report should show release notes generated"
assert_file_contains "$REPORT_OK" "Release notes exit: 0" "Release notes success exit should be 0"
assert_file_contains "$REPORT_OK" "Release notes path: $NOTES_OK" "Report should include resolved release notes path"
assert_file_contains "$REPORT_OK" "## Git Status" "Report should include Git Status section"
assert_file_contains "$REPORT_OK" "## Quality Gate Output" "Report should include Quality Gate section"
assert_file_contains "$REPORT_OK" "## Release Notes Output" "Report should include Release Notes output section"
assert_file_contains "$REPORT_OK" "## Recent Commits" "Report should include Recent Commits section"
assert_file_contains "$NOTES_OK" "# Schema Contract Notes" "Release notes should honor custom title"

# Test 2: explicit skip modes should preserve skip placeholders and omit notes path.
REPORT_SKIPPED="$TMP_DIR/release_prep_skipped.md"
bash -lc "cd '$CLONE_DIR' && ./run_release_prep.sh --skip-quality-gate --skip-release-notes --report '$REPORT_SKIPPED'"
assert_file_contains "$REPORT_SKIPPED" "Release notes generated: no" "Skip-release-notes should be reflected in report"
assert_file_contains "$REPORT_SKIPPED" "(quality gate skipped)" "Quality gate skipped placeholder should be present"
assert_file_contains "$REPORT_SKIPPED" "(release notes generation skipped)" "Release notes skipped placeholder should be present"
assert_file_not_contains "$REPORT_SKIPPED" "Release notes path:" "Skipped release notes should not emit notes path line"

# Test 3: release prep failure should still write report with failing release-notes output details.
REPORT_FAIL="$TMP_DIR/release_prep_fail.md"
assert_command_fails "run_release_prep should fail when release notes input is invalid" \
    bash -lc "cd '$CLONE_DIR' && ./run_release_prep.sh --skip-quality-gate --skip-build --notes-from-tag v0.0.0-nonexistent-stage9 --notes-to-ref HEAD --report '$REPORT_FAIL'"
assert_file_exists "$REPORT_FAIL" "Release prep should still write report on release-notes failure"
assert_file_contains "$REPORT_FAIL" "Release notes exit: 2" "Report should capture release-notes non-zero exit"
assert_file_contains "$REPORT_FAIL" "Invalid --from-tag" "Report should include release-notes failure reason"
assert_file_contains /tmp/stage9_negative_test.log "Release prep failed because release notes generation failed" "Failure path should return clear summary message"

# Test 4: generated notes should preserve expected schema headings.
NOTES_SCHEMA="$TMP_DIR/release_notes_schema.md"
bash -lc "cd '$CLONE_DIR' && ./generate_release_notes.sh --to-ref HEAD --title 'Schema Headings Test' --output '$NOTES_SCHEMA'"
assert_file_contains "$NOTES_SCHEMA" "# Schema Headings Test" "Notes title should be emitted"
assert_file_contains "$NOTES_SCHEMA" "## Features" "Notes should include Features section"
assert_file_contains "$NOTES_SCHEMA" "## Fixes" "Notes should include Fixes section"
assert_file_contains "$NOTES_SCHEMA" "## CI and Tooling" "Notes should include CI and Tooling section"
assert_file_contains "$NOTES_SCHEMA" "## Docs" "Notes should include Docs section"
assert_file_contains "$NOTES_SCHEMA" "## Other Changes" "Notes should include Other Changes section"
assert_file_contains "$NOTES_SCHEMA" "## Contributors" "Notes should include Contributors section"

echo "PASS: Stage 9 release report and notes schema tests"
