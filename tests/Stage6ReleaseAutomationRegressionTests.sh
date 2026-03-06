#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

assert_command_fails() {
    local message="$1"
    shift
    set +e
    "$@" >/tmp/stage6_negative_test.log 2>&1
    local exit_code=$?
    set -e
    if [ $exit_code -eq 0 ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/plex_stage6_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLONE_DIR="$TMP_DIR/repo"
git clone --quiet --no-local "$PROJECT_DIR" "$CLONE_DIR"

chmod +x "$CLONE_DIR"/run_release_prep.sh \
         "$CLONE_DIR"/generate_release_notes.sh \
         "$CLONE_DIR"/create_release_tag.sh \
         "$CLONE_DIR"/run_quality_gate.sh \
         "$CLONE_DIR"/run_stage2_tests.sh \
         "$CLONE_DIR"/run_stage3_tests.sh \
         "$CLONE_DIR"/run_stage4_tests.sh \
         "$CLONE_DIR"/run_stage5_tests.sh \
         "$CLONE_DIR"/run_stage6_tests.sh \
         "$CLONE_DIR"/tests/Stage6ReleaseAutomationRegressionTests.sh 2>/dev/null || true

NOTES_PATH="$TMP_DIR/stage6_notes.md"
REPORT_PATH="$TMP_DIR/stage6_report.md"
TAG_VERSION="v9.9.93-stage6"

# Test 1: release prep with skipped quality gate should succeed and generate report.
bash -lc "cd '$CLONE_DIR' && ./run_release_prep.sh --skip-quality-gate --skip-build --report '$REPORT_PATH' --notes-output '$NOTES_PATH' --notes-from-tag v1.0.0 --notes-to-ref HEAD"

# Test 2: generated default artifacts should not dirty git status (ignored by .gitignore).
bash -lc "cd '$CLONE_DIR' && ./run_release_prep.sh --skip-quality-gate --skip-build >/tmp/stage6_release_prep_default.log 2>&1"
STATUS="$(git -C "$CLONE_DIR" status --short)"
if [ -n "$STATUS" ]; then
    echo "FAIL: Default release prep outputs should be git-ignored, got status: $STATUS"
    exit 1
fi

# Test 3: create_release_tag with --apply should create local tag in isolated clone.
bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version $TAG_VERSION --skip-prep --apply --notes-output '$TMP_DIR/stage6_tag_notes.md'"
if ! git -C "$CLONE_DIR" rev-parse --verify "refs/tags/$TAG_VERSION" >/dev/null 2>&1; then
    echo "FAIL: Expected tag $TAG_VERSION to exist after --apply"
    exit 1
fi

# Test 4: creating the same tag again should fail.
assert_command_fails "create_release_tag should fail for existing tag" \
    bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version $TAG_VERSION --skip-prep --apply"

# Test 5: quality gate should succeed in clone.
# If --skip-stage6 is supported, use it to prevent recursive Stage 6 invocation.
QUALITY_GATE_ARGS=(--skip-build --skip-smoke-help)
if bash -lc "cd '$CLONE_DIR' && ./run_quality_gate.sh --help | grep -q -- '--skip-stage6'"; then
    QUALITY_GATE_ARGS+=(--skip-stage6)
fi

bash -lc "cd '$CLONE_DIR' && ./run_quality_gate.sh ${QUALITY_GATE_ARGS[*]} >/tmp/stage6_quality_gate.log 2>&1"

echo "PASS: Stage 6 release automation regression tests"
