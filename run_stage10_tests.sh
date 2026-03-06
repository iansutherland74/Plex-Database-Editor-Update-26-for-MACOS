#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

bash ./tests/Stage10LiveSmokeSafetyContractTests.sh
