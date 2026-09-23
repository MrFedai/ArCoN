#!/usr/bin/env bash
# ArCoN v3.0 -- platform/hardware.sh
# HardwareDetector: one facade (hw_detect) with Linux / macOS / Mock backends.
#
# Results (HW_*), detected once per run and cached in $ARCON_RUN_DIR/hardware.env:
#   HW_ARCH HW_CPU_VENDOR HW_CPU_MODEL HW_CPU_CORES HW_CPU_THREADS
#   HW_GPU_VENDORS (space list: nvidia amd intel apple virtual unknown)  HW_GPU_NAMES
#   HW_RAM_MB HW_DISK_TYPE (nvme|ssd|hdd|unknown) HW_DISK_FREE_GB HW_ROOT_FS
#   HW_NET_IFACES HW_VIRT (none|<hypervisor>|container:<type>|wsl) HW_SECUREBOOT
#   HW_IS_LAPTOP (yes|no) HW_IS_LIVE (yes|no) HW_POWER (ac|battery|unknown)
#
# Mock backend: ARCON_HW_MOCK=<file with KEY=VALUE lines> (tests/fixtures/hw/*.env)
# Linux backend reads sysfs/procfs under ARCON_SYSROOT so fixtures can emulate
# (fixture PCI dirs use "_" instead of ":" so the repo checks out on Windows)
# NVIDIA/AMD/Intel/unknown GPUs without physical hardware.

[[ -n "${_ARCON_HW_SH:-}" ]] && return 0
_ARCON_HW_SH=1

HW_KEYS=(HW_ARCH HW_CPU_VENDOR HW_CPU_MODEL HW_CPU_CORES HW_CPU_THREADS HW_GPU_VENDORS HW_GPU_NAMES
         HW_RAM_MB HW_DISK_TYPE HW_DISK_FREE_GB HW_ROOT_FS HW_NET_IFACES HW_VIRT HW_SECUREBOOT
         HW_IS_LAPTOP HW_IS_LIVE HW_POWER)

_hw_reset() { local k; for k in "${HW_KEYS[@]}"; do printf -v "$k" '%s' "unknown"; done; }

pci_vendor_name() {
    case "${1,,}" in
        0x10de|10de) printf 'nvidia' ;;
        0x1002|1002|0x1022|1022) printf 'amd' ;;
        0x8086|8086) printf 'intel' ;;
        0x1af4|1af4|0x15ad|15ad|0x1234|1234|0x80ee|80ee|0x1414|1414) printf 'virtual' ;;
        *) printf 'unknown' ;;
    esac
}

