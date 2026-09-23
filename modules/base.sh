#!/usr/bin/env bash
# ArCoN v3.0 -- modules/base.sh
# v2.5 "Pre-flight checks" + "Sector 1: Base System & Mirrors".
#
# v2.5 → v3.0
#   * internet check was commented out but printed OK        → real check
#   * pacman lock was removed silently                        → asked / configurable
#   * GPG keyring was wiped on EVERY run                      → safe refresh by default,
#                                                               full reset opt-in (BASE_GPG_RESET)
#   * reflector saved over mirrorlist without backup          → backup + rollback
#   * `pacman -Sy` partial upgrades                           → -Syu only
#   * yay-bin cloned and built in the repo directory         → temp dir, subshell
#   * Debian/Ubuntu only besides Arch                         → + Fedora, openSUSE, macOS

ARCON_MODULE=base

preflight_run() {
    ARCON_MODULE=preflight
    local ok=1
    ui_section "Pre-flight checks"

    # 1. network (real)
    if net_online; then log_result "internet connection" PASS
    else
        if cfg_bool REQUIRE_NETWORK yes && ! is_dry_run; then
            log_result "internet connection" FAIL "no HTTPS connectivity to $(cfg NET_CHECK_URLS)"
            log_error "suggestion: check cable/Wi-Fi, DNS and proxy settings, or use --set REQUIRE_NETWORK=no for offline dry-runs"
            ok=0
        else
            log_warn "no internet connectivity detected (continuing: dry-run or REQUIRE_NETWORK=no)"
        fi
    fi

    # 2. disk space (v2.5: 10 GB)
    local min free; min="$(cfg MIN_DISK_GB 10)"; free="${HW_DISK_FREE_GB:-0}"
    if [[ "$free" =~ ^[0-9]+$ ]] && (( free >= min )); then log_result "disk space" PASS "${free} GB free (min ${min} GB)"
    else
        log_result "disk space" FAIL "${free} GB free, ${min} GB required"
        is_dry_run || ok=0
    fi

    # 3. privileges
    if is_root; then
        if [[ -z "${SUDO_USER:-}" ]]; then
            log_warn "running as root without sudo: user-level configs go to $HOME and AUR/Homebrew steps will fail"
        fi
        log_result "privileges" PASS "root"
    elif is_dry_run; then
        log_result "privileges" SKIP "dry-run does not need sudo"
    elif command -v sudo >/dev/null 2>&1 && sudo -v; then
        log_result "privileges" PASS "sudo"
        sudo_keepalive_start
    else
        log_result "privileges" FAIL "sudo is required (run: sudo -v)"
        ok=0
    fi

    # 4. OS support tier
    case "$OS_SUPPORT" in
        tested) log_result "operating system" PASS "$OS_NAME" ;;
        experimental) log_warn "$OS_NAME is not one of the CI-tested distributions — treated as $OS_ID (experimental)" ;;
        *) log_result "operating system" FAIL "$OS_NAME is not supported"; ok=0 ;;
    esac

    # 5. architecture
    case "$HW_ARCH" in
        x86_64|amd64|aarch64|arm64) ;;
        *) log_warn "architecture $HW_ARCH is untested; many packages (e.g. Steam, Chrome) are x86_64-only" ;;
    esac

    # 6. live environment (v2.5 check was commented out)
    if [[ "$HW_IS_LIVE" == yes ]]; then
        log_warn "LIVE ENVIRONMENT DETECTED — all changes are lost after reboot"
        if ! is_dry_run && ! ui_confirm "Continue anyway (NOT RECOMMENDED)" n; then
            die 0 "cancelled on live environment"
        fi
    fi

    # 7. pacman lock (v2.5 behaviour, now confirmed)
    if is_arch && [[ -f "${ARCON_SYSROOT}/var/lib/pacman/db.lck" ]]; then
        if pgrep -x pacman >/dev/null 2>&1; then
            log_result "pacman lock" FAIL "pacman is running in another process"; ok=0
        else
            local mode; mode="$(cfg PACMAN_STALE_LOCK ask)"
            if [[ "$mode" == remove ]] || { [[ "$mode" == ask ]] && ui_confirm "Stale pacman lock found (no pacman running). Remove /var/lib/pacman/db.lck" y; }; then
                x_root FILE "remove stale pacman lock" -- rm -f /var/lib/pacman/db.lck
            else
                log_result "pacman lock" FAIL "stale lock kept"; ok=0
            fi
        fi
    fi

    ARCON_MODULE=base
    (( ok == 1 ))
}

# ----------------------------------------------------------------- wizard
mod_base_wizard() {
    ui_confirm_set BASE_UPGRADE y "Update Base System (Mirrors/Keyrings)"
    if is_arch && cfg_bool BASE_UPGRADE; then
        ui_confirm_set BASE_MIRRORS y "Benchmark and rank Arch mirrors with reflector"
        if ui_confirm "Emergency keyring reset (wipes /etc/pacman.d/gnupg — only if pacman reports GPG errors)" n; then
            cfg_set BASE_GPG_RESET yes wizard
        fi
    fi
    return 0
}

