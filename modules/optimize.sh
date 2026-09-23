#!/usr/bin/env bash
# ArCoN v3.0 -- modules/optimize.sh
# Catalogued system optimizations (data/optimizations.catalog).
# Replaces the v2.5 "optimization steps" progress loop in Sector 9 and the
# Arch cleanup at the end of the script.
#
# Every item declares: category, platforms, risk, profiles, description,
# expected effect, rollback method and verification method — and nothing is
# applied that the selected profile did not ask for.
#
# v2.5 → v3.0
#   * fstrim.timer enabled on spinning disks too         → only when HW_DISK_TYPE is ssd/nvme
#   * Bluetooth enabled without checking for an adapter  → skipped when no adapter exists
#   * ZRAM step required zram-generator, which was never
#     installed → the step silently did nothing          → package installed, existing zram respected
#   * `pacman -Sc` / `-Scc` wiped the cache unasked       → paccache -rk2 by default, purge opt-in
#   * orphan removal ran `pacman -Rns $(pacman -Qdtq)`
#     with no list, no confirmation, errors hidden        → list shown, confirmed, verified
#   * Arch-only commands ran on Debian                    → per-platform implementations

ARCON_MODULE=optimize
OPT_CATALOG="${ARCON_ROOT:-.}/data/optimizations.catalog"
declare -gA OPT_ROW=()
_OPT_LOADED=0

opt_load() {
    (( _OPT_LOADED == 1 )) && return 0
    [[ -r "$OPT_CATALOG" ]] || { log_error "optimization catalog missing: $OPT_CATALOG"; return 1; }
    local line id
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        id="${line%%|*}"
        OPT_ROW["$id"]="$line"
    done < "$OPT_CATALOG"
    _OPT_LOADED=1
}

# opt_field <id> <1..8: category platforms risk profiles description effect rollback verify>
opt_field() {
    opt_load
    local IFS='|'; local -a f; read -r -a f <<< "${OPT_ROW[$1]:-}"
    printf '%s' "${f[$2]:-}"
}

opt_applies_here() {
    local plats; plats=" $(opt_field "$1" 2) "
    [[ "$plats" == *" $OS_ID "* ]] && return 0
    is_linux && [[ "$plats" == *" linux "* ]] && return 0
    is_macos && [[ "$plats" == *" macos "* ]] && return 0
    return 1
}

# ids selected by profile + OPT_INCLUDE - OPT_EXCLUDE, in catalog order
opt_selected() {
    opt_load
    local profile id inc exc
    profile="$(cfg OPT_PROFILE minimal)"
    inc=" $(cfg OPT_INCLUDE | tr ',' ' ') "
    exc=" $(cfg OPT_EXCLUDE | tr ',' ' ') "
    while IFS= read -r id; do
        [[ "$exc" == *" $id "* ]] && continue
        opt_applies_here "$id" || continue
        if [[ "$inc" == *" $id "* ]] || [[ " $(opt_field "$id" 4 | tr ',' ' ') " == *" $profile "* ]]; then
            printf '%s\n' "$id"
        fi
    done < <(awk -F'|' '!/^#/ && NF>3 {print $1}' "$OPT_CATALOG")
}

mod_optimize_wizard() {
    local choice
    ui_choose choice "$(cfg OPT_PROFILE minimal)" "=== OPTIMIZATION LEVEL ===" \
        "minimal:Minimal (reports + safe cleanup only)" \
        "balanced:Balanced (recommended low-risk items)" \
        "performance:Performance (zram, performance power profile)" \
        "gaming:Gaming (performance + Game Mode style tuning)" \
        "developer:Developer (cleanup, journal caps)" \
        "security:Security (safe items only)" \
        "custom:Custom (choose items one by one)"
    cfg_set OPT_PROFILE "$choice" wizard
    [[ "$choice" == custom ]] || return 0
    local inc=() id
    while IFS= read -r id; do
        opt_applies_here "$id" || continue
        ui_say "  ${BOLD}$id${NC} [$(opt_field "$id" 1), risk: $(opt_field "$id" 3)] — $(opt_field "$id" 5)"
        ui_say "     ${DIM}effect: $(opt_field "$id" 6) | rollback: $(opt_field "$id" 7)${NC}"
        ui_confirm "  apply $id" n && inc+=("$id")
    done < <(awk -F'|' '!/^#/ && NF>3 {print $1}' "$OPT_CATALOG")
    cfg_set OPT_INCLUDE "$(IFS=,; printf '%s' "${inc[*]}")" wizard
    return 0
}

