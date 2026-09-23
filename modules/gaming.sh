#!/usr/bin/env bash
# ArCoN v3.0 -- modules/gaming.sh
# v2.5 "Sector 2B: Gaming Mode".
#
# v2.5 → v3.0
#   * only offered when GNOME step ran (artificial coupling)  → independent module
#   * GPU chosen manually                                     → auto-detected (sysfs PCI), manual override
#   * NVIDIA: userspace only (no kernel module)               → nvidia-open / nvidia-open-dkms + headers
#   * AMD/Intel: missing lib32 Vulkan drivers                 → lib32-vulkan-radeon / lib32-vulkan-intel
#   * installer output discarded, failures hidden             → logged, verified, reported
#   * gamemode.ini written to ~/.config/gamemode/gamemode.ini → ~/.config/gamemode.ini
#     (GameMode never read the v2.5 path: README "XDG_CONFIG_HOME or $HOME/.config/")
#   * Arch only                                               → Debian/Ubuntu/Fedora/openSUSE/macOS paths
# No FPS gains are claimed: verification checks that Vulkan and GameMode work.

ARCON_MODULE=gaming

gaming_supported() { is_linux || is_macos; }

mod_gaming_wizard() {
    if ! ui_confirm "Install Gaming Mode (Steam, GPU drivers, GameMode)" "$(cfg_bool GAMING && echo y || echo n)"; then
        cfg_set GAMING no wizard; return 0
    fi
    cfg_set GAMING yes wizard
    is_macos && return 0
    local detected; detected="$(hw_primary_gpu)"
    ui_say "  Detected GPU vendor(s): ${BOLD}${HW_GPU_VENDORS}${NC} — ${HW_GPU_NAMES}"
    local choice
    ui_choose choice auto "Select GPU driver set:" \
        "auto:Auto (detected: $detected)" "nvidia:NVIDIA" "amd:AMD" "intel:Intel" "skip:Skip drivers"
    cfg_set GAMING_GPU "$choice" wizard
    ui_confirm "Also install MangoHud + Vulkan tools" y && cfg_set GAMING_EXTRAS mangohud,vulkan-tools wizard
    return 0
}

gaming_gpu() {
    local g; g="$(cfg GAMING_GPU auto)"
    [[ "$g" == auto ]] && g="$(hw_primary_gpu)"
    [[ "$g" == apple || "$g" == unknown ]] && g=skip
    printf '%s' "$g"
}

mod_gaming_plan() {
    cfg_bool GAMING || return 0
    local gpu; gpu="$(gaming_gpu)"
    case "$OS_ID" in
        arch)
            cfg_bool GAMING_ENABLE_MULTILIB yes && task_add gaming.multilib medium "Enable [multilib] repository (32-bit libraries for Steam)" gaming_arch_multilib
            [[ "$gpu" != skip ]] && task_add gaming.gpu medium "Install $gpu GPU driver stack" gaming_arch_gpu ;;
        ubuntu)
            [[ "$gpu" == nvidia ]] && task_add gaming.gpu medium "Install recommended NVIDIA driver (ubuntu-drivers)" gaming_ubuntu_nvidia
            [[ "$gpu" == amd || "$gpu" == intel ]] && task_add gaming.gpu low "Install Mesa Vulkan drivers" gaming_mesa_generic ;;
        debian|fedora|opensuse)
            [[ "$gpu" == nvidia ]] && task_add gaming.gpu_info low "Explain NVIDIA driver installation for $OS_ID" gaming_nvidia_info
            [[ "$gpu" == amd || "$gpu" == intel ]] && task_add gaming.gpu low "Install Mesa Vulkan drivers" gaming_mesa_generic ;;
    esac
    task_add gaming.steam low "Install Steam" gaming_steam
    is_linux && task_add gaming.gamemode low "Install and configure GameMode" gaming_gamemode
    [[ -n "$(cfg GAMING_EXTRAS)" ]] && task_add gaming.extras low "Install gaming extras ($(cfg GAMING_EXTRAS))" gaming_extras
    is_linux && task_add gaming.verify low "Verify Vulkan / GameMode" gaming_verify
    return 0
}

gaming_arch_multilib() {
    local conf="${ARCON_SYSROOT}/etc/pacman.conf"
    if grep -q '^\[multilib\]' "$conf"; then log_info "multilib already enabled"; return 0; fi
    grep -q '^#\[multilib\]' "$conf" || { log_error "no [multilib] section found in $conf"; return 1; }
    local tmp; tmp="$(mktemp)"
    # uncomment "[multilib]" and the Include line that directly follows it
    awk '/^#\[multilib\]$/ { print "[multilib]"; m=1; next }
         m==1 && /^#Include/ { sub(/^#/, ""); print; m=0; next }
         { m=0; print }' "$conf" > "$tmp"
    fs_install_file "$tmp" /etc/pacman.conf root 0644; local rc=$?
    rm -f "$tmp"
    (( rc == 0 )) || return $rc
    plan_record REPO "enable [multilib] in /etc/pacman.conf"
    pkg_upgrade_all   # -Syu: sync the new repo without a partial upgrade
    unset '_PACMAN_SYNC_LOADED'; _PACMAN_SYNC_LOADED=0
}

# kernels installed -> matching header packages (for DKMS)
_arch_kernels() { pacman -Qq 2>/dev/null | grep -xE 'linux|linux-lts|linux-zen|linux-hardened|linux-rt|linux-rt-lts'; }

