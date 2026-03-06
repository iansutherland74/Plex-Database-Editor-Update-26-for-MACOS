#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

START_TIME="$(date +%s)"
echo "[stage11] Running Stage 11 release tag provenance contract tests..."

if bash ./tests/Stage11ReleaseTagProvenanceTests.sh; then
	END_TIME="$(date +%s)"
	echo "[stage11] Completed in $((END_TIME - START_TIME))s"
else
	echo "[stage11] FAIL: Stage 11 release tag provenance contract tests failed"
	exit 1
fi
