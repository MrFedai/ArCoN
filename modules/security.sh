#!/usr/bin/env bash
# ArCoN v3.0 -- modules/security.sh
# v2.5 "Sector 9: Security & System Optimizations" (tools, dashboard, scans,
# hardening, Hardened Mode). The optimization steps of that sector moved to
# modules/optimize.sh (catalogued, per-item risk/rollback).
#
# v2.5 → v3.0
#   * tools installed with pacman on every distro          → catalog per platform
#   * UFW configured although it was never installed       → ufw/firewalld installed first;
#                                                            firewalld on Fedora/openSUSE
#   * "Firejail (Sandbox All)" step name never matched the
#     case branch "Sandbox Integration" → firecfg NEVER ran → fixed, opt-in (SEC_FIREJAIL_FIRECFG)
#   * clamscan ran on /home/$USER with no --infected filter → same scan, results captured to a report file
#   * sshd_config edited in place (sed) without validation  → drop-in file + `sshd -t` validation
#   * Hardened Mode nested inside "Apply All Hardening Fixes"
#     (unreachable if hardening declined)                  → independent SEC_HARDENED_MODE
#   * `yay -S opensnitch opensnitch-ui` (opensnitch-ui does
#     not exist; UI ships inside opensnitch)               → opensnitch only
#   * USBGuard policy generated with no confirmation        → destructive-word confirmation
#                                                            (can lock out USB keyboards)
#   * root login disabled with sed on two patterns          → single validated drop-in

ARCON_MODULE=security
SEC_TOOL_IDS=(arch-audit clamav clamav-freshclam rkhunter lynis firejail nethogs)
SSHD_DROPIN=/etc/ssh/sshd_config.d/00-arcon-hardening.conf
SYSCTL_FILE=/etc/sysctl.d/99-security.conf

mod_security_wizard() {
    ui_confirm "Install security tools (arch-audit, clamav, rkhunter, lynis, firejail, nethogs)" y &&
        cfg_set SEC_TOOLS yes wizard || cfg_set SEC_TOOLS no wizard
    ui_confirm "Enable the firewall (deny incoming, allow outgoing)" y &&
        cfg_set SEC_FIREWALL yes wizard || cfg_set SEC_FIREWALL no wizard
    security_dashboard
    ui_say "\n${DIM}(Scans run arch-audit, Lynis, ClamAV home scan and rkhunter sequentially — this can take a long time)${NC}"
    ui_confirm "Start security scans" n && cfg_set SEC_SCAN yes wizard || cfg_set SEC_SCAN no wizard

    ui_say "\n${BOLD}Proposed hardening plan:${NC}"
    ui_say "   ${CYAN}1. System update:${NC}      patch vulnerable packages"
    ui_say "   ${CYAN}2. Kernel hardening:${NC}   sysctl rules (dmesg/kptr restrictions, sysrq off)"
    ui_say "   ${CYAN}3. SSH hardening:${NC}      disable root login (optionally password auth)"
    ui_say "   ${CYAN}4. Network security:${NC}   block redirects and source routing"
    if ui_confirm "Apply all hardening fixes" n; then
        cfg_set SEC_HARDEN_SYSCTL yes wizard; cfg_set SEC_HARDEN_SSH yes wizard
        ui_say "${RED}[WARNING] Do NOT disable password authentication before your SSH public key works!${NC}"
        ui_confirm "Disable SSH password authentication (key-only access)" n && cfg_set SEC_SSH_DISABLE_PASSWORD yes wizard
    fi
    ui_say "\n${BOLD}HARDENED MODE (OpenSnitch + USBGuard)${NC}"
    ui_say "${CYAN}1. OpenSnitch (application firewall):${NC}"
    ui_say "   ${GREEN}[+]${NC} blocks apps from phoning home, detects telemetry"
    ui_say "   ${RED}[-]${NC} frequent pop-ups at first — you must allow/deny each connection"
    ui_say "${CYAN}2. USBGuard (physical port security):${NC}"
    ui_say "   ${GREEN}[+]${NC} prevents BadUSB attacks, blocks unauthorized devices"
    ui_say "   ${RED}[-]${NC} new USB devices stay blocked until you allow them manually"
    ui_confirm "Activate Hardened Mode" n && cfg_set SEC_HARDENED_MODE yes wizard || cfg_set SEC_HARDENED_MODE no wizard
    return 0
}

