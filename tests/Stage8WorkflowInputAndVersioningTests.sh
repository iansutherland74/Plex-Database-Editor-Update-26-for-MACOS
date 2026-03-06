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

assert_command_fails() {
    local message="$1"
    shift
    set +e
    "$@" >/tmp/stage8_negative_test.log 2>&1
    local exit_code=$?
    set -e
    if [ "$exit_code" -eq 0 ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/plex_stage8_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLONE_DIR="$TMP_DIR/repo"
git clone --quiet --no-local "$PROJECT_DIR" "$CLONE_DIR"

chmod +x "$CLONE_DIR"/run_release_prep.sh \
         "$CLONE_DIR"/generate_release_notes.sh \
         "$CLONE_DIR"/create_release_tag.sh 2>/dev/null || true

WORKFLOW_RELEASE_PREP="$CLONE_DIR/.github/workflows/release-prep.yml"

# Test 1: release-prep workflow input contracts should remain stable.
assert_file_contains "$WORKFLOW_RELEASE_PREP" "from_tag:" "release-prep workflow should define from_tag input"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "to_ref:" "release-prep workflow should define to_ref input"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "default: \"HEAD\"" "release-prep workflow to_ref should default to HEAD"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "notes_title:" "release-prep workflow should define notes_title input"
assert_file_contains "$WORKFLOW_RELEASE_PREP" "default: \"Release Notes (CI Draft)\"" "release-prep workflow notes_title should keep CI draft default"
assert_file_contains "$WORKFLOW_RELEASE_PREP" 'cmd+=(--notes-from-tag "$FROM_TAG_INPUT")' "release-prep workflow should only append notes-from-tag when provided"

# Test 2: run_release_prep should reject invalid notes-from-tag (input edge case parity with workflow input).
INVALID_TAG_REPORT="$TMP_DIR/stage8_invalid_tag_report.md"
assert_command_fails "run_release_prep should fail for invalid --notes-from-tag" \
    bash -lc "cd '$CLONE_DIR' && ./run_release_prep.sh --skip-quality-gate --skip-build --notes-from-tag v0.0.0-nonexistent-stage8 --notes-to-ref HEAD --report '$INVALID_TAG_REPORT'"
assert_file_contains "$INVALID_TAG_REPORT" "Invalid --from-tag" "Invalid --notes-from-tag should surface clear error in release report"

# Test 3: create_release_tag should reject invalid version formats.
assert_command_fails "create_release_tag should reject non-v-prefixed semver" \
    bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version 1.2.3 --skip-prep"
assert_command_fails "create_release_tag should reject incomplete semver" \
    bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version v1.2 --skip-prep"
assert_file_contains /tmp/stage8_negative_test.log "Version must look like vMAJOR.MINOR.PATCH" "Invalid version format should return contract message"

# Test 4: prerelease suffix versions should be accepted in dry-run mode and should not create a tag.
VERSION_PRERELEASE="v9.9.94-rc.1"
NOTES_PATH="$TMP_DIR/stage8_prerelease_notes.md"
bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version $VERSION_PRERELEASE --skip-prep --notes-output '$NOTES_PATH'"
assert_file_contains "$NOTES_PATH" "# Release Notes $VERSION_PRERELEASE" "Dry-run prerelease version should generate notes with versioned title"
if git -C "$CLONE_DIR" rev-parse --verify "refs/tags/$VERSION_PRERELEASE" >/dev/null 2>&1; then
    echo "FAIL: Dry-run should not create prerelease tag $VERSION_PRERELEASE"
    exit 1
fi

# Test 5: create_release_tag should reject invalid --to-ref.
assert_command_fails "create_release_tag should fail for invalid --to-ref" \
    bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version v9.9.95-stage8 --to-ref definitely-not-a-ref --skip-prep"
assert_file_contains /tmp/stage8_negative_test.log "Invalid --to-ref" "Invalid to-ref should surface clear error"

# Test 6: workflow command construction should keep notes-to-ref and notes-title forwarding.
assert_file_contains "$WORKFLOW_RELEASE_PREP" '--notes-to-ref "$TO_REF_INPUT"' "Workflow should forward to_ref input to release prep command"
assert_file_contains "$WORKFLOW_RELEASE_PREP" '--notes-title "$NOTES_TITLE_INPUT"' "Workflow should forward notes_title input to release prep command"
assert_file_not_contains "$WORKFLOW_RELEASE_PREP" "--notes-from-tag \"\"" "Workflow should avoid forcing empty notes-from-tag"

echo "PASS: Stage 8 workflow input and versioning edge tests"
