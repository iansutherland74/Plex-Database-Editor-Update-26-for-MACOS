#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/stage_runner_common.sh"
stage_parse_or_exit "run_stage5_tests.sh" "$@"

stage_run_standard "5" "Stage 5 tooling contract tests..." "./tests/Stage5ToolingContractTests.sh" "Stage 5 tooling contract tests failed"
