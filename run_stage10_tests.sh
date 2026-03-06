#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"
echo "[stage10] Running Stage 10 live smoke safety contract tests..."

if bash ./tests/Stage10LiveSmokeSafetyContractTests.sh; then
	END_TIME="$(date +%s)"
	echo "[stage10] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage10] FAIL: Stage 10 live smoke safety contract tests failed"
	exit 1
fi
