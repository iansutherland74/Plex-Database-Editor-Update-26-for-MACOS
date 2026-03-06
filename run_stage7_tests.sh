#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/stage_runner_common.sh"
stage_parse_or_exit "run_stage7_tests.sh" "$@"

stage_run_standard "7" "Stage 7 CI/release workflow contract tests..." "./tests/Stage7CIWorkflowContractTests.sh" "Stage 7 CI/release workflow contract tests failed"
