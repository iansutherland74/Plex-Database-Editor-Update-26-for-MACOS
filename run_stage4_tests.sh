#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

source "$PROJECT_DIR/scripts/stage_runner_common.sh"
stage_parse_or_exit "run_stage4_tests.sh" "$@"

stage_run_standard "4" "Stage 4 release-tag tests..." "./tests/Stage4ReleaseTagTests.sh" "Stage 4 release-tag tests failed"
