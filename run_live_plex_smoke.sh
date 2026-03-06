#!/bin/bash
set -euo pipefail

SERVER_URL="${PLEX_SERVER_URL:-http://127.0.0.1:32400}"
TOKEN="${PLEX_TOKEN:-}"
INCLUDE_WRITE=0
TIMEOUT_SECONDS=12

while [ $# -gt 0 ]; do
    case "$1" in
        --server-url)
            if [ $# -lt 2 ]; then
                echo "Missing value for --server-url"
                exit 2
            fi
            SERVER_URL="$2"
            shift 2
            ;;
        --token)
            if [ $# -lt 2 ]; then
                echo "Missing value for --token"
                exit 2
            fi
            TOKEN="$2"
            shift 2
            ;;
        --include-write)
            INCLUDE_WRITE=1
            shift
            ;;
        --help|-h)
            cat <<'HELP'
Usage: ./run_live_plex_smoke.sh [options]

Options:
  --server-url <url>   Plex server URL (default: http://127.0.0.1:32400)
  --token <token>      Plex token (default: from PLEX_TOKEN or local defaults)
  --include-write      Also queue non-destructive section actions (refresh/analyze)
  --help               Show this help

Environment:
  PLEX_SERVER_URL      Alternative to --server-url
  PLEX_TOKEN           Alternative to --token

Notes:
- Default mode is read-only endpoint validation.
- --include-write triggers section refresh/analyze queue checks.
- Empty trash is never called by this script.
HELP
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 2
            ;;
    esac
done

SERVER_URL="${SERVER_URL%/}"

if [ -z "$TOKEN" ]; then
    TOKEN="$(defaults read com.plexapp.plexmediaserver PlexOnlineToken 2>/dev/null || true)"
fi

if [ -z "$TOKEN" ]; then
    echo "ERROR: Plex token not found. Set PLEX_TOKEN or pass --token."
    exit 2
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $1"
}

warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    echo "WARN: $1"
}

is_success_code() {
    case "$1" in
        2*|3*) return 0 ;;
        *) return 1 ;;
    esac
}

http_code() {
    local method="$1"
    local url="$2"
    local code
    code="$(curl -s -m "$TIMEOUT_SECONDS" -o /dev/null -w "%{http_code}" -X "$method" "$url" || true)"
    if [ -z "$code" ]; then
        echo "000"
    else
        echo "$code"
    fi
}

api_url() {
    local path="$1"
    local query="${2:-}"
    if [ -n "$query" ]; then
        echo "${SERVER_URL}${path}?${query}&X-Plex-Token=${TOKEN}"
    else
        echo "${SERVER_URL}${path}?X-Plex-Token=${TOKEN}"
    fi
}

probe_advisory_support() {
    local path="$1"
    local options_code head_code
    options_code="$(http_code OPTIONS "$(api_url "$path")")"

    if [ "$options_code" = "404" ] || [ "$options_code" = "405" ] || [ "$options_code" = "000" ]; then
        head_code="$(http_code HEAD "$(api_url "$path")")"
    else
        head_code="skip"
    fi

    if is_success_code "$options_code" || { [ "$head_code" != "skip" ] && is_success_code "$head_code"; }; then
        echo "supported (OPTIONS=${options_code}, HEAD=${head_code})"
    else
        echo "inconclusive (OPTIONS=${options_code}, HEAD=${head_code})"
    fi
}

echo "Running live Plex smoke tests against: $SERVER_URL"

