#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/stage_runner_common.sh"
stage_parse_or_exit "run_stage9_tests.sh" "$@"

stage_run_standard "9" "Stage 9 release report and notes schema tests..." "./tests/Stage9ReleaseReportSchemaTests.sh" "Stage 9 release report and notes schema tests failed"
