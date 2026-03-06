#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/stage_runner_common.sh"
stage_parse_or_exit "run_stage10_tests.sh" "$@"

stage_run_standard "10" "Stage 10 live smoke safety contract tests..." "./tests/Stage10LiveSmokeSafetyContractTests.sh" "Stage 10 live smoke safety contract tests failed"