identity_xml="$(curl -s -m "$TIMEOUT_SECONDS" "$(api_url "/identity")" || true)"
if echo "$identity_xml" | grep -q "<MediaContainer"; then
    friendly_name="$(echo "$identity_xml" | sed -n 's/.*friendlyName="\([^"]*\)".*/\1/p' | head -n 1)"
    version="$(echo "$identity_xml" | sed -n 's/.*version="\([^"]*\)".*/\1/p' | head -n 1)"
    if [ -z "$friendly_name" ]; then
        friendly_name="Unknown"
    fi
    if [ -z "$version" ]; then
        version="Unknown"
    fi
    pass "identity endpoint reachable (server=${friendly_name}, version=${version})"
else
    fail "identity endpoint did not return MediaContainer"
fi

sections_xml="$(curl -s -m "$TIMEOUT_SECONDS" "$(api_url "/library/sections")" || true)"
section_lines="$(echo "$sections_xml" | tr '<' '\n' | grep '^Directory ' || true)"

if [ -z "$section_lines" ]; then
    fail "no library sections discovered"
else
    pass "library sections discovered"
fi

declare -a SECTION_KEYS=()
declare -a SECTION_TYPES=()
declare -a SECTION_TITLES=()

while IFS= read -r line; do
    [ -z "$line" ] && continue
    key="$(echo "$line" | sed -n 's/.* key="\([^"]*\)".*/\1/p')"
    type="$(echo "$line" | sed -n 's/.* type="\([^"]*\)".*/\1/p')"
    title="$(echo "$line" | sed -n 's/.* title="\([^"]*\)".*/\1/p')"

    if [ -n "$key" ]; then
        SECTION_KEYS+=("$key")
        SECTION_TYPES+=("$type")
        SECTION_TITLES+=("$title")
    fi
done <<< "$section_lines"

if [ "${#SECTION_KEYS[@]}" -eq 0 ]; then
    fail "section parser could not extract section keys"
fi

tv_found=0
movie_found=0

for i in "${!SECTION_KEYS[@]}"; do
    key="${SECTION_KEYS[$i]}"
    type="${SECTION_TYPES[$i]}"
    title="${SECTION_TITLES[$i]}"

    [ "$type" = "show" ] && tv_found=1
    [ "$type" = "movie" ] && movie_found=1

    trash_xml="$(curl -s -m "$TIMEOUT_SECONDS" "$(api_url "/library/sections/${key}/all" "trash=1")" || true)"
    if echo "$trash_xml" | grep -q "<MediaContainer"; then
        trash_size="$(echo "$trash_xml" | sed -n 's/.*<MediaContainer[^>]*size="\([0-9][0-9]*\)".*/\1/p' | head -n 1)"
        [ -z "$trash_size" ] && trash_size=0
        pass "trash preview for section ${key} (${title}) returned size=${trash_size}"
    else
        fail "trash preview failed for section ${key} (${title})"
    fi

    refresh_probe="$(probe_advisory_support "/library/sections/${key}/refresh")"
    analyze_probe="$(probe_advisory_support "/library/sections/${key}/analyze")"
    empty_probe="$(probe_advisory_support "/library/sections/${key}/emptyTrash")"

    warn "capability probe section ${key} (${title}): refresh=${refresh_probe}, analyze=${analyze_probe}, emptyTrash=${empty_probe}"
done

if [ "$tv_found" -eq 1 ]; then
    pass "at least one TV section detected"
else
    warn "no TV section detected"
fi

if [ "$movie_found" -eq 1 ]; then
    pass "at least one Movie section detected"
else
    warn "no Movie section detected"
fi

if [ "$INCLUDE_WRITE" -eq 1 ] && [ "${#SECTION_KEYS[@]}" -gt 0 ]; then
    echo "Running optional non-destructive write checks (refresh/analyze)..."

    for i in "${!SECTION_KEYS[@]}"; do
        key="${SECTION_KEYS[$i]}"
        title="${SECTION_TITLES[$i]}"

        refresh_put="$(http_code PUT "$(api_url "/library/sections/${key}/refresh")")"
        refresh_get="skip"
        if ! is_success_code "$refresh_put"; then
            refresh_get="$(http_code GET "$(api_url "/library/sections/${key}/refresh")")"
        fi

        if is_success_code "$refresh_put" || { [ "$refresh_get" != "skip" ] && is_success_code "$refresh_get"; }; then
            pass "refresh queue accepted for section ${key} (${title}) [PUT=${refresh_put}, GET=${refresh_get}]"
        else
            fail "refresh queue failed for section ${key} (${title}) [PUT=${refresh_put}, GET=${refresh_get}]"
        fi

        analyze_put="$(http_code PUT "$(api_url "/library/sections/${key}/analyze")")"
        analyze_get="skip"
        if ! is_success_code "$analyze_put"; then
            analyze_get="$(http_code GET "$(api_url "/library/sections/${key}/analyze")")"
        fi

        if is_success_code "$analyze_put" || { [ "$analyze_get" != "skip" ] && is_success_code "$analyze_get"; }; then
            pass "analyze queue accepted for section ${key} (${title}) [PUT=${analyze_put}, GET=${analyze_get}]"
        else
            fail "analyze queue failed for section ${key} (${title}) [PUT=${analyze_put}, GET=${analyze_get}]"
        fi
    done
else
    echo "Skipping write checks (run with --include-write to enable refresh/analyze queue tests)."
fi

echo ""
echo "Summary: PASS=${PASS_COUNT} WARN=${WARN_COUNT} FAIL=${FAIL_COUNT}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0
