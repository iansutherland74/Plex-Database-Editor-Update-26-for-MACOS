#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

assert_file_contains() {
    local path="$1"
    local needle="$2"
    local message="$3"
    if ! grep -Fq -- "$needle" "$path"; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_text_contains() {
    local text="$1"
    local needle="$2"
    local message="$3"
    if ! printf '%s' "$text" | grep -Fq -- "$needle"; then
        echo "FAIL: $message"
        exit 1
    fi
}

assert_command_fails() {
    local message="$1"
    shift
    set +e
    "$@" >/tmp/stage10_negative_test.log 2>&1
    local exit_code=$?
    set -e
    if [ "$exit_code" -eq 0 ]; then
        echo "FAIL: $message"
        exit 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/plex_stage10_tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

CLONE_DIR="$TMP_DIR/repo"
git clone --quiet --no-local "$PROJECT_DIR" "$CLONE_DIR"
chmod +x "$CLONE_DIR"/run_live_plex_smoke.sh 2>/dev/null || true

# Test 1: help output should keep safety contract language.
HELP_OUTPUT="$(bash -lc "cd '$CLONE_DIR' && ./run_live_plex_smoke.sh --help")"
assert_text_contains "$HELP_OUTPUT" "--include-write" "Live smoke help should document include-write flag"
assert_text_contains "$HELP_OUTPUT" "non-destructive section actions (refresh/analyze)" "Help should explain non-destructive write behavior"
assert_text_contains "$HELP_OUTPUT" "Empty trash is never called by this script." "Help should keep explicit empty-trash safety note"

# Test 2: unknown argument should fail fast.
assert_command_fails "run_live_plex_smoke should fail for unknown arguments" \
    bash -lc "cd '$CLONE_DIR' && ./run_live_plex_smoke.sh --not-a-real-flag"
assert_file_contains /tmp/stage10_negative_test.log "Unknown argument: --not-a-real-flag" "Unknown flag should produce clear error"

# Test 3: missing token should fail before network calls.
BIN_MISSING_TOKEN="$TMP_DIR/bin_missing_token"
mkdir -p "$BIN_MISSING_TOKEN"
cat > "$BIN_MISSING_TOKEN/defaults" <<'EOF'
#!/bin/bash
exit 1
EOF
cat > "$BIN_MISSING_TOKEN/curl" <<'EOF'
#!/bin/bash
echo "curl-called" >> "${STAGE10_CURL_CALLED_LOG:?}"
exit 1
EOF
chmod +x "$BIN_MISSING_TOKEN/defaults" "$BIN_MISSING_TOKEN/curl"

CURL_CALLED_LOG="$TMP_DIR/curl_called.log"
assert_command_fails "run_live_plex_smoke should fail when token is unavailable" \
    env PATH="$BIN_MISSING_TOKEN:/usr/bin:/bin:/usr/sbin:/sbin" STAGE10_CURL_CALLED_LOG="$CURL_CALLED_LOG" PLEX_TOKEN= \
    "$CLONE_DIR/run_live_plex_smoke.sh" --server-url http://127.0.0.1:9
assert_file_contains /tmp/stage10_negative_test.log "ERROR: Plex token not found" "Missing token path should produce explicit guidance"
if [ -f "$CURL_CALLED_LOG" ] && [ -s "$CURL_CALLED_LOG" ]; then
    echo "FAIL: live smoke should not call curl when token lookup fails"
    exit 1
fi

# Test 4: include-write mode should use refresh/analyze writes but never emptyTrash writes.
BIN_STUB="$TMP_DIR/bin_stub"
mkdir -p "$BIN_STUB"
cat > "$BIN_STUB/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
method="GET"
url=""
want_code=0

while [ $# -gt 0 ]; do
    case "$1" in
        -X)
            method="$2"
            shift 2
            ;;
        -w)
            want_code=1
            shift 2
            ;;
        -o|-m)
            shift 2
            ;;
        -s)
            shift
            ;;
        http://*|https://*)
            url="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo "$method $url" >> "${STAGE10_CURL_LOG:?}"

if [ "$want_code" -eq 1 ]; then
    printf '200'
    exit 0
fi

if [[ "$url" == *"/identity"* ]]; then
    echo '<MediaContainer friendlyName="Stage10Stub" version="1.0"/>'
elif [[ "$url" == *"/library/sections?"* ]]; then
    echo '<MediaContainer size="2"><Directory key="1" type="show" title="Shows"/><Directory key="2" type="movie" title="Movies"/></MediaContainer>'
elif [[ "$url" == *"/library/sections/"*"/all"* ]]; then
    echo '<MediaContainer size="0"/>'
else
    echo '<MediaContainer/>'
fi
EOF
chmod +x "$BIN_STUB/curl"

CURL_LOG_WRITE="$TMP_DIR/curl_write.log"
env PATH="$BIN_STUB:/usr/bin:/bin:/usr/sbin:/sbin" STAGE10_CURL_LOG="$CURL_LOG_WRITE" \
    "$CLONE_DIR/run_live_plex_smoke.sh" --server-url http://plex.stub:32400 --token stage10-token --include-write >/tmp/stage10_write_mode.log 2>&1

assert_file_contains /tmp/stage10_write_mode.log "PASS: refresh queue accepted" "Include-write should execute refresh write checks"
assert_file_contains /tmp/stage10_write_mode.log "PASS: analyze queue accepted" "Include-write should execute analyze write checks"

if ! grep -Eq '^PUT .*/refresh\?' "$CURL_LOG_WRITE"; then
    echo "FAIL: include-write should issue PUT refresh requests"
    exit 1
fi

if ! grep -Eq '^PUT .*/analyze\?' "$CURL_LOG_WRITE"; then
    echo "FAIL: include-write should issue PUT analyze requests"
    exit 1
fi

if grep -Eq '^(PUT|GET|POST|DELETE|PATCH) .*/emptyTrash\?' "$CURL_LOG_WRITE"; then
    echo "FAIL: live smoke must not issue emptyTrash write requests"
    exit 1
fi

# Test 5: default (no include-write) must not issue refresh/analyze write requests.
CURL_LOG_READONLY="$TMP_DIR/curl_readonly.log"
env PATH="$BIN_STUB:/usr/bin:/bin:/usr/sbin:/sbin" STAGE10_CURL_LOG="$CURL_LOG_READONLY" \
    "$CLONE_DIR/run_live_plex_smoke.sh" --server-url http://plex.stub:32400 --token stage10-token >/tmp/stage10_read_mode.log 2>&1

assert_file_contains /tmp/stage10_read_mode.log "Skipping write checks" "Default mode should skip write checks"

if grep -Eq '^(PUT|GET) .*/(refresh|analyze)\?' "$CURL_LOG_READONLY"; then
    echo "FAIL: read-only mode should not issue refresh/analyze write requests"
    exit 1
fi

echo "PASS: Stage 10 live smoke safety contract tests"
