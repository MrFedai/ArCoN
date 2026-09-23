#!/usr/bin/env bash
# ArCoN v3.0 -- modules/dotfiles.sh
# v2.5 "Sector 7: Config Restoration (Terminator, Wallpapers)".
#
# v2.5 → v3.0
#   * relative paths (broken after Hyprland `cd`)   → $ARCON_ROOT absolute paths
#   * existing ~/.config/terminator/config overwritten → backup + rollback; unchanged files skipped
#   * Linux only in practice                          → wallpapers on Linux + macOS (~/Pictures/wallp)

ARCON_MODULE=dotfiles

mod_dotfiles_wizard() {
    if ui_confirm "Restore Configs (Terminator, Wallpapers)" y; then
        cfg_set DOTFILES_WALLPAPERS yes wizard; cfg_set DOTFILES_TERMINATOR yes wizard
    else
        cfg_set DOTFILES_WALLPAPERS no wizard; cfg_set DOTFILES_TERMINATOR no wizard
    fi
    return 0
}

mod_dotfiles_plan() {
    cfg_bool DOTFILES_WALLPAPERS yes && task_add dotfiles.wallpapers low "Copy wallpapers to ~/Pictures/wallp" dotfiles_wallpapers
    if cfg_bool DOTFILES_TERMINATOR yes; then
        if is_linux; then task_add dotfiles.terminator low "Restore Terminator config" dotfiles_terminator
        else log_info "Terminator config: Linux only (Terminator is not packaged for $OS_ID) — skipped"; fi
    fi
    return 0
}

dotfiles_wallpapers() {
    [[ -d "$ARCON_ROOT/wallp" ]] || { log_warn "wallp/ directory missing"; return "$TASK_SKIP"; }
    fs_copy_tree "$ARCON_ROOT/wallp" "$ARCON_HOME/Pictures/wallp"
}

dotfiles_terminator() {
    local src="$ARCON_ROOT/configs/terminator/config"
    [[ -f "$src" ]] || { log_warn "configs/terminator/config not found"; return "$TASK_SKIP"; }
    fs_install_file "$src" "$ARCON_HOME/.config/terminator/config"
}
