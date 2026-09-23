#!/usr/bin/env bats
# DRYRUN: nothing is executed or written, everything is planned
load ../helpers/common

setup() { arcon_load; ARCON_DRY_RUN=1; state_new_run; T="$BATS_TEST_TMPDIR/t"; }

@test "x_run does not execute in dry-run and records the plan" {
    x_run COMMAND "create marker" -- touch "$BATS_TEST_TMPDIR/marker"
    [ ! -e "$BATS_TEST_TMPDIR/marker" ]
    [ "$(plan_count)" -eq 1 ]
}
@test "x_root does not call sudo in dry-run" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\ntouch "%s/sudo-called"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/sudo"
    chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" x_root COMMAND "root thing" -- /bin/true
    [ ! -e "$BATS_TEST_TMPDIR/sudo-called" ]
    [ "$(plan_count)" -eq 1 ]
}
@test "fs_write does not create files in dry-run" {
    fs_write "$T/never" <<< 'x'
    [ ! -e "$T/never" ]
    [[ "${ARCON_PLAN[0]}" == *"create $T/never"* ]]
}
@test "no rollback journal and no state pointer are written in dry-run" {
    rb_add FILE /x ABSENT user
    [ ! -e "$(rb_journal)" ]
    [ ! -e "$ARCON_STATE_DIR/current" ]
}
