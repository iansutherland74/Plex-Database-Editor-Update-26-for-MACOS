#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/stage_runner_common.sh"
stage_parse_or_exit "run_stage8_tests.sh" "$@"

stage_run_standard "8" "Stage 8 workflow input and versioning edge tests..." "./tests/Stage8WorkflowInputAndVersioningTests.sh" "Stage 8 workflow input and versioning edge tests failed"
