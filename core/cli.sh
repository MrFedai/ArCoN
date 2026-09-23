#!/usr/bin/env bash
# ArCoN v3.0 -- core/cli.sh
# Argument parsing, banner, wizard/plan/execute orchestration.
#
# v2.5 had no arguments at all: it was interactive-only and always started from
# the top. v3.0 supports interactive, non-interactive, dry-run, profile, resume,
# rollback, verbose/debug and reset modes with the same code path.

[[ -n "${_ARCON_CLI_SH:-}" ]] && return 0
_ARCON_CLI_SH=1

ARCON_VERSION="3.0.0"
# arcon_profiles <sep> -> shipped profile names joined by <sep>
arcon_profiles() {
    local f out=""
    for f in "$ARCON_ROOT"/profiles/*.conf; do [[ -e "$f" ]] && out="${out:+$out$1}$(basename "$f" .conf)"; done
    printf '%s' "$out"
}

ARCON_MODE=install          # install | reset | rollback | list-runs | show-config | plan-only
ARCON_PROFILE=""
ARCON_USER_CONFIG=""
ARCON_RESUME=0
ARCON_ROLLBACK_PACKAGES=0
ARCON_ROLLBACK_RUN=""
ARCON_ASSUME_DESTRUCTIVE=0
ARCON_KEEP_GOING=0
ARCON_MODULES_OVERRIDE=""

# Module execution order is fixed (dependencies), selection is not.
ARCON_MODULE_ORDER=(base packages gnome gaming blackarch hyprland dotfiles terminal shell security optimize cleanup)

usage() {
    cat <<EOF
ArCoN v${ARCON_VERSION} — Arch/Debian/Ubuntu/Fedora/openSUSE/macOS setup & hardening toolkit

Usage: ./setup.sh [options]

Modes
  (no options)              interactive wizard (v2.5 behaviour)
  --profile NAME            use a profile: $(arcon_profiles '|')
  --dry-run                 show everything that would change, change nothing
  --resume                  continue the last interrupted run
  --rollback [RUN_ID]       undo the changes of a run (default: last run)
  --rollback-packages       also remove packages installed by that run
  --reset                   Smart Factory Reset (configs, optionally packages)
  --list-runs               list previous runs and their state
  --show-config             print the effective configuration and its sources

Behaviour
  -y, --non-interactive     never ask; use profile/config defaults
  --i-understand-destructive  allow destructive steps non-interactively
  --keep-going              continue after a failed task
  --modules a,b,c           run only these modules ($(IFS=,; echo "${ARCON_MODULE_ORDER[*]}"))
  --set KEY=VALUE           override a single configuration key (repeatable)
  --config FILE             load an additional configuration file
  -v, --verbose             show command output on the terminal
  -d, --debug               debug logging (implies --verbose)
  --no-color                disable ANSI colours
  --log FILE                write the log to FILE
  -h, --help                this help
  --version                 print version

Examples
  ./setup.sh --dry-run
  ./setup.sh --profile gaming
  ./setup.sh --profile minimal -y
  ./setup.sh --resume
  ./setup.sh --rollback
EOF
}

cli_parse() {
    local sets=()
    while (( $# )); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --version) printf 'ArCoN %s\n' "$ARCON_VERSION"; exit 0 ;;
            --dry-run) ARCON_DRY_RUN=1 ;;
            --profile) ARCON_PROFILE="${2:?--profile needs a name}"; shift ;;
            --profile=*) ARCON_PROFILE="${1#*=}" ;;
            --config) ARCON_USER_CONFIG="${2:?--config needs a file}"; shift ;;
            --config=*) ARCON_USER_CONFIG="${1#*=}" ;;
            --set) sets+=("${2:?--set needs KEY=VALUE}"); shift ;;
            --set=*) sets+=("${1#*=}") ;;
            --modules) ARCON_MODULES_OVERRIDE="${2:?--modules needs a list}"; shift ;;
            --modules=*) ARCON_MODULES_OVERRIDE="${1#*=}" ;;
            -y|--non-interactive|--yes) ARCON_INTERACTIVE=0 ;;
            --i-understand-destructive) ARCON_ASSUME_DESTRUCTIVE=1 ;;
            --keep-going) ARCON_KEEP_GOING=1 ;;
            --resume) ARCON_RESUME=1 ;;
            --rollback)
                ARCON_MODE=rollback
                [[ -n "${2:-}" && "$2" != -* ]] && { ARCON_ROLLBACK_RUN="$2"; shift; } ;;
            --rollback-packages) ARCON_ROLLBACK_PACKAGES=1 ;;
            --reset) ARCON_MODE=reset ;;
            --list-runs) ARCON_MODE=list-runs ;;
            --show-config) ARCON_MODE=show-config ;;
            -v|--verbose) ARCON_VERBOSE=1 ;;
            -d|--debug) ARCON_VERBOSE=1; ARCON_LOG_LEVEL=debug ;;
            --no-color) ARCON_NO_COLOR=1 ;;
            --log) ARCON_LOG_TARGET="${2:?--log needs a file}"; shift ;;
            --log=*) ARCON_LOG_TARGET="${1#*=}" ;;
            *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done
    ARCON_CLI_SETS=("${sets[@]}")
    export ARCON_DRY_RUN ARCON_INTERACTIVE ARCON_VERBOSE ARCON_LOG_LEVEL ARCON_NO_COLOR ARCON_ASSUME_DESTRUCTIVE ARCON_KEEP_GOING
}

cli_banner() {
    ui_say ""
    ui_say "${CYAN}    ___         ______      _   __${NC}"
    ui_say "${CYAN}   /   |  _____/ ____/___  / | / /${NC}   ${BOLD}ArCoN v${ARCON_VERSION}${NC}"
    ui_say "${CYAN}  / /| | / ___/ /   / __ \\/  |/ / ${NC}   cross-platform setup & hardening"
    ui_say "${CYAN} / ___ |/ /  / /___/ /_/ / /|  /  ${NC}   ${DIM}log: $(log_file)${NC}"
    ui_say "${CYAN}/_/  |_/_/   \\____/\\____/_/ |_/   ${NC}"
    ui_say ""
    hw_summary
    is_dry_run && ui_say "\n${YELLOW}${BOLD}DRY-RUN MODE — nothing will be changed${NC}"
    ui_say ""
}

cli_load_config() {
    cfg_load_file "$ARCON_ROOT/config/defaults.conf" defaults 1 || die 2 "cannot load defaults"
    cfg_load_file "$ARCON_ROOT/config/platform/${OS_FAMILY}.conf" "platform/$OS_FAMILY" || die 2 "cannot load platform config"
    if [[ -n "$ARCON_PROFILE" ]]; then
        local pf="$ARCON_ROOT/profiles/${ARCON_PROFILE}.conf"
        [[ -f "$pf" ]] || die 2 "unknown profile '$ARCON_PROFILE' (available: $(arcon_profiles ','))"
        cfg_load_file "$pf" "profile/$ARCON_PROFILE" 1 || die 2 "cannot load profile"
    fi
    cfg_load_file "${XDG_CONFIG_HOME:-$ARCON_HOME/.config}/arcon/arcon.conf" user || die 2 "cannot load user config"
    [[ -n "$ARCON_USER_CONFIG" ]] && { cfg_load_file "$ARCON_USER_CONFIG" "cli-config" 1 || die 2 "cannot load $ARCON_USER_CONFIG"; }
    local kv
    for kv in "${ARCON_CLI_SETS[@]+"${ARCON_CLI_SETS[@]}"}"; do cfg_set_kv "$kv" cli || die 2 "invalid --set"; done
    [[ -n "$ARCON_MODULES_OVERRIDE" ]] && cfg_set MODULES "$ARCON_MODULES_OVERRIDE" cli
    cfg_validate || die 2 "configuration validation failed ($? problem(s))"
}

# modules selected, in dependency order
cli_modules() {
    local m
    for m in "${ARCON_MODULE_ORDER[@]}"; do cfg_list_has MODULES "$m" && printf '%s\n' "$m"; done
}

cli_wizard() {
    [[ "${ARCON_INTERACTIVE:-1}" == "1" ]] || return 0
    # a profile (other than custom) means the user already answered everything
    if [[ -n "$ARCON_PROFILE" && "$ARCON_PROFILE" != custom ]]; then
        log_info "profile '$ARCON_PROFILE' selected — skipping the interactive wizard"
        return 0
    fi
    if [[ -z "$ARCON_PROFILE" ]]; then
        local choice opts=() p desc
        for p in "$ARCON_ROOT"/profiles/*.conf; do
            desc="$(grep -m1 '^PROFILE_DESCRIPTION=' "$p" | cut -d= -f2-)"
            opts+=("$(basename "$p" .conf):$(basename "$p" .conf) — ${desc}")
        done
        ui_choose choice custom "SELECT AN INSTALLATION PROFILE" "${opts[@]}"
        if [[ "$choice" != custom ]]; then
            ARCON_PROFILE="$choice"
            cfg_load_file "$ARCON_ROOT/profiles/${choice}.conf" "profile/$choice" 1 || die 2 "cannot load profile"
            local kv
            for kv in "${ARCON_CLI_SETS[@]+"${ARCON_CLI_SETS[@]}"}"; do cfg_set_kv "$kv" cli; done
            log_info "profile '$choice' selected"
            return 0
        fi
    fi
    local m
    for m in $(cli_modules); do
        ui_section "$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')"
        declare -F "mod_${m}_wizard" >/dev/null && "mod_${m}_wizard"
    done
}

cli_plan() {
    local m
    for m in $(cli_modules); do
        ARCON_MODULE="$m"
        declare -F "mod_${m}_plan" >/dev/null && { "mod_${m}_plan" || log_warn "planning of module $m reported a problem"; }
    done
    ARCON_MODULE=core
}

cli_show_plan_and_confirm() {
    ui_header "EXECUTION PLAN"
    task_print_queue
    local risky=0 id
    for id in "${TASK_IDS[@]}"; do [[ "${TASK_RISK[$id]}" == high ]] && risky=$((risky + 1)); done
    (( risky > 0 )) && ui_say "\n${YELLOW}$risky high-risk task(s) are included; each asks for confirmation before it runs.${NC}"
    ui_say ""
    (( ${#TASK_IDS[@]} == 0 )) && { ui_say "${GREEN}Nothing to do — the system already matches the selected configuration.${NC}"; return 1; }
    is_dry_run && return 0
    ui_confirm "Proceed with these ${#TASK_IDS[@]} task(s)" y || { log_info "cancelled by user before any change"; return 1; }
}
