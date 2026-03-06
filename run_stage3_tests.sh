#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/stage_runner_common.sh"
stage_parse_or_exit "run_stage3_tests.sh" "$@"

stage_run_standard "3" "Stage 3 workflow tests..." "./tests/Stage3WorkflowTests.sh" "Stage 3 workflow tests failed"
