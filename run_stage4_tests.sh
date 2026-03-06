#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"
echo "[stage4] Running Stage 4 release-tag tests..."

if bash ./tests/Stage4ReleaseTagTests.sh; then
	END_TIME="$(date +%s)"
	echo "[stage4] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage4] FAIL: Stage 4 release-tag tests failed"
	exit 1
fi
