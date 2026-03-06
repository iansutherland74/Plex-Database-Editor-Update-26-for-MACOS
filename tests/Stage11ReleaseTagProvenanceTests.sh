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

TMP_DIR="$(mktemp -d /tmp/plex_stage11_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLONE_DIR="$TMP_DIR/repo"
git clone --quiet --no-local "$PROJECT_DIR" "$CLONE_DIR"

chmod +x "$CLONE_DIR"/create_release_tag.sh \
         "$CLONE_DIR"/generate_release_notes.sh \
         "$CLONE_DIR"/run_release_prep.sh \
         "$CLONE_DIR"/run_quality_gate.sh 2>/dev/null || true

RUN_SUFFIX="$(date +%s)"
VERSION_SKIP_PREP="v9.9.110-stage11a.${RUN_SUFFIX}"
VERSION_WITH_PREP="v9.9.110-stage11b.${RUN_SUFFIX}"
BASE_FROM_TAG="v9.9.109-stage11base.${RUN_SUFFIX}"
NOTES_A="$TMP_DIR/stage11_notes_a.md"
NOTES_B="$TMP_DIR/stage11_notes_b.md"
REPORT_B="$TMP_DIR/stage11_report_b.md"
TAG_MSG_A="$TMP_DIR/tag_message_a.txt"
TAG_MSG_B="$TMP_DIR/tag_message_b.txt"

# Prepare an explicit base tag so --from-tag range is deterministic for message contract checks.
git -C "$CLONE_DIR" tag "$BASE_FROM_TAG"

# Test 1: --apply + --skip-prep should create annotated tag with notes line and no report line.
bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version $VERSION_SKIP_PREP --to-ref HEAD --from-tag $BASE_FROM_TAG --skip-prep --apply --notes-output '$NOTES_A'"
assert_file_exists "$NOTES_A" "Skip-prep apply should generate notes file"

git -C "$CLONE_DIR" tag -l --format='%(contents)' "$VERSION_SKIP_PREP" > "$TAG_MSG_A"
assert_file_contains "$TAG_MSG_A" "Release $VERSION_SKIP_PREP" "Tag message should start with release version"
assert_file_contains "$TAG_MSG_A" "Target ref: HEAD" "Tag message should include target ref"
assert_file_contains "$TAG_MSG_A" "Range: ${BASE_FROM_TAG}..HEAD" "Tag message should include explicit from-tag range"
assert_file_contains "$TAG_MSG_A" "Release notes: $NOTES_A" "Tag message should include notes path"
assert_file_not_contains "$TAG_MSG_A" "Release prep report:" "Skip-prep tag message should not include prep report line"

# For prep-flow provenance checks, stub quality gate in clone to avoid deep recursive stage execution.
cat > "$CLONE_DIR/run_quality_gate.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "Quality gate summary: PASS=1 FAIL=0"
exit 0
EOF
chmod +x "$CLONE_DIR/run_quality_gate.sh"
git -C "$CLONE_DIR" config user.name "Stage11 Test"
git -C "$CLONE_DIR" config user.email "stage11@example.invalid"
git -C "$CLONE_DIR" add run_quality_gate.sh
git -C "$CLONE_DIR" commit -m "Stage11: stub quality gate" >/dev/null

# Test 2: --apply with prep should generate report and include both notes/report paths in annotated tag.
bash -lc "cd '$CLONE_DIR' && ./create_release_tag.sh --version $VERSION_WITH_PREP --to-ref HEAD --from-tag $BASE_FROM_TAG --apply --notes-output '$NOTES_B' --report-output '$REPORT_B'"
assert_file_exists "$NOTES_B" "Prep apply should generate notes file"
assert_file_exists "$REPORT_B" "Prep apply should generate prep report"

git -C "$CLONE_DIR" tag -l --format='%(contents)' "$VERSION_WITH_PREP" > "$TAG_MSG_B"
assert_file_contains "$TAG_MSG_B" "Release $VERSION_WITH_PREP" "Tag message should include second release version"
assert_file_contains "$TAG_MSG_B" "Target ref: HEAD" "Tag message should include target ref for prep flow"
assert_file_contains "$TAG_MSG_B" "Range: ${BASE_FROM_TAG}..HEAD" "Tag message should include range for prep flow"
assert_file_contains "$TAG_MSG_B" "Release notes: $NOTES_B" "Tag message should include notes path for prep flow"
assert_file_contains "$TAG_MSG_B" "Release prep report: $REPORT_B" "Tag message should include prep report path"

# Test 3: prep report should exist and keep skip-release-notes contract used by create_release_tag.
assert_file_contains "$REPORT_B" "# Release Prep Report" "Release prep report should include heading"
assert_file_contains "$REPORT_B" "Release notes generated: no" "Release prep report should indicate release notes were skipped"
assert_file_contains "$REPORT_B" "(release notes generation skipped)" "Release prep report should include skipped release-notes placeholder"

echo "PASS: Stage 11 release tag provenance contract tests"
