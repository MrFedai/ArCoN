#!/usr/bin/env bash
# ArCoN v3.0 -- modules/reset.sh
# v2.5 "Sector 0: Smart Factory Reset (Safe Mode)" — reached with `--reset`.
#
# v2.5 → v3.0
#   * config dirs deleted after `cp -r` to a backup dir with no verification
#     → backup verified before removal, and journaled so --rollback restores it
#   * `dconf reset -f /` wiped ALL GNOME settings without a backup
#     → `dconf dump /` is stored first, restorable
#   * removed ~/.oh-my-zsh, ~/.zshrc, ~/.config/starship.toml unconditionally
#     → backed up first, and only with explicit confirmation
#   * `chsh -s /bin/bash` without recording the previous shell → journaled
#   * package names were Arch names on Debian → catalog resolution per platform
#   * `pacman -Rns $(pacman -Qtdq)` unquoted, output hidden → list shown, -Rs, logged
#   * dry-run impossible (the reset ran immediately) → `--reset --dry-run` shows the full plan

ARCON_MODULE=reset

# Never removed, even if a package group lists them (v2.5 whitelist + v3 additions).
RESET_PROTECTED=(
    base base-devel linux linux-firmware sudo pacman yay systemd systemd-libs glibc
    networkmanager network-manager-applet wpa_supplicant wget curl git openssh
    vim nano neovim bluez bluez-utils
    kitty alacritty terminator gnome-terminal konsole xfce4-terminal
    bash zsh fish
    apt dpkg dnf rpm zypper coreutils util-linux openssl ca-certificates
    gnome-shell gdm sddm plasma-desktop xorg-server mesa
)

# package id -> config directory name (v2.5 map, extended)
reset_config_dir() {
    case "$1" in
        hyprland|hyprlock|hypridle) printf 'hypr' ;;
        neovim) printf 'nvim' ;;
        code|visual-studio-code-bin) printf 'Code' ;;
        *) printf '%s' "$1" ;;
    esac
}

reset_targets() {
    local g
    {
        for g in essentials media cyber remote power; do catalog_group "$g"; done
        pkg_custom_list
    } | awk 'NF && !seen[$0]++'
}

_is_protected() {
    local p
    for p in "${RESET_PROTECTED[@]}"; do [[ "$p" == "$1" ]] && return 0; done
    return 1
}

# reset_run: called directly by the CLI (--reset), not through the module queue
reset_run() {
    ui_header "SMART CLEANUP PROTOCOL (SAFE MODE)"
    ui_say "${YELLOW}This mode scans the ArCoN package lists and cleans up their configs${NC}"
    ui_say "${YELLOW}(and optionally the packages themselves). Backups are always taken.${NC}"

    local ids=() natives=() name src
    mapfile -t ids < <(reset_targets)
    while IFS=$'\t' read -r name src; do
        [[ -z "$name" || "$src" != native ]] && continue
        _is_protected "$name" && continue
        pkg_is_installed "$name" && natives+=("$name")
    done < <(pkg_resolve "${ids[@]}" 2>/dev/null)

    local cfgdirs=() id d
    for id in "${ids[@]}"; do
        d="$(reset_config_dir "$id")"
        [[ -d "$ARCON_HOME/.config/$d" ]] && cfgdirs+=("$ARCON_HOME/.config/$d")
        [[ -d "$ARCON_HOME/.$d" ]] && cfgdirs+=("$ARCON_HOME/.$d")
    done

    ui_say "\n${BOLD}Installed ArCoN-managed packages found:${NC} ${#natives[@]}"
    ui_say "${BOLD}Config directories found:${NC} ${#cfgdirs[@]}"
    (( ${#cfgdirs[@]} )) && printf '   %s\n' "${cfgdirs[@]}"

    local do_pkgs=0 do_shell=0
    if ui_confirm "Also uninstall these ${#natives[@]} packages (protected system packages are skipped)" n; then do_pkgs=1; fi
    if ui_confirm "Also reset GNOME and shell settings to defaults" n; then do_shell=1; fi

    if ! is_dry_run; then
        ui_confirm "START CLEANUP PROCESS (config backup included)" n || { log_info "cancelled"; return 0; }
        ui_confirm_word "This removes configuration files${do_pkgs:+ and uninstalls packages}" CLEAN || { log_info "cancelled"; return 0; }
    fi

    # 1. configs
    local path
    for path in "${cfgdirs[@]}"; do
        fs_remove "$path" || return 1
        ui_say "${RED}[-] removed:${NC} ${path/#$ARCON_HOME/~}  ${DIM}(backup kept)${NC}"
    done

    # 2. packages
    if (( do_pkgs )) && (( ${#natives[@]} )); then
        ui_header "UNINSTALLATION PHASE (SAFE MODE)"
        log_info "removing: ${natives[*]}"
        pkg_remove "${natives[@]}" || log_warn "some packages could not be removed (see log)"
        opt_orphans || true
    fi

    # 3. GNOME + shell
    if (( do_shell )); then
        if command -v dconf >/dev/null 2>&1; then
            if is_dry_run; then
                plan_record SETTING "dconf dump / -> backup, then dconf reset -f / (ALL GNOME settings)"
            else
                local dump; dump="$(rb_backup_dir)/dconf-full.ini"; mkdir -p "$(dirname "$dump")"
                dconf dump / > "$dump" && rb_add DCONF / "$dump" || { log_error "dconf backup failed — not resetting"; return 1; }
                x_run SETTING "reset all GNOME/dconf settings" -- dconf reset -f / || return 1
            fi
        fi
        fs_remove "$ARCON_HOME/.oh-my-zsh"
        fs_remove "$ARCON_HOME/.zshrc"
        fs_remove "$ARCON_HOME/.config/starship.toml"
        local cur; cur="$(getent passwd "$ARCON_USER" 2>/dev/null | cut -d: -f7)"
        if [[ -x /bin/bash && "$cur" != /bin/bash ]]; then
            rb_add SHELL "$ARCON_USER" "$cur"
            x_root SETTING "reset login shell to /bin/bash (was $cur)" -- chsh -s /bin/bash "$ARCON_USER" || log_warn "chsh failed"
        fi
    fi

    if is_dry_run; then
        plan_print
    else
        log_result "smart factory reset" PASS "backups: $(rb_backup_dir)"
        ui_say "\n${GREEN}[OK] SMART CLEANUP COMPLETE.${NC}"
        ui_say "${YELLOW}[INFO] Backups: $(rb_backup_dir)${NC}"
        ui_say "${YELLOW}[INFO] Undo everything: ./setup.sh --rollback${NC}"
    fi
}
