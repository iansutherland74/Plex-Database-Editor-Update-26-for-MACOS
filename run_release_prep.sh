#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

RUN_QUALITY_GATE=1
QUALITY_GATE_ARGS=()
REPORT_PATH="docs/release_prep_report_$(date +%Y%m%d_%H%M%S).md"
RUN_RELEASE_NOTES=1
RELEASE_NOTES_ARGS=()
RELEASE_NOTES_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-quality-gate)
            RUN_QUALITY_GATE=0
            shift
            ;;
        --skip-build)
            QUALITY_GATE_ARGS+=("--skip-build")
            shift
            ;;
        --include-live-smoke)
            QUALITY_GATE_ARGS+=("--include-live-smoke")
            shift
            ;;
        --include-live-write)
            QUALITY_GATE_ARGS+=("--include-live-write")
            shift
            ;;
        --report)
            if [ $# -lt 2 ]; then
                echo "Missing value for --report"
                exit 2
            fi
            REPORT_PATH="$2"
            shift 2
            ;;
        --skip-release-notes)
            RUN_RELEASE_NOTES=0
            shift
            ;;
        --notes-from-tag)
            if [ $# -lt 2 ]; then
                echo "Missing value for --notes-from-tag"
                exit 2
            fi
            RELEASE_NOTES_ARGS+=("--from-tag" "$2")
            shift 2
            ;;
        --notes-to-ref)
            if [ $# -lt 2 ]; then
                echo "Missing value for --notes-to-ref"
                exit 2
            fi
            RELEASE_NOTES_ARGS+=("--to-ref" "$2")
            shift 2
            ;;
        --notes-output)
            if [ $# -lt 2 ]; then
                echo "Missing value for --notes-output"
                exit 2
            fi
            RELEASE_NOTES_PATH="$2"
            RELEASE_NOTES_ARGS+=("--output" "$2")
            shift 2
            ;;
        --notes-title)
            if [ $# -lt 2 ]; then
                echo "Missing value for --notes-title"
                exit 2
            fi
            RELEASE_NOTES_ARGS+=("--title" "$2")
            shift 2
            ;;
        --help|-h)
            cat <<'HELP'
Usage: ./run_release_prep.sh [options]

Options:
  --skip-quality-gate  Skip running quality gate checks
  --skip-release-notes Skip generating release notes
  --skip-build         Forwarded to quality gate (skip app build)
  --include-live-smoke Forwarded to quality gate (read-only live smoke)
  --include-live-write Forwarded to quality gate (read + non-destructive write checks)
  --report <path>      Output report path (default: docs/release_prep_report_<timestamp>.md)
  --notes-from-tag <tag> Forwarded to release notes generator --from-tag
  --notes-to-ref <ref>   Forwarded to release notes generator --to-ref
  --notes-output <path>  Forwarded to release notes generator --output
  --notes-title <title>  Forwarded to release notes generator --title
  --help               Show this help

Examples:
  ./run_release_prep.sh
  ./run_release_prep.sh --skip-build
  ./run_release_prep.sh --skip-build --notes-from-tag v1.0.0
  ./run_release_prep.sh --skip-build --include-live-smoke
  ./run_release_prep.sh --skip-quality-gate --report docs/manual_release_report.md
HELP
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 2
            ;;
    esac
done

mkdir -p "$(dirname "$REPORT_PATH")"

DATE_UTC="$(date -u +"%Y-%m-%d %H:%M:%SZ")"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git rev-parse --short HEAD)"
STATUS_SHORT="$(git status --short || true)"

if [ -z "$STATUS_SHORT" ]; then
    STATUS_SHORT="(clean)"
fi

QUALITY_EXIT=0
QUALITY_OUTPUT="(quality gate skipped)"
NOTES_EXIT=0
NOTES_OUTPUT="(release notes generation skipped)"

if [ "$RUN_QUALITY_GATE" -eq 1 ]; then
    set +e
    if [ "${#QUALITY_GATE_ARGS[@]}" -gt 0 ]; then
        QUALITY_OUTPUT="$(./run_quality_gate.sh "${QUALITY_GATE_ARGS[@]}" 2>&1)"
    else
        QUALITY_OUTPUT="$(./run_quality_gate.sh 2>&1)"
    fi
    QUALITY_EXIT=$?
    set -e
fi

if [ "$RUN_RELEASE_NOTES" -eq 1 ]; then
    set +e
    if [ "${#RELEASE_NOTES_ARGS[@]}" -gt 0 ]; then
        NOTES_OUTPUT="$(./generate_release_notes.sh "${RELEASE_NOTES_ARGS[@]}" 2>&1)"
    else
        NOTES_OUTPUT="$(./generate_release_notes.sh 2>&1)"
    fi
    NOTES_EXIT=$?
    set -e

    if [ "$NOTES_EXIT" -eq 0 ] && [ -z "$RELEASE_NOTES_PATH" ]; then
        RELEASE_NOTES_PATH="$(printf '%s\n' "$NOTES_OUTPUT" | sed -n 's/^Wrote release notes: //p' | tail -n 1)"
    fi
fi

RECENT_COMMITS="$(git --no-pager log --oneline -n 12)"

{
    echo "# Release Prep Report"
    echo ""
    echo "- Generated (UTC): ${DATE_UTC}"
    echo "- Branch: ${BRANCH}"
    echo "- HEAD: ${HEAD_SHA}"
    echo "- Quality gate executed: $([ "$RUN_QUALITY_GATE" -eq 1 ] && echo "yes" || echo "no")"
    echo "- Quality gate exit: ${QUALITY_EXIT}"
    echo "- Release notes generated: $([ "$RUN_RELEASE_NOTES" -eq 1 ] && echo "yes" || echo "no")"
    echo "- Release notes exit: ${NOTES_EXIT}"
    if [ -n "$RELEASE_NOTES_PATH" ]; then
        echo "- Release notes path: ${RELEASE_NOTES_PATH}"
    fi
    echo ""
    echo "## Git Status"
    echo ""
    echo '```text'
    echo "$STATUS_SHORT"
    echo '```'
    echo ""
    echo "## Quality Gate Output"
    echo ""
    echo '```text'
    echo "$QUALITY_OUTPUT"
    echo '```'
    echo ""
    echo "## Release Notes Output"
    echo ""
    echo '```text'
    echo "$NOTES_OUTPUT"
    echo '```'
    echo ""
    echo "## Recent Commits"
    echo ""
    echo '```text'
    echo "$RECENT_COMMITS"
    echo '```'
} > "$REPORT_PATH"

echo "Wrote release prep report: $REPORT_PATH"

if [ "$QUALITY_EXIT" -ne 0 ]; then
    echo "Release prep failed because quality gate failed"
    exit "$QUALITY_EXIT"
fi

if [ "$NOTES_EXIT" -ne 0 ]; then
    echo "Release prep failed because release notes generation failed"
    exit "$NOTES_EXIT"
fi

exit 0
