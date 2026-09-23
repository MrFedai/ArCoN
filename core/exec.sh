#!/usr/bin/env bash
# ArCoN v3.0 -- core/exec.sh
# The single gate through which every *mutating* operation passes.
#
# DETECT -> VALIDATE -> PLAN -> SHOW -> CONFIRM IF RISKY -> APPLY -> VERIFY
#
# In dry-run mode (ARCON_DRY_RUN=1) nothing below executes; each call is
# recorded in the plan with a category so the user sees exactly what would
# change:  PKG_INSTALL PKG_REMOVE FILE SETTING SERVICE REPO OPTIMIZE COMMAND
#
# Public API:
#   x_run   <CATEGORY> <description> -- cmd [args...]      (as current user)
#   x_root  <CATEGORY> <description> -- cmd [args...]      (as root, via sudo)
#   x_user  <CATEGORY> <description> -- cmd [args...]      (as invoking user, for AUR/makepkg/brew)
#   x_tty   ...same as x_root but keeps the terminal attached (interactive tools)
#   plan_record <CATEGORY> <description>                   (record only)
#   plan_print                                             (human readable plan)
#   as_root cmd...        (read-only root commands, e.g. inspection)
#   fetch_to <url> <dest> [sha256]   verified download (never piped to a shell)

[[ -n "${_ARCON_EXEC_SH:-}" ]] && return 0
_ARCON_EXEC_SH=1

: "${ARCON_DRY_RUN:=0}"
declare -ga ARCON_PLAN=()
_ARCON_SUDO_KEEPALIVE_PID=""

is_dry_run() { [[ "${ARCON_DRY_RUN}" == "1" ]]; }
is_root()    { [[ "${ARCON_EUID:-$EUID}" -eq 0 ]]; }

plan_record() {
    local cat="$1"; shift
    ARCON_PLAN+=("${cat}|${ARCON_TASK:-${ARCON_MODULE:-core}}|$*")
    log_debug "PLAN [$cat] $*"
}

plan_count() { printf '%s' "${#ARCON_PLAN[@]}"; }

plan_print() {
    local cats=(REPO PKG_INSTALL PKG_REMOVE FILE SETTING SERVICE OPTIMIZE COMMAND) c e shown n=0
    ui_header "DRY-RUN PLAN (no changes were made)"
    for c in "${cats[@]}"; do
        shown=0
        for e in "${ARCON_PLAN[@]}"; do
            [[ "${e%%|*}" == "$c" ]] || continue
            if (( shown == 0 )); then
                case "$c" in
                    REPO)        ui_say "\n${BOLD}Repositories to change:${NC}" ;;
                    PKG_INSTALL) ui_say "\n${BOLD}Packages to install:${NC}" ;;
                    PKG_REMOVE)  ui_say "\n${BOLD}Packages to remove:${NC}" ;;
                    FILE)        ui_say "\n${BOLD}Files to create/modify/remove:${NC}" ;;
                    SETTING)     ui_say "\n${BOLD}Settings to change:${NC}" ;;
                    SERVICE)     ui_say "\n${BOLD}Services to modify:${NC}" ;;
                    OPTIMIZE)    ui_say "\n${BOLD}Optimizations to apply:${NC}" ;;
                    COMMAND)     ui_say "\n${BOLD}Other commands:${NC}" ;;
                esac
                shown=1
            fi
            local rest="${e#*|}"
            ui_say "  - [${rest%%|*}] ${rest#*|}"
            n=$((n + 1))
        done
    done
    (( n == 0 )) && ui_say "\n  (nothing to do — system already matches the selected profile)"
    ui_say ""
}

plan_save() { printf '%s\n' "${ARCON_PLAN[@]}" > "$1"; }

# _x_exec <mode> <CATEGORY> <description> -- cmd...
_x_exec() {
    local mode="$1" cat="$2" desc="$3"; shift 3
    [[ "${1:-}" == "--" ]] && shift
    if (( $# == 0 )); then log_error "x_$mode called without command ($desc)"; return 2; fi

    local printable; printable=$(printf '%q ' "$@"); printable="${printable% }"
    if is_dry_run; then
        plan_record "$cat" "$desc  ::  ${printable}"
        return 0
    fi

    log_debug "exec[$mode] $printable"
    local rc=0 logf; logf="$(log_file)"
    case "$mode" in
        run)
            if [[ "${ARCON_VERBOSE:-0}" == "1" ]]; then "$@" 2>&1 | tee -a "$logf"; rc=${PIPESTATUS[0]}
            else "$@" >> "$logf" 2>&1; rc=$?; fi ;;
        root)
            if [[ "${ARCON_VERBOSE:-0}" == "1" ]]; then as_root "$@" 2>&1 | tee -a "$logf"; rc=${PIPESTATUS[0]}
            else as_root "$@" >> "$logf" 2>&1; rc=$?; fi ;;
        user)
            if [[ "${ARCON_VERBOSE:-0}" == "1" ]]; then as_user "$@" 2>&1 | tee -a "$logf"; rc=${PIPESTATUS[0]}
            else as_user "$@" >> "$logf" 2>&1; rc=$?; fi ;;
        tty)  as_root "$@"; rc=$? ;;
        utty) as_user "$@"; rc=$? ;;
    esac
    if (( rc != 0 )); then
        log_error "$desc failed (exit $rc): $printable"
        log_error "  → see log for command output: $logf"
    fi
    return "$rc"
}

