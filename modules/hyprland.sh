#!/usr/bin/env bash
# ArCoN v3.0 -- modules/hyprland.sh
# v2.5 "Sector 6: Hyprland & Desktop".
#
# v2.5 → v3.0
#   * all packages installed via yay (they are official)   → package facade (pacman/apt/dnf/zypper)
#   * `cd` into theme dirs never returned (broke later
#     relative paths configs/ wallp/)                      → subshells, absolute $ARCON_ROOT paths
#   * `curl -s ... -o install_ax.sh` saved 404 pages       → git clone of the upstream repository
#   * dead installers: Hyprdots (moved to HyDE-Project),
#     ML4W installer.sh (removed), JaKooLit Hyprland-Dots
#     install.sh (moved to Arch-Hyprland)                  → current upstream entry points (verified 2026-09)
#   * Ax-Shell upstream archived (read-only)               → still offered, marked deprecated
#   * default ArCoN config sourced Ax-Shell files that
#     only exist with Ax-Shell                             → fallback colours + missing sources commented
#   * config dir moved away with `mv` (no restore path)    → journaled backup, --rollback restores
# Third-party theme installers are external code: ArCoN shows the commit, asks for
# confirmation, optionally opens the script in $EDITOR (v2.5 "edit/debloat"), and
# runs it in a subshell. They are never piped from curl into a shell.

ARCON_MODULE=hyprland

# id|label|repo|branch|installer (relative)|supported OS ids|note
HYPR_THEMES=(
    "default|ArCoN default configs (configs/hypr)|||||"
    "hyde|HyDE (successor of prasanthrangan/hyprdots)|https://github.com/HyDE-Project/HyDE|master|Scripts/install.sh|arch|heavy: replaces GTK/Qt/shell/SDDM/GRUB theming"
    "jakoolit|JaKooLit Arch-Hyprland (maintained by LinuxBeginnings)|https://github.com/LinuxBeginnings/Arch-Hyprland|main|install.sh|arch|installs pipewire, may remove pulseaudio"
    "ml4w|ML4W OS dotfiles (stable)|https://github.com/mylinuxforwork/dotfiles|main|@https://ml4w.com/os/stable|arch fedora opensuse|bootstrap script downloaded, shown, then executed"
    "ax-shell|Ax-Shell (DEPRECATED: upstream archived)|https://github.com/Axenide/Ax-Shell|main|install.sh|arch|no further upstream fixes"
)

_hypr_theme_field() {
    local id="$1" idx="$2" t
    for t in "${HYPR_THEMES[@]}"; do
        [[ "${t%%|*}" == "$id" ]] || continue
        local IFS='|'; local -a f; read -r -a f <<< "$t"; printf '%s' "${f[$idx]:-}"; return 0
    done
    return 1
}

mod_hyprland_wizard() {
    is_linux || return 0
    if ! ui_confirm "Install Hyprland Environment" "$(cfg_bool HYPRLAND && echo y || echo n)"; then
        cfg_set HYPRLAND no wizard; return 0
    fi
    cfg_set HYPRLAND yes wizard
    local opts=() t id choice
    for t in "${HYPR_THEMES[@]}"; do
        id="${t%%|*}"
        local sup; sup="$(_hypr_theme_field "$id" 5)"
        [[ -z "$sup" || " $sup " == *" $OS_ID "* ]] || continue
        opts+=("$id:$(_hypr_theme_field "$id" 1)")
    done
    opts+=("none:Skip theme (vanilla Hyprland)")
    ui_choose choice "$(cfg HYPR_THEME default)" "SELECT A HYPRLAND THEME (DOTFILES)" "${opts[@]}"
    cfg_set HYPR_THEME "$choice" wizard
    if [[ "$choice" != default && "$choice" != none ]]; then
        ui_confirm "Edit/debloat the installer script before running" n && cfg_set HYPR_EDIT_INSTALLER yes wizard
    fi
    return 0
}

mod_hyprland_plan() {
    cfg_bool HYPRLAND || return 0
    if ! is_linux; then log_warn "Hyprland is Linux-only — platform-inapplicable on $OS_ID"; return 0; fi
    task_add hyprland.packages low "Install Hyprland packages" hyprland_packages
    local theme; theme="$(cfg HYPR_THEME default)"
    case "$theme" in
        none) ;;
        default) task_add hyprland.config low "Install ArCoN Hyprland configs (backup kept)" hyprland_default_config ;;
        *)
            local sup; sup="$(_hypr_theme_field "$theme" 5)" || { log_error "unknown HYPR_THEME '$theme'"; return 1; }
            if [[ " $sup " != *" $OS_ID "* ]]; then
                log_warn "theme '$theme' supports only: $sup — skipped on $OS_ID (using ArCoN default configs)"
                task_add hyprland.config low "Install ArCoN Hyprland configs (backup kept)" hyprland_default_config
            else
                task_add hyprland.theme high "Run third-party theme installer: $theme" hyprland_theme
            fi ;;
    esac
    return 0
}

