#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

RUN_QUALITY_GATE=1
QUALITY_GATE_ARGS=()
REPORT_PATH="docs/release_prep_report_$(date +%Y%m%d_%H%M%S).md"

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
        --help|-h)
            cat <<'HELP'
Usage: ./run_release_prep.sh [options]

Options:
  --skip-quality-gate  Skip running quality gate checks
  --skip-build         Forwarded to quality gate (skip app build)
  --include-live-smoke Forwarded to quality gate (read-only live smoke)
  --include-live-write Forwarded to quality gate (read + non-destructive write checks)
  --report <path>      Output report path (default: docs/release_prep_report_<timestamp>.md)
  --help               Show this help

Examples:
  ./run_release_prep.sh
  ./run_release_prep.sh --skip-build
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

if [ "$RUN_QUALITY_GATE" -eq 1 ]; then
    set +e
    QUALITY_OUTPUT="$(./run_quality_gate.sh "${QUALITY_GATE_ARGS[@]}" 2>&1)"
    QUALITY_EXIT=$?
    set -e
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

exit 0
