#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

assert_file_exists() {
    local path="$1"
    local message="$2"
    if [ ! -f "$path" ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_file_missing() {
    local path="$1"
    local message="$2"
    if [ -f "$path" ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_contains() {
    local path="$1"
    local needle="$2"
    local message="$3"
    if ! grep -Fq "$needle" "$path"; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_command_fails() {
    local message="$1"
    shift
    set +e
    "$@" >/tmp/stage3_negative_test.log 2>&1
    local exit_code=$?
    set -e
    if [ $exit_code -eq 0 ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/plex_stage3_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

NOTES_A="$TMP_DIR/release_notes_a.md"
NOTES_B="$TMP_DIR/release_notes_b.md"
NOTES_C="$TMP_DIR/release_notes_c.md"
REPORT_A="$TMP_DIR/release_prep_a.md"
REPORT_B="$TMP_DIR/release_prep_b.md"

# Test 1: release notes generation creates expected markdown sections.
./generate_release_notes.sh --from-tag v1.0.0 --to-ref HEAD --output "$NOTES_A"
assert_file_exists "$NOTES_A" "Release notes file should be created"
assert_contains "$NOTES_A" "# Release Notes" "Release notes should include title"
assert_contains "$NOTES_A" "## Features" "Release notes should include Features section"

# Test 2: invalid tag input should fail cleanly.
assert_command_fails "Release notes generation should fail for invalid --from-tag" \
    ./generate_release_notes.sh --from-tag invalid_tag_does_not_exist --to-ref HEAD --output "$NOTES_B"

# Test 3: release prep should generate report + notes when notes are enabled.
./run_release_prep.sh --skip-quality-gate --report "$REPORT_A" --notes-output "$NOTES_B" --notes-from-tag v1.0.0 --notes-to-ref HEAD
assert_file_exists "$REPORT_A" "Release prep report should be generated"
assert_file_exists "$NOTES_B" "Release prep should generate notes when enabled"
assert_contains "$REPORT_A" "Release notes generated: yes" "Report should indicate notes generation enabled"
assert_contains "$REPORT_A" "Release notes exit: 0" "Report should indicate notes generation succeeded"

# Test 4: release prep should skip notes when requested.
./run_release_prep.sh --skip-quality-gate --skip-release-notes --report "$REPORT_B" --notes-output "$NOTES_C"
assert_file_exists "$REPORT_B" "Release prep report should be generated when notes are skipped"
assert_contains "$REPORT_B" "Release notes generated: no" "Report should indicate notes generation skipped"
assert_contains "$REPORT_B" "(release notes generation skipped)" "Report should include skipped notes output"

# Test 5: notes output should not be created when notes are skipped.
assert_file_missing "$NOTES_C" "Notes output file should not be created when --skip-release-notes is used"

echo "PASS: Stage 3 workflow tests"
