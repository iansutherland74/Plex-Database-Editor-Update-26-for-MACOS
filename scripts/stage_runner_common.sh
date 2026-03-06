#!/bin/bash

# Shared quiet/help behavior for stage runner wrappers.
STAGE_QUIET=0

stage_parse_or_exit() {
    local script_name="$1"
    shift

    STAGE_QUIET=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --quiet|-q)
                STAGE_QUIET=1
                shift
                ;;
            --help|-h)
                cat <<HELP
Usage: ./${script_name} [--quiet]

Options:
  --quiet, -q  Reduce output; print full logs only on failure
  --help       Show this help
HELP
                exit 0
                ;;
            *)
                echo "Unknown argument: $1"
                exit 2
                ;;
        esac
    done
}

stage_log() {
    if [ "$STAGE_QUIET" -eq 0 ]; then
        echo "$*"
    fi
}

stage_run_with_quiet() {
    local tmp_prefix="$1"
    shift

    if [ "$STAGE_QUIET" -eq 1 ]; then
        local stage_log_file
        stage_log_file="$(mktemp "${tmp_prefix}.XXXXXX")"
        if "$@" >"$stage_log_file" 2>&1; then
            rm -f "$stage_log_file"
            return 0
        fi
        cat "$stage_log_file"
        rm -f "$stage_log_file"
        return 1
    fi

    "$@"
}

stage_run_standard() {
    local stage_id="$1"
    local run_message="$2"
    local test_script_path="$3"
    local fail_message="$4"
    local start_time end_time

    start_time="$(date +%s)"
    stage_log "[stage${stage_id}] Running ${run_message}"

    if stage_run_with_quiet "/tmp/stage${stage_id}_tests" bash "$test_script_path"; then
        end_time="$(date +%s)"
        stage_log "[stage${stage_id}] Completed in $((end_time - start_time))s"
        return 0
    fi

    echo "[stage${stage_id}] FAIL: ${fail_message}"
    return 1
}
