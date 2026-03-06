#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"
echo "[stage5] Running Stage 5 tooling contract tests..."

if bash ./tests/Stage5ToolingContractTests.sh; then
	END_TIME="$(date +%s)"
	echo "[stage5] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage5] FAIL: Stage 5 tooling contract tests failed"
	exit 1
fi
