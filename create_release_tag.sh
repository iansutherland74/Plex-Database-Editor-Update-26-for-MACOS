#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"

elapsed_seconds() {
    local now
    now="$(date +%s)"
    echo $((now - START_TIME))
}

VERSION=""
TO_REF="HEAD"
FROM_TAG=""
NOTES_PATH=""
REPORT_PATH=""
RUN_PREP=1
INCLUDE_LIVE_SMOKE=0
INCLUDE_LIVE_WRITE=0
APPLY=0
PUSH=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            if [ $# -lt 2 ]; then
                echo "Missing value for --version"
                exit 2
            fi
            VERSION="$2"
            shift 2
            ;;
        --to-ref)
            if [ $# -lt 2 ]; then
                echo "Missing value for --to-ref"
                exit 2
            fi
            TO_REF="$2"
            shift 2
            ;;
        --from-tag)
            if [ $# -lt 2 ]; then
                echo "Missing value for --from-tag"
                exit 2
            fi
            FROM_TAG="$2"
            shift 2
            ;;
        --notes-output)
            if [ $# -lt 2 ]; then
                echo "Missing value for --notes-output"
                exit 2
            fi
            NOTES_PATH="$2"
            shift 2
            ;;
        --report-output)
            if [ $# -lt 2 ]; then
                echo "Missing value for --report-output"
                exit 2
            fi
            REPORT_PATH="$2"
            shift 2
            ;;
        --skip-prep)
            RUN_PREP=0
            shift
            ;;
        --include-live-smoke)
            INCLUDE_LIVE_SMOKE=1
            shift
            ;;
        --include-live-write)
            INCLUDE_LIVE_WRITE=1
            shift
            ;;
        --apply)
            APPLY=1
            shift
            ;;
        --push)
            PUSH=1
            shift
            ;;
        --help|-h)
            cat <<'HELP'
Usage: ./create_release_tag.sh --version <tag> [options]

Default behavior:
- Validates repo is clean
- Generates release notes draft
- Runs release prep (non-build path) for evidence
- Dry-run only (does NOT create or push tag unless --apply is used)

Options:
  --version <tag>       Tag name to create (example: v1.0.1)
  --to-ref <ref>        Target ref for notes/tag (default: HEAD)
  --from-tag <tag>      Start tag for release notes range (default: auto-detect latest)
  --notes-output <path> Output path for notes (default: /tmp/release_notes_<tag>.md)
  --report-output <path> Output path for prep report (default: /tmp/release_prep_<tag>.md)
  --skip-prep           Skip running release prep checks
  --include-live-smoke  Include live read-only smoke checks during prep
  --include-live-write  Include live non-destructive write checks during prep
  --apply               Create annotated git tag (otherwise dry-run)
  --push                Push tag to origin (requires --apply)
  --help                Show this help

Examples:
  ./create_release_tag.sh --version v1.0.1
  ./create_release_tag.sh --version v1.0.1 --apply
  ./create_release_tag.sh --version v1.0.1 --apply --push
  ./create_release_tag.sh --version v1.0.1 --from-tag v1.0.0 --to-ref HEAD
HELP
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 2
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "--version is required"
    exit 2
fi

echo "[release-tag] Starting release tag workflow for ${VERSION}"

if ! printf '%s' "$VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$'; then
    echo "Version must look like vMAJOR.MINOR.PATCH (optional suffix allowed)"
    exit 2
fi

if [ "$PUSH" -eq 1 ] && [ "$APPLY" -ne 1 ]; then
    echo "--push requires --apply"
    exit 2
fi

if [ "$INCLUDE_LIVE_WRITE" -eq 1 ]; then
    INCLUDE_LIVE_SMOKE=1
fi

if ! git rev-parse --verify "$TO_REF" >/dev/null 2>&1; then
    echo "Invalid --to-ref: $TO_REF"
    exit 2
fi

if git rev-parse --verify "refs/tags/$VERSION" >/dev/null 2>&1; then
    echo "Tag already exists: $VERSION"
    exit 2
fi

if [ -n "$(git status --short)" ]; then
    echo "Working tree must be clean before preparing a release tag"
    git status --short
    exit 2
fi

echo "[release-tag] Preconditions satisfied (elapsed=$(elapsed_seconds)s)"

if [ -z "$FROM_TAG" ]; then
    FROM_TAG="$(git describe --tags --abbrev=0 "$TO_REF" 2>/dev/null || true)"
fi

if [ -z "$NOTES_PATH" ]; then
    NOTES_PATH="/tmp/release_notes_${VERSION}.md"
fi

if [ -z "$REPORT_PATH" ]; then
    REPORT_PATH="/tmp/release_prep_${VERSION}.md"
fi

notes_cmd=(
    ./generate_release_notes.sh
    --to-ref "$TO_REF"
    --title "Release Notes ${VERSION}"
    --output "$NOTES_PATH"
)

if [ -n "$FROM_TAG" ]; then
    notes_cmd+=(--from-tag "$FROM_TAG")
fi

"${notes_cmd[@]}"
echo "[release-tag] Release notes generated (elapsed=$(elapsed_seconds)s)"

if [ "$RUN_PREP" -eq 1 ]; then
    echo "[release-tag] Running release prep checks..."
    prep_cmd=(
        ./run_release_prep.sh
        --skip-build
        --skip-release-notes
        --report "$REPORT_PATH"
    )

    if [ "$INCLUDE_LIVE_WRITE" -eq 1 ]; then
        prep_cmd+=(--include-live-write)
    elif [ "$INCLUDE_LIVE_SMOKE" -eq 1 ]; then
        prep_cmd+=(--include-live-smoke)
    fi

    "${prep_cmd[@]}"
    echo "[release-tag] Release prep finished (elapsed=$(elapsed_seconds)s)"
fi

echo "Prepared release assets:"
echo "- Notes:  $NOTES_PATH"
if [ "$RUN_PREP" -eq 1 ]; then
    echo "- Report: $REPORT_PATH"
fi

if [ "$APPLY" -ne 1 ]; then
    echo "Dry-run complete. Tag not created. Use --apply to create tag $VERSION"
    echo "[release-tag] Completed dry-run in $(elapsed_seconds)s"
    exit 0
fi

TAG_MESSAGE_FILE="$(mktemp /tmp/tag_message.XXXXXX)"
{
    echo "Release ${VERSION}"
    echo ""
    echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
    echo "Target ref: $TO_REF"
    if [ -n "$FROM_TAG" ]; then
        echo "Range: ${FROM_TAG}..${TO_REF}"
    fi
    echo ""
    echo "Release notes: $NOTES_PATH"
    if [ "$RUN_PREP" -eq 1 ]; then
        echo "Release prep report: $REPORT_PATH"
    fi
} > "$TAG_MESSAGE_FILE"

git tag -a "$VERSION" "$TO_REF" -F "$TAG_MESSAGE_FILE"
rm -f "$TAG_MESSAGE_FILE"

echo "Created tag: $VERSION"
echo "[release-tag] Tag created locally (elapsed=$(elapsed_seconds)s)"

if [ "$PUSH" -eq 1 ]; then
    git push origin "$VERSION"
    echo "Pushed tag to origin: $VERSION"
    echo "[release-tag] Remote push completed (elapsed=$(elapsed_seconds)s)"
fi

exit 0
