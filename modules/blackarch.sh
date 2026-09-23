#!/usr/bin/env bash
# ArCoN v3.0 -- modules/blackarch.sh
# v2.5 "Sector 4: BlackArch Repository Manager". Arch Linux ONLY.
#
# v2.5 → v3.0
#   * strap.sh executed without checksum                 → sha1 compared with the value published
#                                                          on blackarch.org/downloads.html (+ optional pinned sha256)
#   * lsign of 4345771566D76030457303332944B067D796237B  → that fingerprint is WRONG; the BlackArch
#                                                          key is 4345771566D76038C7FEB43863EC0ADBEA87E4E3
#                                                          (blackarch-keyring-20251011/blackarch-trusted)
#   * install with --overwrite '*' (can clobber files)   → off by default (BLACKARCH_OVERWRITE=yes to opt in)
#   * removal: sed '/\[blackarch\]/,+1d'                 → exact section removal with backup
#   * menu loop                                          → BLACKARCH=enable|core|full|remove (wizard keeps the menu)
# Other OSes: BlackArch is platform-inapplicable. Intent (security tooling) is covered by
# PKG_GROUPS=cyber (catalog-mapped per distro) and the security module.

ARCON_MODULE=blackarch
BLACKARCH_KEY_FPR=4345771566D76038C7FEB43863EC0ADBEA87E4E3
BLACKARCH_STRAP_URL=https://blackarch.org/strap.sh
BLACKARCH_DOWNLOADS_URL=https://blackarch.org/downloads.html
BLACKARCH_CORE_GROUPS=(blackarch-webapp blackarch-networking blackarch-wireless)

blackarch_enabled() { pacman_repo_enabled blackarch; }

mod_blackarch_wizard() {
    is_arch || return 0
    local status="NOT ENABLED"; blackarch_enabled && status="ACTIVE"
    local choice
    ui_choose choice "$(cfg BLACKARCH no)" "BlackArch Repository Manager [Status: $status]" \
        "no:Skip" "enable:Enable repository & prep system" \
        "core:Enable + install core pentest groups (webapp, networking, wireless)" \
        "full:Enable + install FULL BlackArch (all tools, 20GB+)" \
        "remove:Remove BlackArch repository & key"
    cfg_set BLACKARCH "$choice" wizard
    return 0
}

mod_blackarch_plan() {
    local mode; mode="$(cfg BLACKARCH no)"
    [[ "$mode" == no ]] && return 0
    if ! is_arch; then
        log_warn "BlackArch requested on $OS_ID — platform-inapplicable (Arch Linux only). Use PKG_GROUPS=cyber instead."
        return 0
    fi
    case "$mode" in
        enable|core|full)
            task_add blackarch.enable high "Enable BlackArch repository (verified strap.sh)" blackarch_enable
            cfg_bool BLACKARCH_PROVIDER_FIX yes && task_add blackarch.providers low "Pre-install providers (jdk17/jdk11/rust/opencl-mesa)" blackarch_providers
            [[ "$mode" != enable ]] && task_add blackarch.install medium "Install BlackArch tools ($mode)" blackarch_install ;;
        remove)
            task_add blackarch.remove medium "Remove BlackArch repository and key" blackarch_remove ;;
        *) log_error "BLACKARCH: unknown value '$mode'"; return 1 ;;
    esac
    return 0
}

# published sha1 of strap.sh from the official downloads page
blackarch_published_sha1() {
    curl -fsSL --proto '=https' --max-time 20 "$BLACKARCH_DOWNLOADS_URL" 2>/dev/null |
        grep -oE 'echo [0-9a-f]{40} +strap\.sh' | head -n1 | awk '{print $2}'
}