mod_base_plan() {
    # Note: BASE_UPGRADE only controls the *upgrade* task. Database refresh and
    # build dependencies are needed by every other module, so they are always
    # planned when the base module is selected (v3.0 fix: in the first v3 draft
    # BASE_UPGRADE=no silently disabled the whole module).
    case "$OS_ID" in
        arch)
            cfg_bool BASE_GPG_RESET && task_add base.gpg_reset high "Reset pacman keyring (v2.5 GPG emergency fix)" base_arch_gpg_reset
            task_add base.keyring low "Refresh archlinux-keyring and core build deps" base_arch_keyring
            cfg_bool BASE_MIRRORS yes && task_add base.mirrors medium "Rank HTTPS mirrors with reflector (backup kept)" base_arch_mirrors
            cfg_bool BASE_UPGRADE yes && task_add base.upgrade low "Full system upgrade (pacman -Syu)" base_upgrade
            cfg_bool BASE_AUR_HELPER_INSTALL yes && task_add base.aur_helper medium "Install AUR helper ($(cfg AUR_HELPER yay)-bin)" base_arch_aur_helper
            cfg_bool BASE_SPEEDTEST yes && task_add base.speedtest low "Measure download speed (Cloudflare)" base_speedtest ;;
        debian|ubuntu|fedora|opensuse)
            task_add base.refresh low "Refresh package database" base_refresh
            task_add base.deps low "Install build essentials and git" base_deps
            cfg_bool BASE_UPGRADE yes && task_add base.upgrade low "Upgrade installed packages" base_upgrade ;;
        macos)
            task_add base.xcode_clt low "Check Xcode Command Line Tools" base_macos_clt
            task_add base.refresh low "Update Homebrew" base_refresh
            cfg_bool BASE_UPGRADE yes && task_add base.upgrade low "Upgrade Homebrew packages" base_upgrade ;;
    esac
    return 0
}

base_refresh() { pkg_refresh; }
base_upgrade() { pkg_upgrade_all; }
base_deps()    { pkg_install_ids base-devel git curl; }

base_arch_gpg_reset() {
    local conf=/etc/pacman.conf ba=0
    if pacman_repo_enabled blackarch; then
        ba=1
        fs_backup "$conf" root
        x_root REPO "temporarily disable [blackarch] while keys are rebuilt" -- \
            sed -i -e 's/^\[blackarch\]/#[blackarch]/' -e 's|^Include = /etc/pacman.d/blackarch-mirrorlist|#Include = /etc/pacman.d/blackarch-mirrorlist|' "$conf" || return 1
    fi
    # keep a restorable copy of the keyring (v2.5 deleted it outright)
    if ! is_dry_run && [[ -d /etc/pacman.d/gnupg ]]; then
        local tarball; tarball="$(rb_backup_dir)/pacman-gnupg.tar"
        as_root tar -C /etc/pacman.d -cf "$tarball" gnupg && as_root chown "$(id -u)" "$tarball"
        rb_add NOTE "pacman keyring was reset; previous keyring archived at $tarball"
    fi
    x_root COMMAND "stop gpg-agent processes" -- gpgconf --homedir /etc/pacman.d/gnupg --kill all || true
    x_root FILE "remove broken keyring /etc/pacman.d/gnupg" -- rm -rf /etc/pacman.d/gnupg || return 1
    x_root FILE "remove stale sync databases" -- find /var/lib/pacman/sync -mindepth 1 -delete || return 1
    x_root COMMAND "pacman-key --init" -- pacman-key --init || return 1
    x_root COMMAND "pacman-key --populate archlinux" -- pacman-key --populate archlinux || return 1
    if (( ba == 1 )); then
        x_root REPO "re-enable [blackarch]" -- \
            sed -i -e 's/^#\[blackarch\]/[blackarch]/' -e 's|^#Include = /etc/pacman.d/blackarch-mirrorlist|Include = /etc/pacman.d/blackarch-mirrorlist|' "$conf" || return 1
        x_root COMMAND "locally sign BlackArch key" -- pacman-key --lsign-key "$BLACKARCH_KEY_FPR" || true
    fi
}

base_arch_keyring() {
    # -Sy + keyring alone would be a partial upgrade; -Syu follows in base.upgrade
    # and we install keyring together with the upgrade transaction.
    x_root PKG_INSTALL "refresh keyring + prerequisites" -- pacman -Syu --needed --noconfirm archlinux-keyring git base-devel reflector
    local rc=$?
    (( rc == 0 )) || log_error "keyring/prerequisites failed — if pacman reports PGP errors, re-run with --set BASE_GPG_RESET=yes"
    pkg_invalidate
    return $rc
}

