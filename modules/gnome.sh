#!/usr/bin/env bash
# ArCoN v3.0 -- modules/gnome.sh
# v2.5 "Sector 2A: GNOME settings (theme + config) + debloat". Linux + GNOME only.
#
# v2.5 → v3.0
#   * gno.conf pointed at wallp/default.jpg (file never existed) → GNOME_WALLPAPER (default Katana.jpg)
#   * /home/$USER hard-coded                                  → real $HOME of the invoking user
#   * no backup before `dconf load /`                         → full `dconf dump /` backup + rollback
#   * adw-gtk-theme-git from AUR                              → official adw-gtk-theme (Arch extra)
#   * debloat used regex `pacman -Qs` (false positives)       → exact installed check
#   * CWD-relative configs/ paths                             → $ARCON_ROOT absolute paths
# macOS/Windows: platform-inapplicable (no GNOME) — documented in FEATURE-PARITY.md.

ARCON_MODULE=gnome
GNOME_BLOAT=(gnome-tour gnome-weather gnome-maps gnome-contacts gnome-music epiphany)

gnome_present() {
    is_linux || return 1
    command -v gnome-shell >/dev/null 2>&1 || [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]]
}

mod_gnome_wizard() {
    gnome_present || { log_info "GNOME not detected — GNOME step not offered"; cfg_set GNOME_APPLY no wizard; return 0; }
    if ui_confirm "Apply GNOME Settings (Theme + Config)" y; then
        cfg_set GNOME_APPLY yes wizard
        local walls=() w choice
        for w in "$ARCON_ROOT"/wallp/*; do [[ -f "$w" ]] && walls+=("$(basename "$w"):$(basename "$w")"); done
        (( ${#walls[@]} )) && { ui_choose choice "$(cfg GNOME_WALLPAPER Katana.jpg)" "Select wallpaper:" "${walls[@]}"; cfg_set GNOME_WALLPAPER "$choice" wizard; }
    else
        cfg_set GNOME_APPLY no wizard
    fi
    ui_confirm "Remove GNOME Bloatware (${GNOME_BLOAT[*]})" n && cfg_set GNOME_DEBLOAT yes wizard || cfg_set GNOME_DEBLOAT no wizard
    return 0
}

mod_gnome_plan() {
    if ! gnome_present; then
        { cfg_bool GNOME_APPLY || cfg_bool GNOME_DEBLOAT; } && log_warn "GNOME settings requested but GNOME is not installed — skipped"
        return 0
    fi
    if cfg_bool GNOME_APPLY; then
        task_add gnome.deps low "Install GNOME theme/clipboard dependencies" gnome_deps
        task_add gnome.apply medium "Apply gno.conf (dconf backup kept for rollback)" gnome_apply
    fi
    cfg_bool GNOME_DEBLOAT && task_add gnome.debloat medium "Remove GNOME bloatware (${GNOME_BLOAT[*]})" gnome_debloat
    return 0
}

gnome_deps() { pkg_install_ids wl-clipboard adw-gtk-theme gnome-shell-extension-clipboard-indicator; }

# render gno.conf for this user: home path + chosen wallpaper
gnome_render_conf() {
    local wall; wall="$(cfg GNOME_WALLPAPER Katana.jpg)"
    sed -e "s|/home/USER_PLACEHOLDER|${ARCON_HOME}|g" \
        -e "s|/Pictures/wallp/default.jpg|/Pictures/wallp/${wall}|g" \
        "$ARCON_ROOT/configs/gno.conf"
}

gnome_apply() {
    local src="$ARCON_ROOT/configs/gno.conf" wall rendered
    [[ -f "$src" ]] || { log_error "configs/gno.conf not found"; return 1; }
    command -v dconf >/dev/null 2>&1 || is_dry_run || { log_error "dconf not installed"; return 1; }
    wall="$(cfg GNOME_WALLPAPER Katana.jpg)"
    [[ -f "$ARCON_ROOT/wallp/$wall" ]] || { log_error "wallpaper '$wall' not found in wallp/"; return 1; }
    # the referenced wallpaper must exist on disk (v2.5 referenced a missing file)
    fs_install_file "$ARCON_ROOT/wallp/$wall" "$ARCON_HOME/Pictures/wallp/$wall" || return 1

    rendered="$ARCON_TMP/gno.rendered.conf"
    gnome_render_conf > "$rendered"
    if is_dry_run; then
        plan_record SETTING "dconf reset /org/gnome/desktop/app-folders/ and load $(grep -c '^\[' "$rendered") dconf sections from configs/gno.conf (wallpaper $wall)"
        return 0
    fi
    [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || log_warn "no D-Bus session found; run ArCoN from your GNOME session (not via sudo) if dconf fails"
    local dump; dump="$(rb_backup_dir)/dconf-full.ini"; mkdir -p "$(dirname "$dump")"
    dconf dump / > "$dump" || { log_error "dconf backup failed — not applying settings"; return 1; }
    rb_add DCONF / "$dump"
    x_run SETTING "reset GNOME app folders" -- dconf reset -f /org/gnome/desktop/app-folders/ || return 1
    x_run SETTING "load gno.conf" -- sh -c 'dconf load / < "$1"' _ "$rendered" || { log_error "gno.conf rejected by dconf (syntax?) — restore with: ./setup.sh --rollback"; return 1; }
    # verify one representative key
    local got; got="$(dconf read /org/gnome/desktop/interface/gtk-theme 2>/dev/null)"
    [[ "$got" == "'adw-gtk3-dark'" ]] && log_result "GNOME settings" PASS "gtk-theme=$got" || { log_result "GNOME settings" FAIL "gtk-theme=$got"; return 1; }
}

gnome_debloat() {
    local present=() p
    for p in "${GNOME_BLOAT[@]}"; do pkg_is_installed "$p" && present+=("$p"); done
    (( ${#present[@]} )) || { log_info "no GNOME bloatware installed"; return 0; }
    ui_say "  will remove: ${present[*]}"
    pkg_remove "${present[@]}"
}
