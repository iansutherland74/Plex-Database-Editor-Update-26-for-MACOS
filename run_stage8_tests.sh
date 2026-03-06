#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"
echo "[stage8] Running Stage 8 workflow input and versioning edge tests..."

if bash ./tests/Stage8WorkflowInputAndVersioningTests.sh; then
	END_TIME="$(date +%s)"
	echo "[stage8] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage8] FAIL: Stage 8 workflow input and versioning edge tests failed"
	exit 1
fi
