#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/stage_runner_common.sh"
stage_parse_or_exit "run_stage6_tests.sh" "$@"

stage_run_standard "6" "Stage 6 release automation regression tests..." "./tests/Stage6ReleaseAutomationRegressionTests.sh" "Stage 6 release automation regression tests failed"
