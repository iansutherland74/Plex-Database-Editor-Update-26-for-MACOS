#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

FROM_TAG=""
TO_REF="HEAD"
OUTPUT_PATH=""
TITLE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --from-tag)
            if [ $# -lt 2 ]; then
                echo "Missing value for --from-tag"
                exit 2
            fi
            FROM_TAG="$2"
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
        --output)
            if [ $# -lt 2 ]; then
                echo "Missing value for --output"
                exit 2
            fi
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --title)
            if [ $# -lt 2 ]; then
                echo "Missing value for --title"
                exit 2
            fi
            TITLE="$2"
            shift 2
            ;;
        --help|-h)
            cat <<'HELP'
Usage: ./generate_release_notes.sh [options]

Options:
  --from-tag <tag>   Start tag for commit range (default: latest tag reachable from --to-ref)
  --to-ref <ref>     End ref/commit (default: HEAD)
  --output <path>    Output markdown path (default: docs/release_notes_<timestamp>.md)
  --title <title>    Custom title (default: Release Notes)
  --help             Show this help

Examples:
  ./generate_release_notes.sh
  ./generate_release_notes.sh --from-tag v1.0.0 --to-ref HEAD
  ./generate_release_notes.sh --from-tag v1.0.0 --output docs/release_notes_next.md
HELP
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 2
            ;;
    esac
done

if [ -z "$TITLE" ]; then
    TITLE="Release Notes"
fi

if ! git rev-parse --verify "$TO_REF" >/dev/null 2>&1; then
    echo "Invalid --to-ref: $TO_REF"
    exit 2
fi

if [ -z "$FROM_TAG" ]; then
    FROM_TAG="$(git describe --tags --abbrev=0 "$TO_REF" 2>/dev/null || true)"
fi

if [ -n "$FROM_TAG" ] && ! git rev-parse --verify "refs/tags/$FROM_TAG" >/dev/null 2>&1; then
    echo "Invalid --from-tag: $FROM_TAG"
    exit 2
fi

if [ -z "$OUTPUT_PATH" ]; then
    OUTPUT_PATH="docs/release_notes_$(date +%Y%m%d_%H%M%S).md"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

RANGE_SPEC="$TO_REF"
if [ -n "$FROM_TAG" ]; then
    RANGE_SPEC="${FROM_TAG}..${TO_REF}"
fi

COMMITS_RAW="$(git --no-pager log --pretty=format:'%h%x09%s' "$RANGE_SPEC" || true)"
CONTRIBUTORS="$(git --no-pager shortlog -sne "$RANGE_SPEC" || true)"

features=""
fixes=""
ci_changes=""
docs_changes=""
other_changes=""

append_line() {
    local current="$1"
    local next_line="$2"
    if [ -z "$current" ]; then
        printf '%s' "$next_line"
    else
        printf '%s\n%s' "$current" "$next_line"
    fi
}

while IFS=$'\t' read -r sha subject; do
    [ -z "$sha" ] && continue
    line="- ${subject} (${sha})"

    lower_subject="$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]')"

    if printf '%s' "$lower_subject" | grep -Eq 'fix|bug|stabiliz|retry|error|correct'; then
        fixes="$(append_line "$fixes" "$line")"
    elif printf '%s' "$lower_subject" | grep -Eq 'ci|workflow|quality gate|github action'; then
        ci_changes="$(append_line "$ci_changes" "$line")"
    elif printf '%s' "$lower_subject" | grep -Eq 'readme|docs|checklist|release note'; then
        docs_changes="$(append_line "$docs_changes" "$line")"
    elif printf '%s' "$lower_subject" | grep -Eq 'add|feature|support|suite|automation|implement|workflow'; then
        features="$(append_line "$features" "$line")"
    else
        other_changes="$(append_line "$other_changes" "$line")"
    fi
done <<< "$COMMITS_RAW"

if [ -z "$features" ]; then features="- None"; fi
if [ -z "$fixes" ]; then fixes="- None"; fi
if [ -z "$ci_changes" ]; then ci_changes="- None"; fi
if [ -z "$docs_changes" ]; then docs_changes="- None"; fi
if [ -z "$other_changes" ]; then other_changes="- None"; fi
if [ -z "$CONTRIBUTORS" ]; then CONTRIBUTORS="(none)"; fi

DATE_UTC="$(date -u +"%Y-%m-%d %H:%M:%SZ")"
TARGET_SHORT="$(git rev-parse --short "$TO_REF")"

{
    echo "# ${TITLE}"
    echo ""
    echo "- Generated (UTC): ${DATE_UTC}"
    echo "- Target ref: ${TO_REF} (${TARGET_SHORT})"
    if [ -n "$FROM_TAG" ]; then
        echo "- Compared from tag: ${FROM_TAG}"
    else
        echo "- Compared from tag: (none, full history to target)"
    fi
    echo ""
    echo "## Features"
    echo "$features"
    echo ""
    echo "## Fixes"
    echo "$fixes"
    echo ""
    echo "## CI and Tooling"
    echo "$ci_changes"
    echo ""
    echo "## Docs"
    echo "$docs_changes"
    echo ""
    echo "## Other Changes"
    echo "$other_changes"
    echo ""
    echo "## Contributors"
    echo '```text'
    echo "$CONTRIBUTORS"
    echo '```'
} > "$OUTPUT_PATH"

echo "Wrote release notes: $OUTPUT_PATH"
