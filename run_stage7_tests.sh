#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"
echo "[stage7] Running Stage 7 CI/release workflow contract tests..."

if bash ./tests/Stage7CIWorkflowContractTests.sh; then
	END_TIME="$(date +%s)"
	echo "[stage7] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage7] FAIL: Stage 7 CI/release workflow contract tests failed"
	exit 1
fi