security_dashboard() {
    ui_say ""
    ui_header "SECURITY & TOOLS DASHBOARD"
    ui_table "${BOLD}TOOL|FUNCTION|STATUS${NC}" \
        "Arch-Audit|Vulnerability scanner (CVE check)|$(_sec_tool_status arch-audit)" \
        "Lynis|System hardening & audit tool|$(_sec_tool_status lynis)" \
        "ClamAV|Antivirus engine|$(_sec_tool_status clamscan)" \
        "Rkhunter|Rootkit & backdoor hunter|$(_sec_tool_status rkhunter)" \
        "Firejail|Application sandboxing|$(_sec_tool_status firejail)" \
        "Nethogs|Per-app network traffic monitor|$(_sec_tool_status nethogs)"
}

_sec_tool_status() { command -v "$1" >/dev/null 2>&1 && printf '%b' "${GREEN}installed${NC}" || printf '%b' "${DIM}missing${NC}"; }

mod_security_plan() {
    cfg_bool SEC_TOOLS && task_add security.tools low "Install security tools" security_tools
    cfg_bool SEC_FIREWALL && task_add security.firewall medium "Enable firewall (deny incoming / allow outgoing)" security_firewall
    if cfg_bool SEC_TOOLS; then
        task_add security.clamav low "Update ClamAV signature database" security_clamav
        task_add security.rkhunter low "Update rkhunter file properties database" security_rkhunter
        cfg_bool SEC_FIREJAIL_FIRECFG && task_add security.firecfg medium "Firejail sandbox integration (firecfg)" security_firecfg
    fi
    cfg_bool SEC_SCAN && task_add security.scan low "Run security scans (report saved)" security_scan
    cfg_bool SEC_HARDEN_SYSCTL && task_add security.sysctl medium "Apply kernel/network sysctl hardening" security_sysctl
    cfg_bool SEC_HARDEN_SSH && task_add security.ssh high "Harden SSH (validated drop-in)" security_ssh
    if cfg_bool SEC_HARDENED_MODE; then
        task_add security.opensnitch medium "Install and enable OpenSnitch" security_opensnitch
        task_add security.usbguard high "Install USBGuard and authorize current devices" security_usbguard
    fi
    return 0
}

security_tools() {
    local ids=() i
    for i in "${SEC_TOOL_IDS[@]}"; do
        catalog_has "$i" || continue
        [[ "$(catalog_field "$i" "$(platform_catalog_column)")" == "-" ]] && { log_info "$i: not packaged for $OS_ID — skipped"; continue; }
        ids+=("$i")
    done
    pkg_install_ids "${ids[@]}"
}

security_firewall() {
    case "$OS_ID" in
        arch|debian|ubuntu) security_firewall_ufw ;;
        fedora|opensuse) security_firewall_firewalld ;;
        macos) security_firewall_macos ;;
        *) log_warn "no firewall backend for $OS_ID"; return "$TASK_SKIP" ;;
    esac
}

security_firewall_ufw() {
    command -v ufw >/dev/null 2>&1 || pkg_install_ids ufw || return 1
    is_dry_run && { plan_record SERVICE "ufw: default deny incoming, allow outgoing, enable (SSH port kept open if sshd is active)"; return 0; }
    x_root SETTING "ufw default deny incoming" -- ufw default deny incoming || return 1
    x_root SETTING "ufw default allow outgoing" -- ufw default allow outgoing || return 1
    # v2.5 enabled ufw with a default-deny policy without allowing SSH: that locks out remote sessions
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        log_warn "sshd is running — allowing SSH so this machine stays reachable"
        x_root SETTING "ufw allow ssh" -- ufw allow ssh || return 1
    fi
    rb_add SERVICE ufw "$(systemctl is-enabled ufw 2>/dev/null || echo absent)"
    x_root SERVICE "enable ufw" -- ufw --force enable || return 1
    ufw status | head -n1 | grep -q active && log_result "firewall (ufw)" PASS || { log_result "firewall (ufw)" FAIL; return 1; }
}

security_firewall_firewalld() {
    command -v firewall-cmd >/dev/null 2>&1 || pkg_install firewalld || return 1
    is_dry_run && { plan_record SERVICE "firewalld: enable, default zone target DROP for incoming"; return 0; }
    rb_add SERVICE firewalld "$(systemctl is-enabled firewalld 2>/dev/null || echo absent)"
    x_root SERVICE "enable firewalld" -- systemctl enable --now firewalld || return 1
    firewall-cmd --state >/dev/null 2>&1 && log_result "firewall (firewalld)" PASS "default zone: $(firewall-cmd --get-default-zone 2>/dev/null)" || { log_result "firewall (firewalld)" FAIL; return 1; }
}