x_run()  { _x_exec run  "$@"; }
x_root() { _x_exec root "$@"; }
x_user() { _x_exec user "$@"; }
x_tty()  { _x_exec tty  "$@"; }
x_utty() { _x_exec utty "$@"; }

# as_root: run a command with root privileges (sudo when needed).
as_root() {
    if is_root; then "$@"
    elif command -v sudo >/dev/null 2>&1; then sudo "$@"
    else log_error "root privileges required and sudo is unavailable: $*"; return 126
    fi
}

# as_user: run as the *invoking* (non-root) user. makepkg/yay/brew refuse root.
as_user() {
    if is_root; then
        if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
            sudo -u "$SUDO_USER" -H "$@"
        else
            log_error "this step must not run as root and no SUDO_USER is known: $*"
            return 126
        fi
    else
        "$@"
    fi
}

# Keep sudo credentials fresh during long installs (v2.5 could time out mid-run).
sudo_keepalive_start() {
    is_dry_run && return 0
    is_root && return 0
    command -v sudo >/dev/null 2>&1 || return 0
    # fds detached: a lingering `sleep` must not keep the caller's stdout pipe open
    # (found in tests: every run waited up to 50 s for EOF after ArCoN had exited)
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) </dev/null >/dev/null 2>&1 &
    _ARCON_SUDO_KEEPALIVE_PID=$!
}
sudo_keepalive_stop() {
    if [[ -n "$_ARCON_SUDO_KEEPALIVE_PID" ]]; then
        pkill -P "$_ARCON_SUDO_KEEPALIVE_PID" 2>/dev/null   # the sleep child
        kill "$_ARCON_SUDO_KEEPALIVE_PID" 2>/dev/null
    fi
    _ARCON_SUDO_KEEPALIVE_PID=""
}

# fetch_to <url> <dest> [expected_sha256]
# HTTPS only, fails on HTTP errors (v2.5 used `curl -s` which saved 404 pages
# as theme files — bug #A-21), atomic move, optional checksum verification.
fetch_to() {
    local url="$1" dest="$2" sum="${3:-}"
    [[ "$url" == https://* ]] || { log_error "refusing non-HTTPS download: $url"; return 1; }
    if is_dry_run; then
        plan_record FILE "download $url -> $dest${sum:+ (sha256 $sum)}"
        return 0
    fi
    local tmp; tmp="$(mktemp "${dest}.XXXXXX.part" 2>/dev/null || mktemp)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 15 -o "$tmp" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only -O "$tmp" "$url"
    else
        log_error "neither curl nor wget available"; rm -f "$tmp"; return 1
    fi || { log_error "download failed: $url"; rm -f "$tmp"; return 1; }
    if [[ ! -s "$tmp" ]]; then log_error "downloaded file is empty: $url"; rm -f "$tmp"; return 1; fi
    if [[ -n "$sum" ]]; then
        local got; got="$(sha256_of "$tmp")"
        if [[ "$got" != "$sum" ]]; then
            log_error "checksum mismatch for $url (expected $sum, got $got)"
            rm -f "$tmp"; return 1
        fi
        log_debug "sha256 verified for $url"
    fi
    mv -f "$tmp" "$dest"
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}

net_online() {
    # Real connectivity check (v2.5 printed "Internet: OK" without testing — bug #A-02).
    local url
    for url in $(cfg NET_CHECK_URLS "https://github.com https://archlinux.org https://www.debian.org"); do
        if command -v curl >/dev/null 2>&1; then
            curl -fsS -o /dev/null --max-time 8 --head "$url" 2>/dev/null && return 0
        elif command -v wget >/dev/null 2>&1; then
            wget -q --spider --timeout=8 "$url" 2>/dev/null && return 0
        fi
    done
    return 1
}
