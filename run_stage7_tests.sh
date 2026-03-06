#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

QUIET=0

while [ $# -gt 0 ]; do
	case "$1" in
		--quiet|-q)
			QUIET=1
			shift
			;;
		--help|-h)
			cat <<'HELP'
Usage: ./run_stage7_tests.sh [--quiet]

Options:
  --quiet, -q  Reduce output; print full logs only on failure
  --help       Show this help
HELP
			exit 0
			;;
		*)
			echo "Unknown argument: $1"
			exit 2
			;;
	esac
done

log() {
	if [ "$QUIET" -eq 0 ]; then
		echo "$*"
	fi
}

run_stage_test() {
	if [ "$QUIET" -eq 1 ]; then
		local stage_log
		stage_log="$(mktemp /tmp/stage7_tests.XXXXXX)"
		if bash ./tests/Stage7CIWorkflowContractTests.sh >"$stage_log" 2>&1; then
			rm -f "$stage_log"
			return 0
		fi
		cat "$stage_log"
		rm -f "$stage_log"
		return 1
	fi

	bash ./tests/Stage7CIWorkflowContractTests.sh
}

START_TIME="$(date +%s)"
log "[stage7] Running Stage 7 CI/release workflow contract tests..."

if run_stage_test; then
	END_TIME="$(date +%s)"
	log "[stage7] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage7] FAIL: Stage 7 CI/release workflow contract tests failed"
	exit 1
fi