security_firewall_macos() {
    is_dry_run && { plan_record SETTING "macOS application firewall: globalstate=1"; return 0; }
    x_root SETTING "enable macOS application firewall" -- /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on || return 1
    log_result "firewall (macOS)" PASS
}

security_clamav() {
    command -v freshclam >/dev/null 2>&1 || { log_info "clamav not installed — skipped"; return "$TASK_SKIP"; }
    local unit=clamav-freshclam
    systemctl list-unit-files 2>/dev/null | grep -q '^clamav-freshclam' || unit=freshclam
    if is_dry_run; then plan_record SERVICE "stop $unit, run freshclam, enable $unit"; return 0; fi
    as_root systemctl stop "$unit" 2>/dev/null || true
    x_root COMMAND "update ClamAV signatures" -- freshclam || log_warn "freshclam failed (rate-limited? check /var/log/clamav)"
    rb_add SERVICE "$unit" "$(systemctl is-enabled "$unit" 2>/dev/null || echo absent)"
    x_root SERVICE "enable $unit" -- systemctl enable --now "$unit" || log_warn "could not enable $unit"
}

security_rkhunter() {
    command -v rkhunter >/dev/null 2>&1 || { log_info "rkhunter not installed — skipped"; return "$TASK_SKIP"; }
    x_root COMMAND "rkhunter --propupd (baseline of file properties)" -- rkhunter --propupd
}

security_firecfg() {
    command -v firecfg >/dev/null 2>&1 || { log_info "firejail not installed — skipped"; return "$TASK_SKIP"; }
    log_warn "firecfg symlinks many programs into firejail; some apps may lose access to files outside \$HOME"
    ui_confirm "Run firecfg (Firejail sandbox integration for all supported programs)" n || return "$TASK_SKIP"
    rb_add NOTE "firecfg created symlinks in /usr/local/bin (undo: sudo firecfg --clean)"
    x_root SETTING "firejail sandbox integration (firecfg)" -- firecfg
}

security_scan() {
    local report; report="$ARCON_LOG_DIR/security-scan-$(date +%Y%m%d-%H%M%S).log"
    if is_dry_run; then plan_record COMMAND "read-only scans: arch-audit, lynis audit system --quick, clamscan -r $ARCON_HOME, rkhunter --check --sk (report: $ARCON_LOG_DIR)"; return 0; fi
    : > "$report"
    ui_say "\n${MAGENTA}>>> arch-audit (package vulnerabilities)${NC}"
    if command -v arch-audit >/dev/null 2>&1; then arch-audit 2>&1 | tee -a "$report"
    else log_info "arch-audit not available on $OS_ID (Arch only)"; fi
    ui_say "\n${MAGENTA}>>> Lynis (system audit, quick mode)${NC}"
    command -v lynis >/dev/null 2>&1 && as_root lynis audit system --quick 2>&1 | tee -a "$report" | tail -n 25
    ui_say "\n${MAGENTA}>>> ClamAV (home directory scan)${NC}"
    command -v clamscan >/dev/null 2>&1 && clamscan -r "$ARCON_HOME" --bell 2>&1 | tee -a "$report" | tail -n 15
    ui_say "\n${MAGENTA}>>> rkhunter (rootkit check)${NC}"
    command -v rkhunter >/dev/null 2>&1 && as_root rkhunter --check --sk 2>&1 | tee -a "$report" | tail -n 20
    log_info "full scan output: $report"
    log_result "security scans" PASS "report: $report"
}

security_sysctl() {
    if ! is_linux; then log_warn "sysctl hardening: Linux only"; return "$TASK_SKIP"; fi
    fs_write "$SYSCTL_FILE" root 0644 <<'EOF'
# Managed by ArCoN v3.0 (modules/security.sh). Remove this file to revert.
# KERNEL SECURITY
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
fs.protected_fifos = 2
fs.protected_regular = 2
# NETWORK SECURITY
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
EOF
    [[ $? -eq 0 ]] || return 1
    x_root SETTING "reload sysctl settings" -- sysctl --system || return 1
    is_dry_run && return 0
    local v; v="$(sysctl -n kernel.kptr_restrict 2>/dev/null)"
    [[ "$v" == 2 ]] && log_result "sysctl hardening" PASS "kernel.kptr_restrict=$v" || { log_result "sysctl hardening" FAIL "kernel.kptr_restrict=$v"; return 1; }
}

