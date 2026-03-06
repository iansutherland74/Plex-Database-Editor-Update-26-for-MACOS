#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"
echo "[stage9] Running Stage 9 release report and notes schema tests..."

if bash ./tests/Stage9ReleaseReportSchemaTests.sh; then
	END_TIME="$(date +%s)"
	echo "[stage9] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage9] FAIL: Stage 9 release report and notes schema tests failed"
	exit 1
fi
