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

assert_file_exists() {
    local path="$1"
    local message="$2"
    if [ ! -f "$path" ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/plex_stage7_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLONE_DIR="$TMP_DIR/repo"
git clone --quiet --no-local "$PROJECT_DIR" "$CLONE_DIR"

chmod +x "$CLONE_DIR"/run_release_prep.sh \
         "$CLONE_DIR"/generate_release_notes.sh 2>/dev/null || true

WORKFLOW_RELEASE_PREP="$CLONE_DIR/.github/workflows/release-prep.yml"
WORKFLOW_BUILD="$CLONE_DIR/.github/workflows/macos-swift-build.yml"

# Test 1: release-prep workflow contract should keep expected trigger, checkout depth, and artifact names.
assert_file_contains "$WORKFLOW_RELEASE_PREP" "name: Release Prep" "Release-prep workflow name contract is missing"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "workflow_dispatch:" "Release-prep workflow should be manually dispatchable"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "fetch-depth: 0" "Release-prep workflow should fetch full history"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "name: release-prep-report" "Release-prep report artifact name contract is missing"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "name: release-notes-draft" "Release notes artifact name contract is missing"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "--report /tmp/release_prep_report.md" "Release-prep workflow should write report to /tmp/release_prep_report.md"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "--notes-output /tmp/release_notes.md" "Release-prep workflow should write notes to /tmp/release_notes.md"

# Test 2: CI build workflow should run the quality gate entrypoint.
assert_file_contains "$WORKFLOW_BUILD" "./run_quality_gate.sh --skip-build" "Build workflow should run quality gate with --skip-build"

# Test 3: local release-prep simulation should produce the same report/notes artifacts expected by CI.
REPORT_PATH="$TMP_DIR/ci_release_prep_report.md"
NOTES_PATH="$TMP_DIR/ci_release_notes.md"
bash -lc "cd '$CLONE_DIR' && ./run_release_prep.sh --skip-quality-gate --skip-build --report '$REPORT_PATH' --notes-output '$NOTES_PATH' --notes-to-ref HEAD --notes-title 'Release Notes (CI Draft)' >/tmp/stage7_release_prep.log 2>&1"

assert_file_exists "$REPORT_PATH" "Release-prep report artifact should be generated"
assert_file_exists "$NOTES_PATH" "Release notes artifact should be generated"
assert_file_contains "$REPORT_PATH" "# Release Prep Report" "Report artifact should include release prep heading"
assert_file_contains "$REPORT_PATH" "Release notes path: $NOTES_PATH" "Report should reference generated notes artifact path"
assert_file_contains "$NOTES_PATH" "# Release Notes (CI Draft)" "Notes artifact should use CI draft title"

echo "PASS: Stage 7 CI/release workflow contract tests"