security_ssh() {
    if ! is_linux; then log_warn "SSH hardening: Linux only in v3.0"; return "$TASK_SKIP"; fi
    [[ -f /etc/ssh/sshd_config ]] || { log_warn "/etc/ssh/sshd_config not found — OpenSSH server not installed, skipped"; return "$TASK_SKIP"; }
    if ! grep -q 'sshd_config.d' /etc/ssh/sshd_config; then
        log_warn "this sshd does not include /etc/ssh/sshd_config.d/*.conf — appending the Include directive"
        fs_append_once /etc/ssh/sshd_config "Include /etc/ssh/sshd_config.d/*.conf" root || return 1
    fi
    local pw="yes"; cfg_bool SEC_SSH_DISABLE_PASSWORD && pw="no"
    [[ "$pw" == no ]] && log_warn "password authentication will be DISABLED — make sure your public key is in ~/.ssh/authorized_keys"
    fs_write "$SSHD_DROPIN" root 0600 <<EOF
# Managed by ArCoN v3.0 (modules/security.sh). Delete this file to revert.
PermitRootLogin no
PasswordAuthentication $pw
EOF
    [[ $? -eq 0 ]] || return 1
    if ! is_dry_run; then
        if ! as_root sshd -t 2>&1 | tee -a "$(log_file)"; then
            log_error "sshd rejected the new configuration — reverting $SSHD_DROPIN"
            as_root rm -f "$SSHD_DROPIN"
            return 1
        fi
    fi
    local unit=sshd
    systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service' || unit=ssh
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        x_root SERVICE "reload $unit" -- systemctl reload "$unit" || return 1
    else
        log_info "$unit is not running; the configuration applies at next start"
    fi
    log_result "SSH hardening" PASS "root login disabled, PasswordAuthentication=$pw"
}

security_opensnitch() {
    if ! is_linux; then log_warn "OpenSnitch: Linux only"; return "$TASK_SKIP"; fi
    if [[ "$(catalog_field opensnitch "$(platform_catalog_column)")" == "-" ]]; then
        log_warn "OpenSnitch is not packaged for $OS_ID — see https://github.com/evilsocket/opensnitch/releases (manual install)"
        rb_add NOTE "OpenSnitch not installed automatically on $OS_ID (documented manual step)"
        return "$TASK_SKIP"
    fi
    pkg_install_ids opensnitch || return 1
    is_debian_like && pkg_install_ids python3-opensnitch-ui
    rb_add SERVICE opensnitchd "$(systemctl is-enabled opensnitchd 2>/dev/null || echo absent)"
    x_root SERVICE "enable opensnitchd" -- systemctl enable --now opensnitchd || return 1
    local desktop=/usr/share/applications/opensnitch_ui.desktop
    [[ -f "$desktop" ]] && fs_install_file "$desktop" "$ARCON_HOME/.config/autostart/opensnitch_ui.desktop"
    log_warn "OpenSnitch is active — watch for connection pop-ups"
}

security_usbguard() {
    if ! is_linux; then log_warn "USBGuard: Linux only"; return "$TASK_SKIP"; fi
    pkg_install_ids usbguard || return 1
    if [[ -s /etc/usbguard/rules.conf ]]; then
        log_info "/etc/usbguard/rules.conf already exists — not regenerating"
    else
        if is_dry_run; then
            plan_record FILE "/etc/usbguard/rules.conf <- usbguard generate-policy (authorizes currently connected devices)"
        else
            log_warn "USBGuard will BLOCK every USB device that is not connected right now (including keyboards plugged in later)"
            ui_confirm_word "This can lock you out of USB input devices. Continue" USBGUARD || return "$TASK_SKIP"
            local tmp="$ARCON_TMP/usbguard-rules.conf"
            as_root usbguard generate-policy > "$tmp" || { log_error "usbguard generate-policy failed"; return 1; }
            [[ -s "$tmp" ]] || { log_error "generated USBGuard policy is empty — refusing to install it"; return 1; }
            fs_install_file "$tmp" /etc/usbguard/rules.conf root 0600 || return 1
        fi
    fi
    rb_add SERVICE usbguard "$(systemctl is-enabled usbguard 2>/dev/null || echo absent)"
    x_root SERVICE "enable usbguard" -- systemctl enable --now usbguard || return 1
    log_warn "new USB devices are blocked by default: sudo usbguard list-devices / allow-device <id>"
}
