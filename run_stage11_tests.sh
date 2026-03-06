#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/stage_runner_common.sh"
stage_parse_or_exit "run_stage11_tests.sh" "$@"

stage_run_standard "11" "Stage 11 release tag provenance contract tests..." "./tests/Stage11ReleaseTagProvenanceTests.sh" "Stage 11 release tag provenance contract tests failed"
