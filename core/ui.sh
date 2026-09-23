#!/usr/bin/env bash
# ArCoN v3.0 -- core/ui.sh
# Terminal UI: colors, banners, prompts, menus and the v2.5 progress bar.
#
# Every prompt respects non-interactive mode (ARCON_INTERACTIVE=0): the
# default answer is used and logged, so unattended runs are deterministic.

[[ -n "${_ARCON_UI_SH:-}" ]] && return 0
_ARCON_UI_SH=1

ui_init_colors() {
    if [[ "${ARCON_NO_COLOR:-0}" == "1" || ! -t 1 ]]; then
        GREEN=''; BLUE=''; YELLOW=''; RED=''; CYAN=''; MAGENTA=''; BOLD=''; DIM=''; GRAY=''; NC=''
    else
        # v2.5 used CYAN/BOLD/DIM/GRAY/MAGENTA without defining them (bug #A-03).
        GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
        CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; GRAY='\033[0;90m'; NC='\033[0m'
    fi
}
ui_init_colors

ui_say()     { printf '%b\n' "$*"; }
ui_header()  {
    local title="$1"
    ui_say "\n${BLUE}========================================${NC}"
    ui_say "${GREEN}${BOLD}  ${title}${NC}"
    ui_say "${BLUE}========================================${NC}"
}
ui_section() { ui_say "\n${CYAN}--- $* ---${NC}"; }

# _ui_read <varname> : read one line from the controlling terminal.
_ui_read() {
    local __v
    if [[ -n "${ARCON_INPUT_FD:-}" ]]; then
        IFS= read -r -u "$ARCON_INPUT_FD" __v || __v=""
    else
        IFS= read -r __v || __v=""
    fi
    printf -v "$1" '%s' "$__v"
}

# ui_confirm <question> [default y|n]
# Returns 0 for yes, 1 for no. Non-interactive => default.
ui_confirm() {
    local q="$1" def="${2:-n}" ans hint
    [[ "$def" == "y" ]] && hint="Y/n" || hint="y/N"
    if [[ "${ARCON_INTERACTIVE:-1}" != "1" ]]; then
        log_debug "non-interactive: '$q' -> default '$def'"
        [[ "$def" == "y" ]]
        return
    fi
    while true; do
        printf '%b' "${YELLOW}>> ${q}? (${hint}): ${NC}"
        _ui_read ans
        ans="${ans,,}"
        [[ -z "$ans" ]] && ans="$def"
        case "$ans" in
            y|yes|e|evet) return 0 ;;
            n|no|h|hayir|hayır) return 1 ;;
            *) ui_say "${RED}Please answer y or n.${NC}" ;;
        esac
    done
}

# ui_confirm_word <question> <word>
# Destructive confirmation: the user must type <word> exactly.
# Non-interactive: only passes when ARCON_ASSUME_DESTRUCTIVE=1.
ui_confirm_word() {
    local q="$1" word="$2" ans
    if [[ "${ARCON_INTERACTIVE:-1}" != "1" ]]; then
        [[ "${ARCON_ASSUME_DESTRUCTIVE:-0}" == "1" ]] && return 0
        log_warn "non-interactive: destructive step '$q' refused (use --i-understand-destructive)"
        return 1
    fi
    printf '%b' "${RED}>> ${q} — type '${word}' to confirm: ${NC}"
    _ui_read ans
    [[ "$ans" == "$word" ]]
}

# ui_choose <varname> <default> <prompt> <option1> [option2 ...]
# Options are "value:Label" pairs. Stores the chosen value in <varname>.
ui_choose() {
    local __var="$1" def="$2" prompt="$3"; shift 3
    local opts=("$@") i ans val
    if [[ "${ARCON_INTERACTIVE:-1}" != "1" ]]; then
        printf -v "$__var" '%s' "$def"
        log_debug "non-interactive: '$prompt' -> '$def'"
        return 0
    fi
    ui_say "\n${CYAN}${prompt}${NC}"
    for i in "${!opts[@]}"; do
        val="${opts[$i]%%:*}"
        local mark=""
        [[ "$val" == "$def" ]] && mark=" ${DIM}(default)${NC}"
        ui_say "  [$((i + 1))] ${opts[$i]#*:}${mark}"
    done
    while true; do
        printf '%b' "${YELLOW}Select [1-${#opts[@]}]: ${NC}"
        _ui_read ans
        if [[ -z "$ans" ]]; then printf -v "$__var" '%s' "$def"; return 0; fi
        if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#opts[@]} )); then
            printf -v "$__var" '%s' "${opts[$((ans - 1))]%%:*}"
            return 0
        fi
        ui_say "${RED}Invalid option.${NC}"
    done
}

# ui_progress <current> <total> <label>  (v2.5 visual bar, non-destructive redraw)
ui_progress() {
    local cur="$1" total="$2" label="$3" width=40
    (( total <= 0 )) && total=1
    local pct=$(( cur * 100 / total ))
    local filled=$(( pct * width / 100 )) empty
    empty=$(( width - filled ))
    local bar_f bar_e
    bar_f=$(printf '%*s' "$filled" '' | tr ' ' '#')
    bar_e=$(printf '%*s' "$empty" '' | tr ' ' '.')
    if [[ -t 1 && "${ARCON_NO_COLOR:-0}" != "1" ]]; then
        bar_f=$(printf '%*s' "$filled" ''); bar_f=${bar_f// /█}
        bar_e=$(printf '%*s' "$empty" '');  bar_e=${bar_e// /░}
        printf '\r\033[K%b[%b%s%b%s%b] %3d%%%b %s' "$BOLD" "$GREEN" "$bar_f" "$GRAY" "$bar_e" "$NC$BOLD" "$pct" "$NC" "$label"
        (( cur >= total )) && printf '\n'
    else
        printf '[%s%s] %3d%% %s\n' "$bar_f" "$bar_e" "$pct" "$label"
    fi
}

# ui_table <rows...>  rows are "col1|col2|col3"
ui_table() {
    if command -v column >/dev/null 2>&1; then
        printf '%b\n' "$@" | column -t -s '|'
    else
        # portable fallback (busybox/minimal images have no column(1)):
        # pad the first field, keep the rest as-is
        printf '%b\n' "$@" | awk -F'|' '
            { for (i = 1; i <= NF; i++) { if (length($i) > w[i]) w[i] = length($i) } lines[NR] = $0 }
            END { for (n = 1; n <= NR; n++) { split(lines[n], f, "|"); out = ""
                    for (i = 1; i <= length(w); i++) { if (f[i] == "") continue
                        out = out sprintf("%-*s  ", w[i], f[i]) }
                    sub(/ +$/, "", out); print out } }'
    fi
}

# ui_confirm_set <KEY> <default y|n> <question>
# Ask a yes/no question and store yes|no in the config (wizard layer).
ui_confirm_set() {
    local key="$1" def="$2"; shift 2
    if ui_confirm "$*" "$def"; then cfg_set "$key" yes wizard; else cfg_set "$key" no wizard; fi
    return 0
}
