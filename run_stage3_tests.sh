#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"
echo "[stage3] Running Stage 3 workflow tests..."

if bash ./tests/Stage3WorkflowTests.sh; then
	END_TIME="$(date +%s)"
	echo "[stage3] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage3] FAIL: Stage 3 workflow tests failed"
	exit 1
fi
