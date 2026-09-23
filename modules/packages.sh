#!/usr/bin/env bash
# ArCoN v3.0 -- modules/packages.sh
# v2.5 "Sector 3: Package Groups" + "Smart Package Manager Engine".
#
# v2.5 → v3.0
#   * package names were Arch names on every distro      → data/packages.catalog per distro
#   * pacs.txt was read line by line (no comments)       → comments/blank lines allowed
#   * size preview only on Arch                          → kept on Arch; count elsewhere
#   * per-package progress bar                           → kept (interactive), batch in CI
#   * failures printed but run reported success          → failures returned + summarised

ARCON_MODULE=packages
PKG_GROUP_LABELS=(
    "essentials:Essentials (Chrome, VLC, LibreOffice, Obsidian, htop, fastfetch...)"
    "media:Media & Creativity (OBS, GIMP, Krita, Kdenlive, Audacity...)"
    "cyber:Cyber Security (nmap, wireshark, metasploit, burpsuite...)"
    "remote:Remote & Network (Remmina, AnyDesk, RustDesk, LocalSend...)"
    "power:Power User & Dev (VS Code, Docker, Neovim, btop, tmux...)"
)
PKG_FAILED_IDS=()
PKG_UNAVAILABLE_IDS=()

mod_packages_wizard() {
    local sel=() e g
    ui_section "Package groups"
    for e in "${PKG_GROUP_LABELS[@]}"; do
        g="${e%%:*}"
        local def=n; cfg_list_has PKG_GROUPS "$g" && def=y
        ui_confirm "Install ${e#*:}" "$def" && sel+=("$g")
    done
    cfg_set PKG_GROUPS "$(IFS=,; printf '%s' "${sel[*]}")" wizard
    local custom; custom="$(pkg_custom_file)"
    if [[ -n "$custom" ]]; then
        ui_confirm_set PKG_USE_CUSTOM y "Load custom packages from $(basename "$custom") ($(pkg_custom_list | wc -l | tr -d ' ') entries)"
    fi
    return 0
}

pkg_custom_file() {
    local f; f="$(cfg PKG_CUSTOM_FILE pacs.txt)"
    [[ "$f" == /* ]] || f="$ARCON_ROOT/$f"
    [[ -r "$f" ]] && printf '%s' "$f"
}

# pacs.txt: one id or native name per line, '#' comments allowed
pkg_custom_list() {
    local f; f="$(pkg_custom_file)" || return 0
    [[ -n "$f" ]] || return 0
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$f" | awk 'NF'
}

# pkg_selected_ids -> unique ids, catalog order, then custom/extra
pkg_selected_ids() {
    local g
    {
        for g in $(cfg PKG_GROUPS | tr ',' ' '); do catalog_group "$g"; done
        if [[ "$(cfg PKG_USE_CUSTOM ask)" == yes ]]; then pkg_custom_list; fi
        cfg_list PKG_EXTRA
    } | awk 'NF && !seen[$0]++'
}

mod_packages_plan() {
    local ids; ids="$(pkg_selected_ids | wc -l | tr -d ' ')"
    (( ids > 0 )) || { log_info "no package groups selected"; return 0; }
    task_add packages.install low "Install $ids selected packages ($(cfg PKG_GROUPS))" packages_install
    return 0
}

packages_install() {
    local ids=() native=() flat=() name src
    mapfile -t ids < <(pkg_selected_ids)
    PKG_UNAVAILABLE_IDS=()
    while IFS=$'\t' read -r name src; do
        [[ -z "$name" ]] && continue
        if [[ "$src" == flatpak ]]; then flat+=("$name"); else native+=("$name"); fi
    done < <(pkg_resolve "${ids[@]}" 2>"$ARCON_TMP/unavail.txt")
    local tag uid _rest
    while read -r tag uid _rest; do
        [[ "$tag" == UNAVAILABLE ]] && PKG_UNAVAILABLE_IDS+=("$uid")
    done < "$ARCON_TMP/unavail.txt"
    if (( ${#PKG_UNAVAILABLE_IDS[@]} )); then
        log_warn "not packaged for $OS_ID (platform-inapplicable, skipped): ${PKG_UNAVAILABLE_IDS[*]}"
        is_linux && ! cfg_bool PKG_ALLOW_FLATPAK && log_info "tip: --set PKG_ALLOW_FLATPAK=yes installs available ones from Flathub"
    fi

    # already-installed filter (one cached query — v2.5 called pacman -Qi per package)
    local todo=() n
    for n in "${native[@]}"; do pkg_is_installed "$n" || todo+=("$n"); done
    log_info "packages: ${#native[@]} native requested, $(( ${#native[@]} - ${#todo[@]} )) already installed, ${#todo[@]} to install; ${#flat[@]} flatpak"

    if (( ${#todo[@]} )) && is_arch && [[ "${ARCON_INTERACTIVE:-1}" == 1 ]]; then
        packages_arch_preview "${todo[@]}" || return $?
    fi

    if is_dry_run; then
        for n in "${todo[@]}"; do plan_record PKG_INSTALL "$n  (via $PKG_PROVIDER)"; done
        (( ${#flat[@]} )) && flatpak_install "${flat[@]}"
        return 0
    fi

    PKG_FAILED_IDS=()
    local i=0 total=${#todo[@]}
    if [[ "${ARCON_INTERACTIVE:-1}" == 1 && -t 1 ]] && (( total > 0 )); then
        # v2.5 per-package progress UI
        for n in "${todo[@]}"; do
            i=$((i + 1))
            ui_progress "$((i - 1))" "$total" "installing $n"
            if pkg_install "$n" >/dev/null 2>&1; then :; else PKG_FAILED_IDS+=("$n"); fi
        done
        ui_progress "$total" "$total" "done"
    elif (( total > 0 )); then
        pkg_install "${todo[@]}" || PKG_FAILED_IDS+=("${PKG_LAST_FAILED[@]}")
    fi
    (( ${#flat[@]} )) && { flatpak_install "${flat[@]}" || PKG_FAILED_IDS+=("flatpak:${flat[*]}"); }

    if (( ${#PKG_FAILED_IDS[@]} )); then
        log_error "failed packages: ${PKG_FAILED_IDS[*]}"
        log_error "recovery: check the log, then re-run: ./setup.sh --resume"
        return 1
    fi
    log_result "package installation" PASS "${total} installed, $(( ${#native[@]} - total )) already present"
}

packages_arch_preview() {
    local official=() aur=() n
    for n in "$@"; do if pacman_is_official "$n"; then official+=("$n"); else aur+=("$n"); fi; done
    ui_say "\n${BOLD}Package preview${NC}"
    local rows=("${BOLD}PACKAGE|SOURCE|DOWNLOAD${NC}") name size
    if (( ${#official[@]} )); then
        while IFS=$'\t' read -r name size; do rows+=("$name|official|$size"); done < <(pacman_download_size "${official[@]}")
    fi
    for n in "${aur[@]}"; do rows+=("$n|AUR|built locally"); done
    ui_table "${rows[@]}"
    ui_say "  official: ${#official[@]}   AUR: ${#aur[@]}"
    (( ${#aur[@]} )) && ! aur_helper >/dev/null && log_warn "AUR packages need yay/paru (base module installs it)"
    ui_confirm "Proceed with installation" y || { log_warn "package installation skipped by user"; return "$TASK_SKIP"; }
}