gaming_arch_gpu() {
    local gpu pk=(); gpu="$(gaming_gpu)"
    case "$gpu" in
        nvidia)
            if cfg_bool GAMING_NVIDIA_KMOD yes; then
                local kernels; mapfile -t kernels < <(_arch_kernels)
                if [[ "${kernels[*]}" == linux ]]; then pk+=(nvidia-open)
                else
                    pk+=(nvidia-open-dkms)
                    local k; for k in "${kernels[@]}"; do pk+=("${k}-headers"); done
                    (( ${#kernels[@]} )) || { log_warn "no known kernel package found; add headers for your kernel manually"; }
                fi
                log_warn "nvidia-open supports Turing (GTX 16xx / RTX 20xx) and newer. Older GPUs need a legacy driver — see https://wiki.archlinux.org/title/NVIDIA"
            fi
            pk+=(nvidia-utils lib32-nvidia-utils nvidia-settings) ;;
        amd)   pk+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu) ;;
        intel) pk+=(mesa lib32-mesa vulkan-intel lib32-vulkan-intel) ;;
        *) return "$TASK_SKIP" ;;
    esac
    pkg_install "${pk[@]}" || return 1
    if [[ "$gpu" == nvidia ]] && ! is_dry_run; then
        rb_add NOTE "NVIDIA kernel module installed; a reboot is required. Initramfs/bootloader were not modified by ArCoN."
        log_warn "reboot required to load the NVIDIA kernel module"
    fi
}

gaming_mesa_generic() { pkg_install_ids mesa vulkan-radeon vulkan-intel; }

gaming_ubuntu_nvidia() {
    command -v ubuntu-drivers >/dev/null 2>&1 || pkg_install ubuntu-drivers-common || return 1
    ui_confirm "Install the NVIDIA driver recommended by 'ubuntu-drivers' (Ubuntu official tool)" y || return "$TASK_SKIP"
    x_root PKG_INSTALL "ubuntu-drivers install (recommended NVIDIA driver)" -- ubuntu-drivers install || return 1
    rb_add NOTE "NVIDIA driver installed by ubuntu-drivers; reboot required"
}

gaming_nvidia_info() {
    case "$OS_ID" in
        debian)   log_warn "Debian: NVIDIA drivers need the non-free component (nvidia-driver). ArCoN does not change repositories automatically — see https://wiki.debian.org/NvidiaGraphicsDrivers" ;;
        fedora)   log_warn "Fedora: NVIDIA drivers come from RPM Fusion (akmod-nvidia). ArCoN does not add third-party repositories automatically — see https://rpmfusion.org/Howto/NVIDIA" ;;
        opensuse) log_warn "openSUSE: use the official NVIDIA repository (zypper install-new-recommends / openSUSE-repos-*-NVIDIA) — see https://en.opensuse.org/SDB:NVIDIA_drivers" ;;
    esac
    rb_add NOTE "NVIDIA driver not installed automatically on $OS_ID (documented manual step)"
    return 0
}

gaming_steam() {
    case "$OS_ID" in
        arch|macos) pkg_install_ids steam ;;
        *)
            # Steam is not in the default repos of Debian/Fedora/openSUSE/Ubuntu main;
            # Flathub is Valve-supported and needs no repository/arch changes.
            log_info "Steam on $OS_ID: using Flathub (com.valvesoftware.Steam)"
            if ! cfg_bool PKG_ALLOW_FLATPAK && ! ui_confirm "Install Steam from Flathub (adds the Flathub remote if missing)" y; then
                return "$TASK_SKIP"
            fi
            flatpak_install com.valvesoftware.Steam ;;
    esac
}

gaming_gamemode() {
    local ids=(gamemode); is_arch && ids+=(lib32-gamemode)
    pkg_install_ids "${ids[@]}" || return 1
    if cfg_bool GAMING_GAMEMODE_CONFIG yes; then
        printf '[general]\ndesiredgov=performance\nigpu_desiredgov=performance\n' |
            fs_write "$ARCON_HOME/.config/gamemode.ini" || return 1
    fi
    if getent group gamemode >/dev/null 2>&1 || is_dry_run; then
        if id -nG "$ARCON_USER" 2>/dev/null | tr ' ' '\n' | grep -qx gamemode; then
            log_info "$ARCON_USER already in group gamemode"
        else
            x_root SETTING "add $ARCON_USER to group gamemode (CPU governor/renice permission)" -- usermod -aG gamemode "$ARCON_USER" || return 1
            rb_add NOTE "user $ARCON_USER added to group gamemode (remove: gpasswd -d $ARCON_USER gamemode)"
        fi
    fi
}

gaming_extras() {
    local ids=() e
    for e in $(cfg GAMING_EXTRAS | tr ',' ' '); do
        ids+=("$e"); is_arch && catalog_has "lib32-$e" && ids+=("lib32-$e")
    done
    pkg_install_ids "${ids[@]}"
}

gaming_verify() {
    is_dry_run && { plan_record COMMAND "verify: vulkaninfo --summary, gamemoded -t"; return 0; }
    local ok=0
    if command -v vulkaninfo >/dev/null 2>&1; then
        if vulkaninfo --summary >/dev/null 2>&1; then log_result "Vulkan" PASS "$(vulkaninfo --summary 2>/dev/null | awk -F'= ' '/deviceName/{print $2; exit}')"
        else log_result "Vulkan" WARN "vulkaninfo failed (reboot may be required after driver install)"; fi
    else log_result "Vulkan" SKIP "vulkan-tools not installed"; fi
    if command -v gamemoded >/dev/null 2>&1; then
        log_result "GameMode" PASS "$(gamemoded -v 2>/dev/null | head -n1)"
    else log_result "GameMode" FAIL "gamemoded not found"; ok=1; fi
    log_info "no FPS change is claimed; measure with MangoHud (MANGOHUD=1 %command%) before/after"
    return $ok
}
