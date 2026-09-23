#!/usr/bin/env bash
# ArCoN v3.0 -- core/main.sh
# Platform-independent orchestrator: environment -> detect -> validate -> plan
# -> show -> confirm -> apply -> verify. Contains no distro-specific logic;
# everything platform-specific lives in platform/ and is chosen at runtime.

[[ -n "${_ARCON_MAIN_SH:-}" ]] && return 0
_ARCON_MAIN_SH=1

set -uo pipefail

# --------------------------------------------------------------- environment
arcon_env_init() {
    : "${ARCON_ROOT:?ARCON_ROOT must be set by setup.sh}"

    # Real user, even when started with sudo — v2.5 wrote root-owned files into
    # the invoking user's $HOME (bug #A-11) because it used $HOME/$USER blindly.
    ARCON_EUID="$(id -u)"
    if [[ "$ARCON_EUID" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
        ARCON_USER="$SUDO_USER"
        ARCON_HOME="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
        [[ -z "$ARCON_HOME" ]] && ARCON_HOME="$(eval echo "~$SUDO_USER")"
    else
        ARCON_USER="$(id -un)"
        ARCON_HOME="${HOME:-$(eval echo "~$(id -un)")}"
    fi
    [[ -d "$ARCON_HOME" ]] || die 3 "cannot determine a valid home directory (got '$ARCON_HOME')"

    ARCON_TMP="$(mktemp -d "${TMPDIR:-/tmp}/arcon.XXXXXXXX")" || die 3 "cannot create temp dir"
    chmod 700 "$ARCON_TMP"
    : "${ARCON_INTERACTIVE:=1}"
    [[ -t 0 ]] || ARCON_INTERACTIVE=0
    : "${ARCON_VERBOSE:=0}"
    : "${ARCON_DRY_RUN:=0}"
    : "${ARCON_SYSROOT:=}"
    : "${XDG_STATE_HOME:=$ARCON_HOME/.local/state}"
    : "${XDG_CONFIG_HOME:=$ARCON_HOME/.config}"
    ARCON_LOG_DIR="${ARCON_LOG_DIR:-$XDG_STATE_HOME/arcon/logs}"
    ARCON_STATE_DIR="${ARCON_STATE_DIR:-$XDG_STATE_HOME/arcon}"
    export ARCON_ROOT ARCON_HOME ARCON_USER ARCON_TMP ARCON_EUID ARCON_INTERACTIVE \
           ARCON_VERBOSE ARCON_DRY_RUN ARCON_LOG_DIR ARCON_STATE_DIR ARCON_SYSROOT \
           XDG_STATE_HOME XDG_CONFIG_HOME
}

arcon_cleanup() {
    local rc=$?
    sudo_keepalive_stop 2>/dev/null || true
    [[ -n "${ARCON_TMP:-}" && -d "$ARCON_TMP" && "$ARCON_TMP" == */arcon.* ]] && rm -rf "$ARCON_TMP"
    return $rc
}

arcon_source_all() {
    local f
    for f in log ui config exec fs rollback state cli; do
        # shellcheck source=/dev/null
        . "$ARCON_ROOT/core/$f.sh" || { printf 'FATAL: cannot load core/%s.sh\n' "$f" >&2; exit 3; }
    done
    for f in detect hardware; do
        # shellcheck source=/dev/null
        . "$ARCON_ROOT/platform/$f.sh" || die 3 "cannot load platform/$f.sh"
    done
    # shellcheck source=/dev/null
    . "$ARCON_ROOT/platform/pkg/pkg.sh" || die 3 "cannot load platform/pkg/pkg.sh"
    for f in "$ARCON_ROOT"/modules/*.sh; do
        # shellcheck source=/dev/null
        . "$f" || die 3 "cannot load $f"
    done
    ARCON_MODULE=core
}

# --------------------------------------------------------------- preflight
arcon_preflight() {
    local problems=0

    if [[ "$OS_SUPPORT" == unsupported ]]; then
        log_error "unsupported platform: ${OS_NAME:-unknown} (${OS_ID_RAW:-?})"
        log_error "supported: Arch, Debian, Ubuntu, Fedora, openSUSE, macOS — see docs/PLATFORMS.md"
        return 1
    fi
    if [[ "$OS_SUPPORT" == experimental ]]; then
        log_warn "platform '${OS_NAME}' is handled as '${OS_ID}' but is NOT validated by ArCoN's test suite"
        [[ "${ARCON_INTERACTIVE}" == "1" ]] && { ui_confirm "Continue anyway" n || return 1; }
    fi

    case "$HW_ARCH" in
        x86_64|aarch64|arm64) ;;
        *) log_warn "architecture '$HW_ARCH' is untested; package availability may differ" ;;
    esac

    if is_root && [[ -z "${SUDO_USER:-}" ]]; then
        log_warn "running directly as root: user-level configuration would land in /root"
        [[ "${ARCON_INTERACTIVE}" == "1" ]] && { ui_confirm "Continue as root anyway" n || return 1; }
    fi

    if ! is_root; then
        if ! command -v sudo >/dev/null 2>&1; then
            log_error "sudo is not installed and ArCoN is not running as root"
            problems=$((problems + 1))
        elif ! is_dry_run; then
            ui_say "${DIM}Administrator rights are required for system changes.${NC}"
            if ! sudo -v 2>/dev/null; then
                sudo -p "[sudo] password for %u: " true || { log_error "sudo authentication failed"; problems=$((problems + 1)); }
            fi
            sudo_keepalive_start
        fi
    fi

    local min_gb free_gb
    min_gb="$(cfg MIN_DISK_GB 10)"
    free_gb="$(df -Pk "$ARCON_HOME" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1048576}')"
    if [[ -n "$free_gb" ]] && (( free_gb < min_gb )); then
        log_warn "only ${free_gb} GiB free on $ARCON_HOME (recommended: ${min_gb} GiB)"
        [[ "${ARCON_INTERACTIVE}" == "1" ]] && { ui_confirm "Continue with low disk space" n || return 1; }
    fi

    if ! net_online; then
        log_error "no internet connectivity (checked DNS + HTTPS) — package operations would fail"
        [[ "${ARCON_INTERACTIVE}" == "1" ]] && ui_confirm "Continue offline anyway (most tasks will fail)" n || problems=$((problems + 1))
    fi

    if [[ "${HW_POWER:-unknown}" == battery ]]; then
        log_warn "the machine is running on battery; a long installation may be interrupted"
    fi

    pkg_init || problems=$((problems + 1))
    log_info "package manager: ${PKG_PROVIDER:-none} (catalog column: $(platform_catalog_column))"
    return "$problems"
}

# --------------------------------------------------------------- modes
_arcon_mode_list_runs() {
    ui_header "PREVIOUS RUNS"
    local out; out="$(state_list_runs)"
    [[ -z "$out" ]] && { ui_say "  (none)"; return 0; }
    printf '%s\n' "$out"
    local cur; cur="$(state_current_run 2>/dev/null || true)"
    [[ -n "$cur" ]] && ui_say "\n${YELLOW}unfinished run:${NC} $cur  (./setup.sh --resume)"
}

_arcon_mode_rollback() {
    local id="$ARCON_ROLLBACK_RUN"
    if [[ -z "$id" ]]; then
        id="$(state_current_run 2>/dev/null || true)"
        if [[ -z "$id" ]]; then
            # latest run that actually recorded changes (no-op re-runs are skipped)
            local d
            while IFS= read -r d; do
                [[ -s "$d/rollback.journal" ]] && { id="$(basename "$d")"; break; }
            done < <(printf '%s\n' "$ARCON_STATE_DIR"/runs/*/ | sort -r)
        fi
    fi
    [[ -z "$id" ]] && die 3 "no run found to roll back"
    state_open_run "$id"
    ui_header "ROLLBACK OF RUN $id"
    rollback_run "$ARCON_RUN_DIR" "$ARCON_ROLLBACK_PACKAGES"
}

_arcon_mode_install() {
    local resumed=0
    if (( ARCON_RESUME )); then
        local id; id="$(state_current_run 2>/dev/null || true)"
        [[ -z "$id" ]] && die 3 "no interrupted run to resume (see --list-runs)"
        state_open_run "$id"
        cfg_load_file "$ARCON_RUN_DIR/config.conf" "resume/$id" 1 || die 3 "cannot load the saved configuration"
        # CLI overrides must still win over the saved answers, so the user can
        # fix the cause of a failure (e.g. --set PKG_EXTRA=...) and resume.
        local kv
        for kv in "${ARCON_CLI_SETS[@]+"${ARCON_CLI_SETS[@]}"}"; do cfg_set_kv "$kv" cli; done
        [[ -n "$ARCON_MODULES_OVERRIDE" ]] && cfg_set MODULES "$ARCON_MODULES_OVERRIDE" cli
        cfg_validate || die 2 "configuration validation failed after resume overrides"
        log_info "resuming run $id"
        resumed=1
    else
        state_new_run
    fi

    (( resumed )) || cli_wizard
    cli_plan
    (( resumed )) && state_load_tasks

    cli_show_plan_and_confirm || { is_dry_run && plan_print; state_clear_current; return 0; }

    if is_dry_run; then
        # execute every task in dry-run mode: they only record plan entries
        local id
        for id in "${TASK_IDS[@]}"; do
            ARCON_MODULE="${TASK_MODULE[$id]}"; ARCON_TASK="$id"
            "${TASK_FN[$id]}" >/dev/null 2>&1 || true
        done
        ARCON_TASK=""; ARCON_MODULE=core
        plan_print
        ui_say "${DIM}Nothing above was applied. Re-run without --dry-run to apply it.${NC}"
        return 0
    fi

    cfg_dump "$ARCON_RUN_DIR/config.conf"
    hw_dump > "$ARCON_RUN_DIR/hardware.env" 2>/dev/null || true

    local failures=0
    task_run_all || failures=$?

    summary_print
    plan_save "$ARCON_RUN_DIR/plan.txt" 2>/dev/null || true

    if (( failures == 0 )); then
        state_clear_current
        reboot_prompt
        return 0
    fi
    log_error "$failures task(s) failed — the run is kept so it can be resumed"
    return 1
}

# --------------------------------------------------------------- entry
arcon_main() {
    ARCON_ARGV="$*"
    export ARCON_ARGV

    # bootstrap: logging/ui need to exist before anything can fail loudly
    # shellcheck source=/dev/null
    . "$ARCON_ROOT/core/log.sh"
    arcon_env_init
    arcon_source_all
    trap arcon_cleanup EXIT

    cli_parse "$@"
    ui_init_colors
    log_init "${ARCON_LOG_TARGET:-}"
    log_set_level "${ARCON_LOG_LEVEL:-info}"
    # shellcheck disable=SC2153  # ARCON_MODE is set by cli_parse (core/cli.sh)
    log_info "ArCoN ${ARCON_VERSION} starting (mode=$ARCON_MODE dry_run=${ARCON_DRY_RUN} interactive=${ARCON_INTERACTIVE})"

    platform_detect || die 3 "platform detection failed"
    hw_detect       || log_warn "hardware detection was incomplete"
    cli_load_config

    case "$ARCON_MODE" in
        list-runs)   _arcon_mode_list_runs; return 0 ;;
        show-config) cli_banner; ui_header "EFFECTIVE CONFIGURATION"; cfg_explain; return 0 ;;
    esac

    cli_banner

    case "$ARCON_MODE" in
        rollback) pkg_init || log_warn "package manager unusable — package rollback entries will fail"
                  _arcon_mode_rollback ;;
        reset)    pkg_init || die 5 "package manager unusable"
                  state_new_run; reset_run ;;
        install)  arcon_preflight || die 5 "preflight checks failed"; _arcon_mode_install ;;
        *)        die 2 "unknown mode: $ARCON_MODE" ;;
    esac
}