hyprland_packages() {
    local ids; mapfile -t ids < <(catalog_group hyprland)
    pkg_install_ids "${ids[@]}" terminator
}

# copy configs/hypr, repairing references to Ax-Shell files that are absent
hyprland_default_config() {
    local dest="$ARCON_HOME/.config/hypr" f axdir="$ARCON_HOME/.config/Ax-Shell/config/hypr"
    local stage="$ARCON_TMP/hypr"; rm -rf "$stage"; mkdir -p "$stage"
    cp "$ARCON_ROOT"/configs/hypr/* "$stage/"
    if [[ ! -f "$axdir/colors.conf" ]]; then
        sed -i "s|^source = ~/.config/Ax-Shell/config/hypr/colors.conf|source = ~/.config/hypr/arcon-colors.conf|" "$stage/hyprlock.conf"
    else
        rm -f "$stage/arcon-colors.conf"
    fi
    if [[ ! -f "$axdir/ax-shell.conf" ]]; then
        sed -i "s|^source = ~/.config/Ax-Shell/config/hypr/ax-shell.conf|# (ArCoN: Ax-Shell not installed) source = ~/.config/Ax-Shell/config/hypr/ax-shell.conf|" "$stage/hyprland.conf"
    fi
    for f in "$stage"/*; do
        fs_install_file "$f" "$dest/$(basename "$f")" || return 1
    done
    log_result "Hyprland configs" PASS "$dest"
}

hyprland_theme() {
    local theme repo branch inst note
    theme="$(cfg HYPR_THEME)"
    repo="$(_hypr_theme_field "$theme" 2)"; branch="$(_hypr_theme_field "$theme" 3)"
    inst="$(_hypr_theme_field "$theme" 4)"; note="$(_hypr_theme_field "$theme" 6)"
    local dir="$ARCON_HOME/.local/share/arcon/themes/$theme"
    [[ "$theme" == ax-shell ]] && dir="$ARCON_HOME/.config/Ax-Shell"   # Ax-Shell expects this path
    [[ "$theme" == hyde ]] && log_warn "HyDE: create a restore point (e.g. Timeshift) first — upstream recommendation"
    [[ -n "$note" ]] && log_warn "$theme: $note"

    if is_dry_run; then
        plan_record COMMAND "git clone --depth 1 -b $branch $repo $dir"
        plan_record COMMAND "run third-party installer $inst ($theme) — external code, confirmation required"
        return 0
    fi
    # backup current hypr config (v2.5 moved it to hypr.bak_<ts>)
    [[ -d "$ARCON_HOME/.config/hypr" ]] && fs_backup "$ARCON_HOME/.config/hypr"

    if [[ -d "$dir/.git" ]]; then
        x_user COMMAND "update $theme checkout" -- git -C "$dir" pull --ff-only || return 1
    else
        [[ -e "$dir" ]] && { log_error "$dir exists and is not a git checkout — move it away first"; return 1; }
        x_user COMMAND "clone $theme" -- git clone --depth 1 -b "$branch" "$repo" "$dir" || return 1
    fi
    local commit script
    commit="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
    if [[ "$inst" == @* ]]; then
        script="$dir/.arcon-bootstrap.sh"
        fetch_to "${inst#@}" "$script" || return 1
    else
        script="$dir/$inst"
    fi
    [[ -f "$script" ]] || { log_error "installer $inst not found in $repo@$commit — upstream layout changed"; return 1; }
    ui_say "\n${BOLD}Third-party installer:${NC} $theme  repo=$repo  commit=$commit"
    ui_say "  script: $script   sha256: $(sha256sum "$script" | cut -c1-16)…"
    if cfg_bool HYPR_EDIT_INSTALLER; then
        "${EDITOR:-nano}" "$script" </dev/tty >/dev/tty 2>&1 || true
    fi
    ui_confirm "Run this third-party installer now (it will make its own system changes)" n || return "$TASK_SKIP"
    rb_add NOTE "third-party Hyprland theme '$theme' ($repo@$commit) made changes ArCoN cannot roll back; previous ~/.config/hypr is in the run backup"
    ( cd "$(dirname "$script")" && as_user bash "./$(basename "$script")" )
    local rc=$?
    if (( rc == 0 )); then log_result "Hyprland theme $theme" PASS; else log_result "Hyprland theme $theme" FAIL "installer exit $rc"; fi
    return $rc
}
