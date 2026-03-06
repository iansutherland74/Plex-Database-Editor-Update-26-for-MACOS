#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"
echo "[stage6] Running Stage 6 release automation regression tests..."

if bash ./tests/Stage6ReleaseAutomationRegressionTests.sh; then
	END_TIME="$(date +%s)"
	echo "[stage6] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage6] FAIL: Stage 6 release automation regression tests failed"
	exit 1
fi