# ------------------------------------------------------------ Linux backend
_hw_linux() {
    local S="${ARCON_SYSROOT}"
    HW_ARCH="$(uname -m 2>/dev/null || echo unknown)"
    [[ -n "${ARCON_HW_ARCH:-}" ]] && HW_ARCH="$ARCON_HW_ARCH"

    # CPU
    if [[ -r "$S/proc/cpuinfo" ]]; then
        local vendor model
        vendor="$(awk -F': *' '/^vendor_id/{print $2; exit}' "$S/proc/cpuinfo")"
        model="$(awk -F': *' '/^model name/{print $2; exit}' "$S/proc/cpuinfo")"
        [[ -z "$model" ]] && model="$(awk -F': *' '/^(Model|Hardware|cpu model)/{print $2; exit}' "$S/proc/cpuinfo")"
        case "$vendor" in
            GenuineIntel) HW_CPU_VENDOR=intel ;;
            AuthenticAMD) HW_CPU_VENDOR=amd ;;
            "") [[ "$HW_ARCH" == aarch64* || "$HW_ARCH" == arm* ]] && HW_CPU_VENDOR=arm || HW_CPU_VENDOR=unknown ;;
            *) HW_CPU_VENDOR="${vendor,,}" ;;
        esac
        HW_CPU_MODEL="${model:-unknown}"
        HW_CPU_THREADS="$(grep -c '^processor' "$S/proc/cpuinfo")"
        local cores
        cores="$(awk -F': *' '/^physical id/{p=$2} /^core id/{print p":"$2}' "$S/proc/cpuinfo" | sort -u | wc -l | tr -d ' ')"
        [[ "$cores" =~ ^[1-9][0-9]*$ ]] && HW_CPU_CORES="$cores" || HW_CPU_CORES="$HW_CPU_THREADS"
    fi

    # GPU: every PCI function with class 0x03xxxx (display controller)
    local d cls ven vendors="" names=""
    for d in "$S"/sys/bus/pci/devices/*; do
        [[ -r "$d/class" ]] || continue
        cls="$(cat "$d/class")"
        [[ "$cls" == 0x03* ]] || continue
        ven="$(pci_vendor_name "$(cat "$d/vendor" 2>/dev/null)")"
        [[ " $vendors " == *" $ven "* ]] || vendors="${vendors:+$vendors }$ven"
        if [[ -z "$S" ]] && command -v lspci >/dev/null 2>&1; then
            local slot; slot="$(basename "$d")"
            names="${names:+$names; }$(lspci -s "$slot" 2>/dev/null | sed 's/^[^:]*: //' | cut -c1-80)"
        elif [[ -r "$d/label" ]]; then
            names="${names:+$names; }$(cat "$d/label")"
        fi
    done
    HW_GPU_VENDORS="${vendors:-none}"
    HW_GPU_NAMES="${names:-n/a}"

    # Memory
    if [[ -r "$S/proc/meminfo" ]]; then
        HW_RAM_MB="$(awk '/^MemTotal:/{printf "%d", $2/1024}' "$S/proc/meminfo")"
    fi

    # Root filesystem & disk type
    local src dev
    if [[ -n "$S" && -r "$S/arcon-root-device" ]]; then
        dev="$(cat "$S/arcon-root-device")"; HW_ROOT_FS="$(cat "$S/arcon-root-fs" 2>/dev/null || echo unknown)"
    else
        src="$(findmnt -n -o SOURCE / 2>/dev/null || df / 2>/dev/null | awk 'NR==2{print $1}')"
        HW_ROOT_FS="$(findmnt -n -o FSTYPE / 2>/dev/null || df -T / 2>/dev/null | awk 'NR==2{print $2}' || echo unknown)"
        src="${src%%[*}"   # btrfs subvolume suffix
        dev="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1)"
        [[ -z "$dev" ]] && dev="$(basename "$src")"
    fi
    if [[ "$dev" == nvme* ]]; then HW_DISK_TYPE=nvme
    elif [[ -r "$S/sys/block/$dev/queue/rotational" ]]; then
        [[ "$(cat "$S/sys/block/$dev/queue/rotational")" == 0 ]] && HW_DISK_TYPE=ssd || HW_DISK_TYPE=hdd
    else HW_DISK_TYPE=unknown; fi
    HW_DISK_FREE_GB="$(df -Pk "${S:-/}" 2>/dev/null | awk 'NR==2{printf "%d", $4/1024/1024}')"

    # Network interfaces (non-loopback)
    local ifs="" n
    for n in "$S"/sys/class/net/*; do
        [[ -e "$n" ]] || continue
        n="$(basename "$n")"; [[ "$n" == lo ]] && continue
        ifs="${ifs:+$ifs }$n"
    done
    HW_NET_IFACES="${ifs:-none}"

    # Virtualization / containers
    if [[ -f "$S/.dockerenv" ]]; then HW_VIRT="container:docker"
    elif [[ -f "$S/run/.containerenv" ]]; then HW_VIRT="container:podman"
    elif grep -qi microsoft "$S/proc/sys/kernel/osrelease" 2>/dev/null; then HW_VIRT=wsl
    elif [[ -z "$S" ]] && command -v systemd-detect-virt >/dev/null 2>&1; then
        local ctype
        if ctype="$(systemd-detect-virt -c 2>/dev/null)" && [[ -n "$ctype" && "$ctype" != none ]]; then
            HW_VIRT="container:$ctype"
        else
            HW_VIRT="$(systemd-detect-virt 2>/dev/null || true)"; [[ -z "$HW_VIRT" ]] && HW_VIRT=none
        fi
    elif [[ -r "$S/sys/class/dmi/id/product_name" ]]; then
        case "$(cat "$S/sys/class/dmi/id/product_name")" in
            *VirtualBox*) HW_VIRT=oracle ;; *VMware*) HW_VIRT=vmware ;; *KVM*|*QEMU*|*Standard\ PC*) HW_VIRT=kvm ;;
            *) HW_VIRT=none ;;
        esac
    else HW_VIRT=none; fi

    # Live environment. An overlay/tmpfs root is normal inside containers, so it
    # only counts as "live" on bare metal / VMs (CI found a false positive in
    # every distro container). Live-ISO markers count everywhere.
    HW_IS_LIVE=no
    if [[ "$HW_ROOT_FS" =~ ^(overlay|tmpfs|squashfs|aufs)$ && "$HW_VIRT" != container:* ]]; then HW_IS_LIVE=yes; fi
    if [[ -d "$S/run/archiso" || -d "$S/run/live" || -f "$S/run/initramfs/live" ]]; then HW_IS_LIVE=yes; fi

    # Secure Boot (EFI variable: last byte 1 = enabled)
    local sb
    local -a sbv=("$S"/sys/firmware/efi/efivars/SecureBoot-*)
    sb=""; [[ -e "${sbv[0]}" ]] && sb="${sbv[0]}"
    if [[ ! -d "$S/sys/firmware/efi" ]]; then HW_SECUREBOOT=unsupported-bios
    elif [[ -n "$sb" && -r "$sb" ]]; then
        if [[ "$(od -An -t u1 "$sb" 2>/dev/null | awk '{print $NF}')" == 1 ]]; then HW_SECUREBOOT=enabled; else HW_SECUREBOOT=disabled; fi
    else HW_SECUREBOOT=unknown; fi

    # Laptop (battery present) and current power source
    HW_IS_LAPTOP=no
    ls -d "$S"/sys/class/power_supply/BAT* >/dev/null 2>&1 && HW_IS_LAPTOP=yes
    HW_POWER=unknown
    if [[ "$HW_IS_LAPTOP" == no ]]; then
        HW_POWER=ac
    else
        local ac
        for ac in "$S"/sys/class/power_supply/A*/online "$S"/sys/class/power_supply/*/online; do
            [[ -r "$ac" ]] || continue
            [[ "$(cat "$ac" 2>/dev/null)" == 1 ]] && HW_POWER=ac || HW_POWER=battery
            break
        done
    fi
    return 0
}

# ------------------------------------------------------------ macOS backend
_hw_macos() {
    HW_ARCH="$(uname -m)"
    HW_CPU_MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
    if [[ "$HW_ARCH" == arm64 ]]; then HW_CPU_VENDOR=apple
    elif [[ "$HW_CPU_MODEL" == *Intel* ]]; then HW_CPU_VENDOR=intel
    else HW_CPU_VENDOR=unknown; fi
    HW_CPU_CORES="$(sysctl -n hw.physicalcpu 2>/dev/null || echo unknown)"
    HW_CPU_THREADS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo unknown)"
    local mem; mem="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    HW_RAM_MB=$(( mem / 1024 / 1024 ))
    if [[ "$HW_ARCH" == arm64 ]]; then
        HW_GPU_VENDORS=apple; HW_GPU_NAMES="Apple integrated GPU (${HW_CPU_MODEL})"
    else
        local sp; sp="$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/{print $2}')"
        HW_GPU_NAMES="$(printf '%s' "$sp" | paste -sd ';' -)"
        HW_GPU_VENDORS=""
        [[ "$sp" == *Intel* ]]  && HW_GPU_VENDORS="intel"
        [[ "$sp" == *AMD* || "$sp" == *Radeon* ]] && HW_GPU_VENDORS="${HW_GPU_VENDORS:+$HW_GPU_VENDORS }amd"
        [[ "$sp" == *NVIDIA* ]] && HW_GPU_VENDORS="${HW_GPU_VENDORS:+$HW_GPU_VENDORS }nvidia"
        HW_GPU_VENDORS="${HW_GPU_VENDORS:-unknown}"
    fi
    local di; di="$(diskutil info / 2>/dev/null)"
    if [[ "$di" == *"Solid State:"*Yes* ]]; then
        [[ "$di" == *"Protocol:"*"PCI"* || "$di" == *"Apple Fabric"* ]] && HW_DISK_TYPE=nvme || HW_DISK_TYPE=ssd
    elif [[ -n "$di" ]]; then HW_DISK_TYPE=hdd; fi
    HW_ROOT_FS="$(printf '%s\n' "$di" | awk -F': *' '/File System Personality/{print $2; exit}')"
    HW_ROOT_FS="${HW_ROOT_FS:-apfs}"
    HW_DISK_FREE_GB="$(df -Pk / | awk 'NR==2{printf "%d", $4/1024/1024}')"
    HW_NET_IFACES="$(networksetup -listallhardwareports 2>/dev/null | awk -F': ' '/^Device/{print $2}' | paste -sd ' ' -)"
    [[ "$(sysctl -n kern.hv_vm_active 2>/dev/null)" == 1 ]] && HW_VIRT=vm || HW_VIRT=none
    HW_SECUREBOOT="n/a (Apple platform boot security)"
    pmset -g batt 2>/dev/null | grep -q InternalBattery && HW_IS_LAPTOP=yes || HW_IS_LAPTOP=no
    if [[ "$HW_IS_LAPTOP" == no ]]; then HW_POWER=ac
    elif pmset -g batt 2>/dev/null | grep -q "AC Power"; then HW_POWER=ac
    elif pmset -g batt 2>/dev/null | grep -q "Battery Power"; then HW_POWER=battery
    else HW_POWER=unknown; fi
    HW_IS_LIVE=no
}

# ------------------------------------------------------------ Mock backend
_hw_mock() {
    local file="$1" line k v
    [[ -r "$file" ]] || { log_error "hardware mock not readable: $file"; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^(HW_[A-Z_]+)=(.*)$ ]] || continue
        k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"; v="${v#\"}"; v="${v%\"}"
        printf -v "$k" '%s' "$v"
    done < "$file"
}

# hw_detect [force]
hw_detect() {
    local cache="${ARCON_RUN_DIR:+$ARCON_RUN_DIR/hardware.env}"
    if [[ "${1:-}" != force && "${_ARCON_HW_DONE:-0}" == 1 ]]; then return 0; fi
    _hw_reset
    if [[ -n "${ARCON_HW_MOCK:-}" ]]; then _hw_mock "$ARCON_HW_MOCK" || return 1
    elif [[ "$OS_FAMILY" == macos ]]; then _hw_macos
    else _hw_linux; fi
    _ARCON_HW_DONE=1
    if [[ -n "$cache" ]] && ! is_dry_run; then hw_dump > "$cache" 2>/dev/null || true; fi
    log_debug "hardware: $(hw_dump | tr '\n' ' ')"
}

hw_dump() { local k; for k in "${HW_KEYS[@]}"; do printf '%s=%s\n' "$k" "${!k}"; done; }

hw_has_gpu() { [[ " $HW_GPU_VENDORS " == *" $1 "* ]]; }

# primary discrete GPU preference: nvidia > amd > intel > apple
hw_primary_gpu() {
    local v
    for v in nvidia amd intel apple; do hw_has_gpu "$v" && { printf '%s' "$v"; return; }; done
    printf 'unknown'
}

hw_summary() {
    ui_say "  ${BOLD}OS:${NC}     ${OS_NAME} (${OS_ID}, ${OS_SUPPORT})"
    ui_say "  ${BOLD}Arch:${NC}   ${HW_ARCH}"
    ui_say "  ${BOLD}CPU:${NC}    ${HW_CPU_MODEL} [${HW_CPU_VENDOR}] ${HW_CPU_CORES}C/${HW_CPU_THREADS}T"
    ui_say "  ${BOLD}GPU:${NC}    ${HW_GPU_VENDORS} — ${HW_GPU_NAMES}"
    ui_say "  ${BOLD}RAM:${NC}    $(( ${HW_RAM_MB:-0} / 1024 )) GB"
    ui_say "  ${BOLD}Disk:${NC}   ${HW_DISK_TYPE} (${HW_ROOT_FS}), ${HW_DISK_FREE_GB} GB free"
    ui_say "  ${BOLD}Virt:${NC}   ${HW_VIRT}   ${BOLD}SecureBoot:${NC} ${HW_SECUREBOOT}   ${BOLD}Laptop:${NC} ${HW_IS_LAPTOP}"
}
