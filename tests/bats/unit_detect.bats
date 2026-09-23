#!/usr/bin/env bats
# UNIT: platform detection (os-release fixtures, never the host)
load ../helpers/common

setup() { arcon_load; export ARCON_UNAME_S=Linux; }

detect() { ARCON_SYSROOT="$ARCON_REPO/tests/fixtures/os/$1" platform_detect; }

@test "arch -> pacman, tested" {
    detect arch
    [ "$OS_ID" = arch ]; [ "$PKG_PROVIDER" = pacman ]; [ "$OS_SUPPORT" = tested ]
}
@test "debian -> apt, tested" { detect debian; [ "$OS_ID" = debian ]; [ "$PKG_PROVIDER" = apt ]; [ "$OS_SUPPORT" = tested ]; }
@test "ubuntu -> apt, tested" { detect ubuntu; [ "$OS_ID" = ubuntu ]; [ "$PKG_PROVIDER" = apt ]; [ "$OS_SUPPORT" = tested ]; }
@test "fedora -> dnf, tested" { detect fedora; [ "$OS_ID" = fedora ]; [ "$PKG_PROVIDER" = dnf ]; [ "$OS_SUPPORT" = tested ]; }
@test "opensuse tumbleweed -> zypper, tested" { detect opensuse-tumbleweed; [ "$OS_ID" = opensuse ]; [ "$PKG_PROVIDER" = zypper ]; [ "$OS_SUPPORT" = tested ]; }
@test "opensuse leap -> zypper, tested" { detect opensuse-leap; [ "$OS_ID" = opensuse ]; [ "$OS_SUPPORT" = tested ]; }

@test "derivatives are mapped but marked experimental (never claimed as tested)" {
    detect endeavouros; [ "$OS_ID" = arch ];   [ "$OS_SUPPORT" = experimental ]
    detect cachyos;     [ "$OS_ID" = arch ];   [ "$OS_SUPPORT" = experimental ]
    detect linuxmint;   [ "$OS_ID" = ubuntu ]; [ "$OS_SUPPORT" = experimental ]
    detect nobara;      [ "$OS_ID" = fedora ]; [ "$OS_SUPPORT" = experimental ]
}

@test "unknown distributions are unsupported, with no package provider" {
    detect alpine; [ "$OS_SUPPORT" = unsupported ]; [ -z "$PKG_PROVIDER" ]
    detect gentoo; [ "$OS_SUPPORT" = unsupported ]
}

@test "missing os-release fails loudly" {
    run detect broken
    [ "$status" -ne 0 ]
}

@test "os-release is parsed, never executed (v2.5 sourced it)" {
    rm -f /tmp/arcon-pwned /tmp/arcon-pwned2
    detect malicious
    [ ! -e /tmp/arcon-pwned ]; [ ! -e /tmp/arcon-pwned2 ]
    [ "$OS_SUPPORT" = unsupported ]
}

@test "macOS is detected via uname" {
    ARCON_UNAME_S=Darwin platform_detect
    [ "$OS_FAMILY" = macos ]; [ "$PKG_PROVIDER" = brew ]
}

@test "Windows shells are redirected to setup.ps1" {
    run env ARCON_UNAME_S=MINGW64_NT bash -c ". '$ARCON_REPO/core/log.sh'; . '$ARCON_REPO/platform/detect.sh'; platform_detect"
    [ "$status" -ne 0 ]
    [[ "$output" == *setup.ps1* ]]
}

@test "catalog column follows the platform" {
    detect fedora; [ "$(platform_catalog_column)" = fedora ]
    ARCON_UNAME_S=Darwin platform_detect; [ "$(platform_catalog_column)" = brew ]
}