base_arch_mirrors() {
    command -v reflector >/dev/null 2>&1 || is_dry_run || { log_warn "reflector not installed — skipping mirror ranking"; return "$TASK_SKIP"; }
    local ml=/etc/pacman.d/mirrorlist args=(--protocol https --latest 20 --sort rate --download-timeout 5)
    local country; country="$(cfg BASE_MIRROR_COUNTRY)"
    [[ -n "$country" ]] && args+=(--country "$country")
    fs_backup "$ml" root || return 1
    if is_dry_run; then plan_record FILE "$ml: rewrite with reflector ${args[*]}"; return 0; fi
    local tmp; tmp="$(mktemp)"
    ui_say "${BLUE}[*] Benchmarking top 20 HTTPS mirrors... (live output)${NC}"
    # v2.5 live colourised output kept; result written to a temp file first
    as_root reflector --verbose "${args[@]}" --save "$tmp" 2>&1 | _reflector_colorize
    if ! grep -q '^Server' "$tmp" 2>/dev/null; then
        log_error "reflector produced no servers — mirrorlist left unchanged"
        rm -f "$tmp"; return 1
    fi
    as_root install -m 0644 "$tmp" "$ml"; rm -f "$tmp"
    ui_say "${YELLOW}[INFO] Final selection (top 10):${NC}"
    grep '^Server' "$ml" | head -n 10 | awk -v g="$GREEN" -v n="$NC" '{ if (NR==1) printf "%s 1. %s  <-- ACTIVE MIRROR%s\n", g, $3, n; else printf " %2d. %s\n", NR, $3 }'
    pkg_invalidate
}

_reflector_colorize() {
    awk -v red='\033[1;31m' -v green='\033[1;32m' -v nc='\033[0m' '
        BEGIN { count = 1 }
        /rating/ || /Server.*Rate.*Time/ { print; next }
        {
            for (i = 2; i <= NF; i++) {
                if ($i ~ /^[KM]i?B\/s$/ || $i ~ /^s$|^second\(s\)\.?$/) {
                    c = ($(i-1) == 0 || $(i-1) == "0.00") ? red : green
                    $(i-1) = c $(i-1); $i = $i nc
                }
            }
            printf "%2d) %s\n", count++, $0; fflush()
        }'
}

base_arch_aur_helper() {
    local helper; helper="$(cfg AUR_HELPER yay)"
    if command -v "$helper" >/dev/null 2>&1; then log_info "$helper already installed"; return 0; fi
    if is_root && [[ -z "${SUDO_USER:-}" ]]; then log_error "makepkg cannot run as root; run ArCoN as a normal user with sudo"; return 1; fi
    if is_dry_run; then plan_record PKG_INSTALL "$helper-bin (AUR, built with makepkg in a temp dir)"; return 0; fi
    local work; work="$(as_user mktemp -d)"
    (
        cd "$work" || exit 1
        as_user git clone --depth 1 "https://aur.archlinux.org/${helper}-bin.git" || exit 1
        cd "${helper}-bin" || exit 1
        ui_say "${DIM}PKGBUILD source: $(grep -m1 '^source' PKGBUILD 2>/dev/null)${NC}"
        as_user makepkg -si --noconfirm
    ) >> "$(log_file)" 2>&1
    local rc=$?
    as_user rm -rf "$work"
    if (( rc == 0 )) && command -v "$helper" >/dev/null 2>&1; then rb_add PKG pacman "${helper}-bin"; pkg_invalidate; return 0; fi
    log_error "$helper build failed (see log). Recovery: check base-devel/git, then re-run with --resume"
    return 1
}

base_speedtest() {
    is_dry_run && { plan_record COMMAND "download speed test (10 MB from speed.cloudflare.com, read-only)"; return 0; }
    local bps kb
    bps="$(curl -s -o /dev/null -w '%{speed_download}' --connect-timeout 5 --max-time 8 'https://speed.cloudflare.com/__down?bytes=10000000' 2>/dev/null)"
    kb="$(awk -v b="${bps:-0}" 'BEGIN{printf "%d", b/1024}')"
    ui_say "${BOLD}>> Current download speed: ${kb} KB/s${NC}"
    if (( kb < 500 )); then log_warn "connection seems slow (<500 KB/s)"; else log_info "connection speed is good"; fi
    return 0
}

base_macos_clt() {
    if xcode-select -p >/dev/null 2>&1; then log_info "Xcode Command Line Tools present"; return 0; fi
    log_warn "Xcode Command Line Tools missing — opening the Apple installer dialog"
    x_run COMMAND "xcode-select --install (Apple GUI installer)" -- xcode-select --install || true
    log_warn "finish the Apple installer, then run: ./setup.sh --resume"
    return 1
}
