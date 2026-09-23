#!/usr/bin/env bats
# UNIT: hardware detection from sysfs/procfs fixtures and mock env files
load ../helpers/common

setup() { arcon_load; OS_FAMILY=linux; }

sys() { ARCON_SYSROOT="$ARCON_REPO/tests/fixtures/sys/$1" hw_detect force; }

@test "NVIDIA desktop: vendor from PCI id, SSD from rotational=0" {
    sys nvidia
    [ "$HW_GPU_VENDORS" = nvidia ]
    [ "$HW_CPU_VENDOR" = amd ]
    [ "$HW_RAM_MB" -eq 32000 ]
    [ "$HW_DISK_TYPE" = ssd ]
    [ "$HW_ROOT_FS" = ext4 ]
    [ "$(hw_primary_gpu)" = nvidia ]
}
@test "AMD GPU on a spinning disk" { sys amd; [ "$HW_GPU_VENDORS" = amd ]; [ "$HW_DISK_TYPE" = hdd ]; }
@test "Intel iGPU" { sys intel; [ "$HW_GPU_VENDORS" = intel ]; }
@test "hybrid laptop: both GPUs, NVIDIA preferred, battery + nvme detected" {
    sys hybrid
    [[ " $HW_GPU_VENDORS " == *" intel "* ]]; [[ " $HW_GPU_VENDORS " == *" nvidia "* ]]
    [ "$(hw_primary_gpu)" = nvidia ]
    [ "$HW_IS_LAPTOP" = yes ]; [ "$HW_POWER" = battery ]; [ "$HW_DISK_TYPE" = nvme ]
    [ "$HW_ROOT_FS" = btrfs ]
}
@test "virtual display adapter is not reported as a real GPU vendor" { sys vm; [ "$HW_GPU_VENDORS" = virtual ]; ! hw_has_gpu nvidia; }
@test "no display controller -> none" { sys none; [ "$HW_GPU_VENDORS" = none ]; }

@test "ARCON_HW_MOCK overrides detection completely" {
    ARCON_HW_MOCK="$ARCON_REPO/tests/fixtures/hw/laptop-hybrid-battery.env" hw_detect force
    [ "$HW_POWER" = battery ]; [ "$HW_IS_LAPTOP" = yes ]; hw_has_gpu intel; hw_has_gpu nvidia
}

@test "pci vendor mapping" {
    [ "$(pci_vendor_name 0x10de)" = nvidia ]; [ "$(pci_vendor_name 0x1002)" = amd ]
    [ "$(pci_vendor_name 0x8086)" = intel ];  [ "$(pci_vendor_name 0x15ad)" = virtual ]
    [ "$(pci_vendor_name 0xdead)" = unknown ]
}

@test "hw_dump emits every key exactly once" {
    sys nvidia
    run hw_dump
    [ "$(printf '%s\n' "$output" | cut -d= -f1 | sort | uniq -d)" = "" ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq "${#HW_KEYS[@]}" ]
}

# Live-environment detection (CI found every distro container reported as "live")
live_fixture() {
    local d="$BATS_TEST_TMPDIR/sys"
    cp -r "$ARCON_REPO/tests/fixtures/sys/none" "$d"
    echo overlay > "$d/arcon-root-fs"; echo sda > "$d/arcon-root-device"
    printf '%s' "$d"
}
@test "overlay root inside a Docker container is NOT a live system" {
    d="$(live_fixture)"; : > "$d/.dockerenv"
    ARCON_SYSROOT="$d" hw_detect force
    [ "$HW_VIRT" = container:docker ]
    [ "$HW_IS_LIVE" = no ]
}
@test "overlay root outside a container is a live system" {
    d="$(live_fixture)"
    ARCON_SYSROOT="$d" hw_detect force
    [ "$HW_IS_LIVE" = yes ]
}
@test "archiso marker means live even inside a container" {
    d="$(live_fixture)"; : > "$d/.dockerenv"; mkdir -p "$d/run/archiso"
    ARCON_SYSROOT="$d" hw_detect force
    [ "$HW_IS_LIVE" = yes ]
}
