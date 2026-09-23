#!/usr/bin/env bash
# ArCoN v3.0 -- modules/terminal.sh
# v2.5 "Sector 8 / Step A: Terminal emulator & theme".
#
# v2.5 → v3.0
#   * kitty themes from dexpota/kitty-themes with names like "Gruvbox Dark"
#     -> URL with a space, `curl -sS` stored the 404 page as theme.conf
#     → kovidgoyal/kitty-themes, exact file names, pinned commit, HTTP errors fail
#   * alacritty theme names wrong case (Dracula.toml vs dracula.toml) → exact names
#   * alacritty theme written over alacritty.toml (destroying user config)
#     → theme stored as themes/<name>.toml and imported from alacritty.toml
#   * gnome-terminal installed on Arch via pacman only        → catalog per platform
#   * no backups                                              → all writes journaled

ARCON_MODULE=terminal

# id|label|catalog id|platforms
TERM_EMULATORS=(
    "terminator|Terminator (Advanced Tiling)|terminator|linux"
    "kitty|Kitty (GPU Accelerated)|kitty|linux macos"
    "alacritty|Alacritty (Fastest)|alacritty|linux macos"
    "gnome-terminal|Gnome-Terminal|gnome-terminal|linux"
)
# verified against kovidgoyal/kitty-themes @ KITTY_THEMES_REF (file names are exact)
KITTY_THEMES=("Dracula" "Nord" "gruvbox-dark" "tokyo_night_night" "Cyberpunk-Neon")
# verified against alacritty/alacritty-theme @ ALACRITTY_THEMES_REF
ALACRITTY_THEMES=("dracula" "nord" "gruvbox_dark" "tokyo_night" "omni")

mod_terminal_wizard() {
    local opts=() e sup choice
    for e in "${TERM_EMULATORS[@]}"; do
        IFS='|' read -r id label _cid sup <<< "$e"
        [[ " $sup " == *" $OS_FAMILY "* ]] || continue
        opts+=("$id:$label")
    done
    ui_choose choice "$(cfg TERM_EMULATOR skip)" "=== TERMINAL EMULATOR SELECTION ===" "${opts[@]}" "skip:Skip"
    cfg_set TERM_EMULATOR "$choice" wizard
    case "$choice" in
        kitty)     _terminal_theme_wizard "${KITTY_THEMES[@]}" ;;
        alacritty) _terminal_theme_wizard "${ALACRITTY_THEMES[@]}" ;;
    esac
    return 0
}

_terminal_theme_wizard() {
    local opts=() t choice
    for t in "$@"; do opts+=("$t:$t"); done
    ui_choose choice "$1" "=== $(cfg TERM_EMULATOR | tr '[:lower:]' '[:upper:]') THEME SELECTION ===" "${opts[@]}" "skip:Skip"
    cfg_set TERM_THEME "$choice" wizard
}

mod_terminal_plan() {
    local t; t="$(cfg TERM_EMULATOR skip)"
    [[ "$t" == skip ]] && return 0
    local sup e
    for e in "${TERM_EMULATORS[@]}"; do
        IFS='|' read -r id _l _c sup <<< "$e"
        [[ "$id" == "$t" ]] || continue
        if [[ " $sup " != *" $OS_FAMILY "* ]]; then
            log_warn "$t is not available on $OS_ID — platform-inapplicable, skipped"; return 0
        fi
    done
    task_add terminal.install low "Install terminal emulator: $t" terminal_install
    case "$t" in
        kitty)      [[ "$(cfg TERM_THEME)" != skip ]] && task_add terminal.theme low "Apply kitty theme $(cfg TERM_THEME)" terminal_kitty_theme ;;
        alacritty)  [[ "$(cfg TERM_THEME)" != skip ]] && task_add terminal.theme low "Apply alacritty theme $(cfg TERM_THEME)" terminal_alacritty_theme ;;
        terminator)
            # the dotfiles module already installs configs/terminator/config;
            # only schedule it here when dotfiles is not part of this run
            if cfg_list_has MODULES dotfiles && cfg_bool DOTFILES_TERMINATOR yes; then
                log_debug "Terminator config is handled by the dotfiles module"
            else
                task_add terminal.theme low "Apply ArCoN Terminator config" dotfiles_terminator
            fi ;;
    esac
    return 0
}

terminal_install() { pkg_install_ids "$(cfg TERM_EMULATOR)"; }

_theme_valid() {
    local want="$1"; shift
    local t; for t in "$@"; do [[ "$t" == "$want" ]] && return 0; done
    log_error "unknown theme '$want' for $(cfg TERM_EMULATOR); valid: $*"
    return 1
}

terminal_kitty_theme() {
    local theme; theme="$(cfg TERM_THEME)"
    _theme_valid "$theme" "${KITTY_THEMES[@]}" || return 1
    local dir="$ARCON_HOME/.config/kitty" url dest="$ARCON_TMP/kitty-theme.conf"
    url="$(cfg KITTY_THEMES_REPO)/$(cfg KITTY_THEMES_REF)/themes/${theme}.conf"
    if is_dry_run; then
        plan_record FILE "$dir/theme.conf <- $url"
        plan_record FILE "$dir/kitty.conf: ensure 'include ./theme.conf' and JetBrainsMono Nerd Font"
        return 0
    fi
    fetch_to "$url" "$dest" || { log_error "kitty theme download failed: $url"; return 1; }
    grep -q 'color0' "$dest" || { log_error "downloaded file is not a kitty theme (upstream layout changed?)"; return 1; }
    fs_install_file "$dest" "$dir/theme.conf" || return 1
    [[ -f "$dir/kitty.conf" ]] || fs_write "$dir/kitty.conf" <<< "font_family JetBrainsMono Nerd Font"
    fs_append_once "$dir/kitty.conf" "include ./theme.conf" || return 1
    log_result "kitty theme $theme" PASS "$dir/theme.conf"
}

terminal_alacritty_theme() {
    local theme; theme="$(cfg TERM_THEME)"
    _theme_valid "$theme" "${ALACRITTY_THEMES[@]}" || return 1
    local dir="$ARCON_HOME/.config/alacritty" url dest="$ARCON_TMP/alacritty-theme.toml"
    url="$(cfg ALACRITTY_THEMES_REPO)/$(cfg ALACRITTY_THEMES_REF)/themes/${theme}.toml"
    if is_dry_run; then
        plan_record FILE "$dir/themes/${theme}.toml <- $url"
        plan_record FILE "$dir/alacritty.toml: import the theme (existing config preserved)"
        return 0
    fi
    fetch_to "$url" "$dest" || { log_error "alacritty theme download failed: $url"; return 1; }
    grep -q 'colors' "$dest" || { log_error "downloaded file is not an alacritty theme"; return 1; }
    fs_install_file "$dest" "$dir/themes/${theme}.toml" || return 1
    # alacritty >= 0.13 uses "general.import"; older uses top-level "import"
    local import_line="general.import = [\"~/.config/alacritty/themes/${theme}.toml\"]"
    if command -v alacritty >/dev/null 2>&1 && alacritty --version 2>/dev/null | awk '{split($2,v,"."); exit !(v[1]==0 && v[2]<13)}'; then
        import_line="import = [\"~/.config/alacritty/themes/${theme}.toml\"]"
    fi
    fs_set_kv "$dir/alacritty.toml" '^(general\.)?import *=' "$import_line" || return 1
    log_result "alacritty theme $theme" PASS "$dir/themes/${theme}.toml"
}