mod_optimize_plan() {
    local id ids=()
    mapfile -t ids < <(opt_selected)
    (( ${#ids[@]} )) || { log_info "no optimizations selected for profile $(cfg OPT_PROFILE)"; return 0; }
    for id in "${ids[@]}"; do
        declare -F "opt_${id}" >/dev/null || { log_warn "optimization '$id' has no implementation — skipped"; continue; }
        task_add "optimize.$id" "$(opt_field "$id" 3)" "$(opt_field "$id" 5)" "opt_${id}"
    done
    return 0
}

# ------------------------------------------------------------------ Linux
opt_fstrim_timer() {
    case "$HW_DISK_TYPE" in
        ssd|nvme) ;;
        *) log_info "root disk is '$HW_DISK_TYPE' — fstrim not applicable"; return "$TASK_SKIP" ;;
    esac
    has_systemd || { log_warn "no systemd — skipping fstrim.timer"; return "$TASK_SKIP"; }
    systemctl is-enabled fstrim.timer >/dev/null 2>&1 && { log_info "fstrim.timer already enabled"; return 0; }
    rb_add SERVICE fstrim.timer "$(systemctl is-enabled fstrim.timer 2>/dev/null || echo absent)"
    x_root OPTIMIZE "enable fstrim.timer (weekly TRIM)" -- systemctl enable --now fstrim.timer || return 1
    is_dry_run && return 0
    if systemctl is-enabled fstrim.timer >/dev/null 2>&1; then log_result "fstrim.timer" PASS
    else log_result "fstrim.timer" FAIL; return 1; fi
}

opt_bluetooth_autoenable() {
    has_systemd || return "$TASK_SKIP"
    if ! ls -d /sys/class/bluetooth/* >/dev/null 2>&1; then
        log_info "no Bluetooth adapter detected — skipped"; return "$TASK_SKIP"
    fi
    [[ -f /etc/bluetooth/main.conf ]] && fs_set_kv /etc/bluetooth/main.conf '^#?AutoEnable *=' 'AutoEnable=true' root
    rb_add SERVICE bluetooth "$(systemctl is-enabled bluetooth 2>/dev/null || echo absent)"
    x_root OPTIMIZE "enable bluetooth.service" -- systemctl enable --now bluetooth
}

opt_zram() {
    has_systemd || return "$TASK_SKIP"
    if ! is_dry_run && swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
        log_info "zram swap is already active — not changing it"; return 0
    fi
    pkg_install_ids zram-generator || return 1
    fs_write /etc/systemd/zram-generator.conf root 0644 <<'EOF' || return 1
# Managed by ArCoN v3.0. Delete this file to disable zram.
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
EOF
    x_root OPTIMIZE "reload systemd generators" -- systemctl daemon-reload || return 1
    x_root OPTIMIZE "start systemd-zram-setup@zram0.service" -- systemctl start systemd-zram-setup@zram0.service || return 1
    is_dry_run && return 0
    if swapon --show=NAME --noheadings | grep -q zram; then log_result "zram" PASS "$(swapon --show=NAME,SIZE --noheadings | grep zram | tr -s ' ')"; else log_result "zram" FAIL "no zram device active"; return 1; fi
}

opt_swappiness_report() {
    is_dry_run && { plan_record OPTIMIZE "report vm.swappiness and zram state (read-only)"; return 0; }
    local sw zr
    sw="$(sysctl -n vm.swappiness 2>/dev/null)"
    zr="$(swapon --show=NAME --noheadings 2>/dev/null | grep -c zram)"
    ui_say "  vm.swappiness = ${sw:-unknown}, zram devices: $zr"
    if (( zr > 0 )) && [[ "${sw:-60}" -lt 100 ]]; then
        ui_say "  ${DIM}recommendation: with zram, a higher vm.swappiness (100–180) is usually better${NC}"
    fi
    return 0
}

opt_power_profile() {
    command -v powerprofilesctl >/dev/null 2>&1 || { log_info "power-profiles-daemon not installed — skipped"; return "$TASK_SKIP"; }
    if [[ "$HW_IS_LAPTOP" == yes && "${HW_POWER:-unknown}" == battery ]] && ! is_dry_run; then
        log_info "laptop is on battery — not switching to the performance profile"
        return "$TASK_SKIP"
    fi
    local cur; cur="$(powerprofilesctl get 2>/dev/null)"
    [[ "$cur" == performance ]] && { log_info "power profile already 'performance'"; return 0; }
    rb_add POWER "$cur"
    x_root OPTIMIZE "set power profile to performance (was $cur)" -- powerprofilesctl set performance
}

opt_ananicy() {
    has_systemd || return "$TASK_SKIP"
    pkg_is_installed ananicy-cpp || { log_info "ananicy-cpp not installed — skipped (install it from PKG_GROUPS=power)"; return "$TASK_SKIP"; }
    systemctl is-enabled ananicy-cpp >/dev/null 2>&1 && { log_info "ananicy-cpp already enabled"; return 0; }
    rb_add SERVICE ananicy-cpp "$(systemctl is-enabled ananicy-cpp 2>/dev/null || echo absent)"
    x_root OPTIMIZE "enable ananicy-cpp" -- systemctl enable --now ananicy-cpp
}

opt_pkg_cache_trim() {
    is_arch || return "$TASK_SKIP"
    command -v paccache >/dev/null 2>&1 || pkg_install_ids pacman-contrib || return 1
    is_dry_run && { plan_record OPTIMIZE "paccache -rk2 (keep last 2 versions per package)"; return 0; }
    local before after
    before="$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)"
    x_root OPTIMIZE "paccache -rk2" -- paccache -rk2 || return 1
    after="$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)"
    log_result "package cache trim" PASS "$before -> $after"
}

opt_pkg_cache_clean() {
    is_arch && return "$TASK_SKIP"
    case "$OS_ID" in
        debian|ubuntu) x_root OPTIMIZE "apt-get autoclean" -- env DEBIAN_FRONTEND=noninteractive apt-get autoclean -y ;;
        fedora) x_root OPTIMIZE "dnf clean packages" -- dnf clean packages ;;
        opensuse) x_root OPTIMIZE "zypper clean" -- zypper --non-interactive clean ;;
        macos) return "$TASK_SKIP" ;;
        *) return "$TASK_SKIP" ;;
    esac
}

opt_pkg_cache_purge() {
    log_warn "removing the ENTIRE package cache also removes the ability to downgrade packages"
    ui_confirm "Purge the whole package cache" n || return "$TASK_SKIP"
    rb_note_irreversible "package cache purged (packages must be re-downloaded to downgrade)"
    case "$OS_ID" in
        arch) x_root OPTIMIZE "pacman -Scc" -- pacman -Scc --noconfirm ;;
        debian|ubuntu) x_root OPTIMIZE "apt-get clean" -- apt-get clean ;;
        fedora) x_root OPTIMIZE "dnf clean all" -- dnf clean all ;;
        opensuse) x_root OPTIMIZE "zypper clean --all" -- zypper --non-interactive clean --all ;;
        macos) x_user OPTIMIZE "brew cleanup --prune=all" -- brew cleanup --prune=all ;;
    esac
}

opt_orphans() {
    local orphans=()
    case "$OS_ID" in
        arch) mapfile -t orphans < <(pacman_orphans) ;;
        debian|ubuntu)
            is_dry_run && { plan_record OPTIMIZE "apt-get autoremove --purge (list shown at run time)"; return 0; }
            x_root OPTIMIZE "apt-get autoremove --purge" -- env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
            return $? ;;
        fedora)
            x_root OPTIMIZE "dnf autoremove" -- dnf autoremove -y; return $? ;;
        opensuse)
            log_info "openSUSE: orphan cleanup is handled by 'zypper packages --unneeded' (manual review recommended)"; return "$TASK_SKIP" ;;
        *) return "$TASK_SKIP" ;;
    esac
    (( ${#orphans[@]} )) || { log_info "no orphaned packages"; return 0; }
    ui_say "  orphaned packages (${#orphans[@]}): ${orphans[*]}"
    log_info "orphans to remove: ${orphans[*]}"
    if ! is_dry_run; then ui_confirm "Remove these ${#orphans[@]} orphaned packages" y || return "$TASK_SKIP"; fi
    pkg_remove "${orphans[@]}"
}

opt_journal_vacuum() {
    has_systemd || return "$TASK_SKIP"
    is_dry_run && { plan_record OPTIMIZE "journalctl --vacuum-size=500M ($(as_root journalctl --disk-usage 2>/dev/null))"; return 0; }
    rb_note_irreversible "systemd journal trimmed to 500M (older entries deleted)"
    x_root OPTIMIZE "journalctl --vacuum-size=500M" -- journalctl --vacuum-size=500M
}

opt_service_report() {
    is_dry_run && { plan_record OPTIMIZE "report slowest boot units and failed units (read-only)"; return 0; }
    if is_linux; then
        has_systemd || return "$TASK_SKIP"
        ui_say "  ${BOLD}slowest boot units:${NC}"
        systemd-analyze blame 2>/dev/null | head -n 5 | sed 's/^/    /'
        local failed; failed="$(systemctl --failed --no-legend 2>/dev/null | wc -l | tr -d ' ')"
        ui_say "  failed units: $failed"
        (( failed > 0 )) && systemctl --failed --no-legend | sed 's/^/    /'
    fi
    return 0
}

# ------------------------------------------------------------------ macOS
opt_brew_cleanup()       { x_user OPTIMIZE "brew cleanup --prune=30" -- brew cleanup --prune=30; }
opt_launch_items_report() {
    is_dry_run && { plan_record OPTIMIZE "list third-party launch agents/daemons (read-only)"; return 0; }
    ui_say "  ${BOLD}third-party launch items:${NC}"
    find /Library/LaunchAgents /Library/LaunchDaemons "$ARCON_HOME/Library/LaunchAgents" \
        -mindepth 1 -maxdepth 1 -name '*.plist' 2>/dev/null | sed 's/^/    /' | head -n 30
    return 0
}
opt_power_report() {
    is_dry_run && { plan_record OPTIMIZE "report pmset settings (read-only)"; return 0; }
    pmset -g 2>/dev/null | sed 's/^/    /' | head -n 20; return 0
}
opt_cache_report() {
    is_dry_run && { plan_record OPTIMIZE "report ~/Library/Caches size (read-only)"; return 0; }
    ui_say "  ~/Library/Caches: $(du -sh "$ARCON_HOME/Library/Caches" 2>/dev/null | cut -f1)"
    ui_say "  ${DIM}ArCoN does not delete application caches automatically${NC}"
    return 0
}
