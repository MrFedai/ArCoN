#!/usr/bin/env bats
# UNIT: security module verification logic (tools replaced by shell functions)
load ../helpers/common

setup() {
    arcon_load
    state_new_run
    OS_ID=ubuntu; OS_FAMILY=linux; PKG_PROVIDER=apt
    command() { if [[ "$1" == -v && "$2" == ufw ]]; then echo /usr/sbin/ufw; return 0; fi; builtin command "$@"; }
    x_root() { return 0; }          # mutating calls are covered by the dry-run/integration tests
    rb_add() { :; }
    systemctl() { return 1; }
}

@test "ufw verification: 'Status: inactive' is a FAILURE (substring 'active' must not match)" {
    as_root() { [[ "$1" == ufw ]] && echo "Status: inactive"; }
    run security_firewall_ufw
    [ "$status" -ne 0 ]
}

@test "ufw verification: 'Status: active' is a PASS" {
    as_root() { [[ "$1" == ufw ]] && echo "Status: active"; }
    run security_firewall_ufw
    [ "$status" -eq 0 ]
}

@test "ufw verification runs 'ufw status' with root privileges" {
    as_root() { [[ "$1" == ufw ]] && { touch "$BATS_TEST_TMPDIR/as_root_used"; echo "Status: active"; }; }
    ufw() { echo "ERROR: You need to be root to run this script"; return 1; }
    security_firewall_ufw
    [ -e "$BATS_TEST_TMPDIR/as_root_used" ]
}
