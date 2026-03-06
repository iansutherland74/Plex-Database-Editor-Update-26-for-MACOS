#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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
    "$@" >/tmp/stage4_negative_test.log 2>&1
    local exit_code=$?
    set -e
    if [ $exit_code -eq 0 ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/plex_stage4_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLONE_DIR="$TMP_DIR/repo"
git clone --quiet --no-local "$PROJECT_DIR" "$CLONE_DIR"

# Ensure scripts are executable in the clone.
chmod +x "$CLONE_DIR"/create_release_tag.sh "$CLONE_DIR"/generate_release_notes.sh "$CLONE_DIR"/run_release_prep.sh "$CLONE_DIR"/run_quality_gate.sh || true

VERSION_A="v9.9.91-stage4"
VERSION_B="v9.9.92-stage4"
NOTES_A="$TMP_DIR/notes_a.md"
NOTES_B="$TMP_DIR/notes_b.md"

# Test 1: --version is required.
assert_command_fails "create_release_tag should fail when --version is missing" \
    bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh"

# Test 2: invalid version format should fail.
assert_command_fails "create_release_tag should reject invalid version format" \
    bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version not-a-tag"

# Test 3: --push requires --apply.
assert_command_fails "create_release_tag should reject --push without --apply" \
    bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version $VERSION_A --push"

# Test 4: dry-run prepares notes but does not create tag.
bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version $VERSION_A --skip-prep --notes-output '$NOTES_A'"
assert_file_exists "$NOTES_A" "Dry-run should generate notes file"
if git -C "$CLONE_DIR" rev-parse --verify "refs/tags/$VERSION_A" >/dev/null 2>&1; then
    echo "FAIL: Dry-run should not create git tag $VERSION_A"
    exit 1
fi

# Test 5: --apply creates local annotated tag.
bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version $VERSION_B --skip-prep --apply --notes-output '$NOTES_B'"
assert_file_exists "$NOTES_B" "Apply mode should generate notes file"
if ! git -C "$CLONE_DIR" rev-parse --verify "refs/tags/$VERSION_B" >/dev/null 2>&1; then
    echo "FAIL: --apply should create git tag $VERSION_B"
    exit 1
fi

echo "PASS: Stage 4 release-tag tests"
