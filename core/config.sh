#!/usr/bin/env bash
# ArCoN v3.0 -- core/config.sh
# Layered, *non-executing* configuration loader.
#
# Layers (later wins):
#   1. config/defaults.conf               (shipped defaults)
#   2. config/platform/<family>.conf      (linux | macos)
#   3. profiles/<profile>.conf            (--profile)
#   4. user file                          (~/.config/arcon/arcon.conf or --config)
#   5. CLI overrides                      (--set KEY=VALUE, and dedicated flags)
#
# Files use KEY=VALUE lines. Values are NEVER evaluated by the shell: no
# command substitution, no variable expansion. This closes the "sourced
# config = arbitrary code execution" class of bugs (security finding S-09).

[[ -n "${_ARCON_CONFIG_SH:-}" ]] && return 0
_ARCON_CONFIG_SH=1

declare -gA ARCON_CFG=()
declare -gA ARCON_CFG_SRC=()

# cfg_parse_line <line> -> sets _CFG_K/_CFG_V, returns 1 when not a setting.
_cfg_parse_line() {
    local line="$1"
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && return 1
    if [[ "$line" =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        _CFG_K="${BASH_REMATCH[1]}"
        _CFG_V="${BASH_REMATCH[2]}"
        # a value that is only a comment means "unset"
        [[ "$_CFG_V" == \#* ]] && _CFG_V=""
        # strip trailing inline comment " # ..." (only when preceded by space)
        _CFG_V="${_CFG_V%%[[:space:]]#*}"
        # trim trailing whitespace
        _CFG_V="${_CFG_V%"${_CFG_V##*[![:space:]]}"}"
        # strip one level of matching quotes
        if [[ "$_CFG_V" =~ ^\"(.*)\"$ || "$_CFG_V" =~ ^\'(.*)\'$ ]]; then
            _CFG_V="${BASH_REMATCH[1]}"
        fi
        return 0
    fi
    return 2
}

# cfg_load_file <path> <source-label> [required]
cfg_load_file() {
    local file="$1" label="${2:-$1}" required="${3:-0}" n=0 line rc
    if [[ ! -f "$file" ]]; then
        [[ "$required" == "1" ]] && { log_error "config file not found: $file"; return 1; }
        log_debug "config layer absent: $file"
        return 0
    fi
    if [[ ! -r "$file" ]]; then
        log_error "config file not readable: $file"
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        # (written so it also behaves under `set -e`, e.g. inside bats)
        rc=0; _cfg_parse_line "$line" || rc=$?
        if (( rc == 0 )); then
            ARCON_CFG["$_CFG_K"]="$_CFG_V"
            ARCON_CFG_SRC["$_CFG_K"]="$label:$n"
        elif (( rc == 2 )); then
            log_error "invalid config syntax at $file:$n: $line"
            return 1
        fi
    done < "$file"
    log_debug "loaded config layer $label ($file)"
}

# cfg_set <KEY> <VALUE> [source]
cfg_set() {
    [[ "$1" =~ ^[A-Z][A-Z0-9_]*$ ]] || { log_error "invalid config key: $1"; return 1; }
    ARCON_CFG["$1"]="$2"
    ARCON_CFG_SRC["$1"]="${3:-runtime}"
}

# cfg_set_kv "KEY=VALUE" [source]
cfg_set_kv() {
    local kv="$1"
    [[ "$kv" == *=* ]] || { log_error "--set expects KEY=VALUE, got: $kv"; return 1; }
    cfg_set "${kv%%=*}" "${kv#*=}" "${2:-cli}"
}

# cfg <KEY> [default]   -> prints value
cfg() {
    if [[ -n "${ARCON_CFG[$1]+x}" ]]; then
        printf '%s' "${ARCON_CFG[$1]}"
    else
        printf '%s' "${2:-}"
    fi
}

# cfg_bool <KEY> [default] -> exit 0 when truthy (yes/true/1/on)
cfg_bool() {
    local v; v="$(cfg "$1" "${2:-no}")"
    case "${v,,}" in yes|true|1|on|y) return 0 ;; *) return 1 ;; esac
}

# cfg_list_has <KEY> <item>  -> comma/space separated list membership
cfg_list_has() {
    local item
    for item in $(cfg "$1" | tr ',' ' '); do
        [[ "$item" == "$2" ]] && return 0
    done
    return 1
}

# cfg_list <KEY> -> one item per line
cfg_list() { printf '%s\n' "$(cfg "$1")" | tr ',' ' ' | tr -s ' ' '\n' | sed '/^$/d'; }

# cfg_dump [file] -> write effective config (used by resume)
cfg_dump() {
    local out="${1:-/dev/stdout}" k
    {
        printf '# ArCoN effective configuration (generated)\n'
        for k in $(printf '%s\n' "${!ARCON_CFG[@]}" | sort); do
            printf '%s=%s\n' "$k" "${ARCON_CFG[$k]}"
        done
    } > "$out"
}

# cfg_explain -> KEY=VALUE  (source) table for --show-config
cfg_explain() {
    local k
    for k in $(printf '%s\n' "${!ARCON_CFG[@]}" | sort); do
        printf '%-28s %-32s %s\n' "$k" "${ARCON_CFG[$k]}" "(${ARCON_CFG_SRC[$k]:-?})"
    done
}

# cfg_validate -> checks enumerated keys; returns number of problems
cfg_validate() {
    local problems=0 k v allowed
    local -A enums=(
        [GAMING_GPU]="auto nvidia amd intel skip"
        [HYPR_THEME]="none default ax-shell hyde ml4w jakoolit"
        [TERM_EMULATOR]="skip terminator kitty alacritty gnome-terminal"
        [SHELL_TARGET]="skip zsh fish bash"
        [SHELL_ZSH_THEME]="agnoster robbyrussell bira powerlevel10k"
        [SHELL_STARSHIP_PRESET]="default pastel-powerline tokyo-night pure-preset gruvbox-rainbow"
        [BLACKARCH]="no enable core full remove"
        [AUR_HELPER]="yay paru"
    )
    for k in "${!enums[@]}"; do
        v="$(cfg "$k")"
        [[ -z "$v" ]] && continue
        allowed=" ${enums[$k]} "
        if [[ "$allowed" != *" $v "* ]]; then
            log_error "config $k='$v' is invalid (allowed:${allowed% }) [${ARCON_CFG_SRC[$k]:-?}]"
            problems=$((problems + 1))
        fi
    done
    v="$(cfg MIN_DISK_GB 10)"
    [[ "$v" =~ ^[0-9]+$ ]] || { log_error "MIN_DISK_GB must be an integer"; problems=$((problems + 1)); }
    return "$problems"
}
