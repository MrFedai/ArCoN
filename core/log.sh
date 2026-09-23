#!/usr/bin/env bash
# ArCoN v3.0 -- core/log.sh
# Structured logging: level filtering, timestamps, module tags, file sink.
#
# Public API:
#   log_init [logfile]
#   log_debug|log_info|log_warn|log_error <msg...>
#   log_result <operation> <PASS|FAIL|SKIP> [detail]
#   log_set_level <debug|info|warn|error>
#   log_file            -> prints active log file path
#   die <exit_code> <msg...>
#
# Every record is written to the log file as:
#   2026-09-23T18:00:00+03:00 [LEVEL] [module] message
# and to the terminal with colors (unless ARCON_NO_COLOR=1).

[[ -n "${_ARCON_LOG_SH:-}" ]] && return 0
_ARCON_LOG_SH=1

: "${ARCON_LOG_LEVEL:=info}"
: "${ARCON_LOG_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/arcon/logs}"
_ARCON_LOG_FILE=""

_log_level_num() {
    case "${1,,}" in
        debug) echo 10 ;;
        info)  echo 20 ;;
        warn)  echo 30 ;;
        error) echo 40 ;;
        *)     echo 20 ;;
    esac
}

log_set_level() { ARCON_LOG_LEVEL="${1,,}"; }

log_file() { printf '%s\n' "$_ARCON_LOG_FILE"; }

log_init() {
    local target="${1:-}"
    if [[ -n "$target" ]]; then
        _ARCON_LOG_FILE="$target"
    else
        mkdir -p "$ARCON_LOG_DIR" 2>/dev/null || ARCON_LOG_DIR="${TMPDIR:-/tmp}"
        _ARCON_LOG_FILE="$ARCON_LOG_DIR/arcon-$(date +%Y%m%d-%H%M%S)-$$.log"
    fi
    : > "$_ARCON_LOG_FILE" 2>/dev/null || _ARCON_LOG_FILE="/dev/null"
    chmod 600 "$_ARCON_LOG_FILE" 2>/dev/null || true
    {
        printf '# ArCoN %s log\n' "${ARCON_VERSION:-3.0.0}"
        printf '# started: %s\n' "$(date -Iseconds 2>/dev/null || date)"
        printf '# argv: %s\n' "${ARCON_ARGV:-}"
    } >> "$_ARCON_LOG_FILE" 2>/dev/null || true

    # Keep the last 20 logs only.
    if [[ -d "$ARCON_LOG_DIR" ]]; then
        local old
        # shellcheck disable=SC2012  # filenames are timestamped and ASCII-safe
        old=$(ls -1t "$ARCON_LOG_DIR"/arcon-*.log 2>/dev/null | tail -n +21)
        [[ -n "$old" ]] && printf '%s\n' "$old" | while read -r f; do rm -f "$f"; done
    fi
}

_log_emit() {
    local level="$1" color="$2"; shift 2
    local msg="$*"
    local module="${ARCON_MODULE:-core}"
    local ts; ts=$(date -Iseconds 2>/dev/null || date)

    if [[ -n "$_ARCON_LOG_FILE" ]]; then
        printf '%s [%-5s] [%s] %s\n' "$ts" "$level" "$module" "$msg" >> "$_ARCON_LOG_FILE" 2>/dev/null || true
    fi
    if (( $(_log_level_num "$level") >= $(_log_level_num "$ARCON_LOG_LEVEL") )); then
        if [[ "${ARCON_NO_COLOR:-0}" == "1" || ! -t 2 ]]; then
            printf '[%s] %s\n' "$level" "$msg" >&2
        else
            printf '\033[%sm[%s]\033[0m %s\n' "$color" "$level" "$msg" >&2
        fi
    fi
}

log_debug() { _log_emit DEBUG '0;90' "$@"; }
log_info()  { _log_emit INFO  '0;36' "$@"; }
log_warn()  { _log_emit WARN  '1;33' "$@"; }
log_error() { _log_emit ERROR '1;31' "$@"; }

# log_result <operation> <status> [detail]
# Machine readable line consumed by tests and the final audit summary.
log_result() {
    local op="$1" status="$2"; shift 2 || true
    local detail="${*:-}"
    if [[ -n "$_ARCON_LOG_FILE" ]]; then
        printf '%s [RESULT] [%s] op=%s status=%s detail=%s\n' \
            "$(date -Iseconds 2>/dev/null || date)" "${ARCON_MODULE:-core}" "$op" "$status" "$detail" \
            >> "$_ARCON_LOG_FILE" 2>/dev/null || true
    fi
    case "$status" in
        PASS|OK)   log_info  "✓ $op${detail:+ — $detail}" ;;
        SKIP)      log_info  "· $op skipped${detail:+ — $detail}" ;;
        *)         log_warn  "✗ $op failed${detail:+ — $detail}" ;;
    esac
}

die() {
    local code="$1"; shift
    log_error "$*"
    log_error "Log file: ${_ARCON_LOG_FILE:-<none>}"
    exit "$code"
}
