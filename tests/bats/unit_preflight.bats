#!/usr/bin/env bats
# UNIT: pre-flight checks (network tri-state, live environment, pacman lock).
# Regression for a review finding: the live/lock checks lived in an uncalled
# function, so they never ran in the first v3 draft.
load ../helpers/common

setup() {
    arcon_load
    state_new_run
}

hide_downloaders() {
    command() {
        if [[ "$1" == -v && ( "$2" == curl || "$2" == wget ) ]]; then return 1; fi
        builtin command "$@"
    }
}

@test "network check without curl/wget falls back to /dev/tcp (not reported as offline)" {
    hide_downloaders
    cfg_set NET_CHECK_URLS "https://127.0.0.1" test   # port 443 closed on the runner
    run net_online
    [ "$status" -eq 1 ]
    net_online || true
    [ "$NET_CHECK_METHOD" = devtcp ]
}

@test "network check reports 'could not check' (rc 2) when no method exists" {
    command() {
        if [[ "$1" == -v && ( "$2" == curl || "$2" == wget || "$2" == timeout ) ]]; then return 1; fi
        builtin command "$@"
    }
    run net_online
    [ "$status" -eq 2 ]
}

@test "live environment: non-interactive real run is cancelled (exit 0, nothing applied)" {
    HW_IS_LIVE=yes; ARCON_DRY_RUN=0; ARCON_INTERACTIVE=0
    run base_preflight_live
    [ "$status" -eq 0 ]
    [[ "$output" == *"LIVE ENVIRONMENT DETECTED"* ]]
    [[ "$output" == *"cancelled on live environment"* ]]
}

@test "live environment: dry-run only warns" {
    HW_IS_LIVE=yes; ARCON_DRY_RUN=1
    run base_preflight_live
    [ "$status" -eq 0 ]
    [[ "$output" == *"LIVE ENVIRONMENT DETECTED"* ]]
    [[ "$output" != *"cancelled"* ]]
}

@test "pacman lock: stale lock with PACMAN_STALE_LOCK=abort fails the preflight" {
    arcon_fake_distro arch
    export ARCON_SYSROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ARCON_SYSROOT/var/lib/pacman"; : > "$ARCON_SYSROOT/var/lib/pacman/db.lck"
    pgrep() { return 1; }
    cfg_set PACMAN_STALE_LOCK abort test
    run base_preflight_pacman_lock
    [ "$status" -ne 0 ]
    [ -f "$ARCON_SYSROOT/var/lib/pacman/db.lck" ]
}

@test "pacman lock: never removed while pacman is running" {
    arcon_fake_distro arch
    export ARCON_SYSROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ARCON_SYSROOT/var/lib/pacman"; : > "$ARCON_SYSROOT/var/lib/pacman/db.lck"
    pgrep() { return 0; }
    cfg_set PACMAN_STALE_LOCK remove test
    run base_preflight_pacman_lock
    [ "$status" -ne 0 ]
    [[ "$output" == *"running in another process"* ]]
    [ -f "$ARCON_SYSROOT/var/lib/pacman/db.lck" ]
}

@test "pacman lock: dry-run with PACMAN_STALE_LOCK=remove only plans the removal" {
    arcon_fake_distro arch
    export ARCON_SYSROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ARCON_SYSROOT/var/lib/pacman"; : > "$ARCON_SYSROOT/var/lib/pacman/db.lck"
    pgrep() { return 1; }
    ARCON_DRY_RUN=1
    cfg_set PACMAN_STALE_LOCK remove test
    run base_preflight_pacman_lock
    [ "$status" -eq 0 ]
    [ -f "$ARCON_SYSROOT/var/lib/pacman/db.lck" ]
}

@test "pacman lock check is skipped on non-Arch systems" {
    arcon_fake_distro ubuntu
    export ARCON_SYSROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ARCON_SYSROOT/var/lib/pacman"; : > "$ARCON_SYSROOT/var/lib/pacman/db.lck"
    run base_preflight_pacman_lock
    [ "$status" -eq 0 ]
}