blackarch_enable() {
    if blackarch_enabled; then log_info "BlackArch repository already active"; return 0; fi
    if is_dry_run; then
        plan_record REPO "add [blackarch] to /etc/pacman.conf via $BLACKARCH_STRAP_URL (sha1 verified against $BLACKARCH_DOWNLOADS_URL)"
        plan_record PKG_INSTALL "blackarch-keyring, blackarch-mirrorlist"
        return 0
    fi
    local work strap got want pinned
    work="$(mktemp -d)"; strap="$work/strap.sh"
    fetch_to "$BLACKARCH_STRAP_URL" "$strap" || { rm -rf "$work"; return 1; }
    got="$(sha1sum "$strap" | awk '{print $1}')"
    want="$(blackarch_published_sha1)"
    pinned="$(cfg BLACKARCH_STRAP_SHA256)"
    if [[ -n "$pinned" ]] && [[ "$(sha256sum "$strap" | awk '{print $1}')" != "$pinned" ]]; then
        log_error "strap.sh sha256 does not match BLACKARCH_STRAP_SHA256 — aborting"; rm -rf "$work"; return 1
    fi
    if [[ -z "$want" ]]; then
        log_error "could not read the published strap.sh checksum from $BLACKARCH_DOWNLOADS_URL — aborting (no unverified execution)"
        rm -rf "$work"; return 1
    fi
    if [[ "$got" != "$want" ]]; then
        log_error "strap.sh checksum mismatch: got $got, published $want — aborting"
        rm -rf "$work"; return 1
    fi
    log_result "strap.sh checksum" PASS "sha1 $got matches blackarch.org"
    fs_backup /etc/pacman.conf root
    rb_add NOTE "BlackArch keyring installed into pacman keyring (remove: ./setup.sh --set BLACKARCH=remove)"
    x_tty REPO "run BlackArch strap.sh (adds [blackarch] + keyring)" -- bash "$strap"; local rc=$?
    rm -rf "$work"
    (( rc == 0 )) || return $rc
    x_root COMMAND "locally sign BlackArch key $BLACKARCH_KEY_FPR" -- pacman-key --lsign-key "$BLACKARCH_KEY_FPR" || return 1
    pkg_invalidate; _PACMAN_SYNC_LOADED=0
    if blackarch_enabled; then log_result "BlackArch repository" PASS; else log_result "BlackArch repository" FAIL "[blackarch] missing from pacman.conf"; return 1; fi
}

blackarch_providers() {
    # v2.5 "provider lock" fix: pick providers up-front so the group install does not prompt
    pkg_install jdk17-openjdk jdk11-openjdk rust opencl-mesa
}

blackarch_install() {
    local mode; mode="$(cfg BLACKARCH)"
    local targets=()
    [[ "$mode" == full ]] && targets=(blackarch) || targets=("${BLACKARCH_CORE_GROUPS[@]}")
    local flags=(-S --needed)
    if cfg_bool BLACKARCH_OVERWRITE; then
        log_warn "BLACKARCH_OVERWRITE=yes: pacman may overwrite files owned by other packages"
        flags+=(--overwrite '*')
    fi
    if is_dry_run; then plan_record PKG_INSTALL "pacman ${flags[*]} ${targets[*]}"; return 0; fi
    if [[ "${ARCON_INTERACTIVE:-1}" == 1 ]]; then
        ui_say "\n${BLUE}========== SELECTION GUIDE ==========${NC}"
        ui_say " - Press ${GREEN}[Enter]${NC} for ALL (Default)"
        ui_say " - Type ${CYAN}1 5 10${NC} for specific tools"
        ui_say " - Type ${RED}^10 ^15${NC} to ${RED}EXCLUDE${NC} packages 10 and 15"
        ui_say " - Range: ${CYAN}1-50${NC} (installs first 50 tools)"
        ui_say "${BLUE}=====================================${NC}"
        x_tty PKG_INSTALL "BlackArch ${targets[*]} (interactive pacman selection)" -- pacman "${flags[@]}" "${targets[@]}"
    else
        x_root PKG_INSTALL "BlackArch ${targets[*]}" -- pacman "${flags[@]}" --noconfirm "${targets[@]}"
    fi
    local rc=$?
    pkg_invalidate
    if (( rc == 0 )); then log_result "BlackArch $mode" PASS; else log_result "BlackArch $mode" FAIL "pacman exit $rc (file conflicts? retry with --set BLACKARCH_OVERWRITE=yes only if you understand the risk)"; fi
    return $rc
}

blackarch_remove() {
    blackarch_enabled || grep -q '^#\[blackarch\]' /etc/pacman.conf || { log_info "BlackArch not present"; return 0; }
    local tmp; tmp="$(mktemp)"
    # drop the [blackarch] section (header + its lines up to the next section)
    awk '/^#?\[blackarch\]/ { skip=1; next } /^\[/ { skip=0 } !skip' /etc/pacman.conf > "$tmp"
    fs_install_file "$tmp" /etc/pacman.conf root 0644; local rc=$?; rm -f "$tmp"
    (( rc == 0 )) || return $rc
    plan_record REPO "remove [blackarch] from /etc/pacman.conf"
    x_root COMMAND "delete BlackArch key" -- pacman-key --delete "$BLACKARCH_KEY_FPR" || log_warn "BlackArch key not in keyring"
    x_root COMMAND "resync databases" -- pacman -Syy || return 1
    log_info "installed BlackArch packages were NOT removed (list: pacman -Sl blackarch before removal, or pacman -Qm)"
}
