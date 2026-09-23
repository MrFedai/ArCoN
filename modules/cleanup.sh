#!/usr/bin/env bash
# ArCoN v3.0 -- modules/cleanup.sh + final summary + reboot prompt
# v2.5 "FINAL CLEANUP SECTION", "SECTOR 10: FINAL SUMMARY" and the reboot prompt.
#
# v2.5 → v3.0
#   * cleanup ran `pacman -Scc` (full cache wipe) on every OS, even Debian
#     → the cleanup items now come from data/optimizations.catalog per platform
#   * summary used `pacman -Qi` on every OS (always "Skipped" elsewhere)
#     → platform-aware status, plus the real task results of this run
#   * "Packages: Processed" / "Shell & Term: Configured" printed unconditionally,
#     even when those steps failed or never ran (false success)
#     → status comes from the task state (done / failed / skipped / not selected)

ARCON_MODULE=cleanup

mod_cleanup_wizard() {
    ui_confirm "Remove unnecessary leftovers (orphans, package cache, temp files)" n &&
        cfg_set CLEANUP yes wizard || cfg_set CLEANUP no wizard
    return 0
}

mod_cleanup_plan() {
    cfg_bool CLEANUP || return 0
    if is_arch; then task_add cleanup.cache low "Trim package cache (keep last 2 versions)" opt_pkg_cache_trim
    else task_add cleanup.cache low "Clean obsolete package downloads" opt_pkg_cache_clean; fi
    task_add cleanup.orphans medium "Remove orphaned packages (list shown first)" opt_orphans
    task_add cleanup.temp low "Remove ArCoN temporary files" cleanup_temp
    return 0
}

cleanup_temp() {
    local n=0 f
    for f in "$ARCON_ROOT"/strap.sh "$ARCON_ROOT"/install_ax.sh "$ARCON_ROOT"/gno_final.conf; do
        [[ -f "$f" ]] && { fs_remove "$f" && n=$((n + 1)); }
    done
    log_info "removed $n leftover file(s) from earlier ArCoN versions"
    return 0
}

# --------------------------------------------------------------- summary
_sum_status() {
    # _sum_status <task-id-prefix> <label-when-absent>
    local prefix="$1" absent="${2:-Not selected}" id best=""
    for id in "${TASK_IDS[@]}"; do
        [[ "$id" == "$prefix"* ]] || continue
        case "${TASK_STATUS[$id]}" in
            failed) best=failed; break ;;
            done) [[ "$best" == skipped || -z "$best" ]] && best='done' ;;
            skipped) [[ -z "$best" ]] && best=skipped ;;
            pending|running) [[ -z "$best" ]] && best=pending ;;
        esac
    done
    case "$best" in
        done)    printf '%b' "${GREEN}Applied${NC}" ;;
        failed)  printf '%b' "${RED}FAILED (see log)${NC}" ;;
        skipped) printf '%b' "${YELLOW}Skipped${NC}" ;;
        pending) printf '%b' "${YELLOW}Not completed${NC}" ;;
        *)       printf '%b' "${DIM}${absent}${NC}" ;;
    esac
}

summary_print() {
    local ba_status hypr_status sec_status hard_status gamemode_status
    if is_arch; then
        pacman_repo_enabled blackarch && ba_status="${GREEN}Active${NC}" || ba_status="${DIM}Inactive${NC}"
    else
        ba_status="${DIM}n/a (Arch only)${NC}"
    fi
    if is_linux; then
        pkg_is_installed hyprland && hypr_status="${GREEN}Installed${NC}" || hypr_status="${DIM}Not installed${NC}"
        [[ -f /etc/sysctl.d/99-security.conf ]] && sec_status="${GREEN}Applied (hardened)${NC}" || sec_status="${YELLOW}Standard${NC}"
        if systemctl is-active --quiet opensnitchd 2>/dev/null || systemctl is-active --quiet usbguard 2>/dev/null; then
            hard_status="${GREEN}Active${NC}"; else hard_status="${DIM}Disabled${NC}"; fi
    else
        hypr_status="${DIM}n/a${NC}"; sec_status="${DIM}n/a${NC}"; hard_status="${DIM}n/a${NC}"
    fi
    pkg_is_installed gamemode && gamemode_status="${GREEN}Ready${NC}" || gamemode_status="${DIM}Not installed${NC}"

    ui_header "INSTALLATION SUMMARY"
    ui_table \
        "OS|${OS_NAME} (${OS_ID}/${HW_ARCH}, support: ${OS_SUPPORT})" \
        "Base system|$(_sum_status base.)" \
        "Packages|$(_sum_status packages.)" \
        "BlackArch repo|$ba_status  $(_sum_status blackarch. 'Not selected')" \
        "GNOME config|$(_sum_status gnome.)" \
        "Gaming mode|$gamemode_status  $(_sum_status gaming. 'Not selected')" \
        "Hyprland env|$hypr_status  $(_sum_status hyprland. 'Not selected')" \
        "Terminal & shell|$(_sum_status terminal.) / $(_sum_status shell.)" \
        "Security tools|$(_sum_status security.)" \
        "Hardening (sysctl)|$sec_status" \
        "Hardened mode|$hard_status" \
        "Optimizations|$(_sum_status optimize.)" \
        "GPU driver|${HW_GPU_VENDORS} ($(cfg GAMING_GPU auto))" \
        "Log file|$(log_file)" \
        "Run directory|${ARCON_RUN_DIR:-n/a}"
    local failed=0 id
    for id in "${TASK_IDS[@]}"; do [[ "${TASK_STATUS[$id]}" == failed ]] && failed=$((failed + 1)); done
    if (( failed == 0 )); then
        ui_say "\n${GREEN}Installation complete.${NC}"
    else
        ui_say "\n${RED}Finished with $failed failed step(s).${NC} Re-run with ${BOLD}--resume${NC} after fixing the cause, or undo with ${BOLD}--rollback${NC}."
    fi
}

# --------------------------------------------------------------- reboot
reboot_prompt() {
    is_dry_run && return 0
    local need=0 id
    for id in "${TASK_IDS[@]}"; do
        [[ "${TASK_STATUS[$id]}" == 'done' ]] || continue
        case "$id" in gaming.gpu|security.usbguard|optimize.zram|blackarch.enable) need=1 ;; esac
    done
    if (( need == 0 )) && ! cfg_bool REBOOT; then
        log_info "no reboot-requiring change was applied"
        return 0
    fi
    ui_say "\n${YELLOW}[!] A reboot is recommended to apply all changes.${NC}"
    if cfg_bool REBOOT || ui_confirm "Reboot now" n; then
        ui_say "${BLUE}[*] Rebooting in 5 seconds... (Ctrl+C to cancel)${NC}"
        sleep 5
        x_root COMMAND "reboot" -- systemctl reboot || as_root reboot
    fi
}
