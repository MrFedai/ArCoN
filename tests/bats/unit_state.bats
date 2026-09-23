#!/usr/bin/env bats
# UNIT/ERROR: task engine, statuses, resume semantics, failure reporting
load ../helpers/common

setup() { arcon_load; state_new_run; }

ok()   { return 0; }
bad()  { return 3; }
skip_() { return "$TASK_SKIP"; }

@test "statuses: done / skipped / failed, and failure count is returned" {
    ARCON_KEEP_GOING=1
    task_add m.ok low "ok" ok
    task_add m.skip low "skip" skip_
    task_add m.bad low "bad" bad
    run task_run_all
    [ "$status" -eq 1 ]
    task_run_all || true
    [ "${TASK_STATUS[m.ok]}" = done ]; [ "${TASK_STATUS[m.skip]}" = skipped ]; [ "${TASK_STATUS[m.bad]}" = failed ]
}

@test "a failed task is never reported as PASS in the log" {
    ARCON_KEEP_GOING=1
    task_add m.bad low "bad" bad
    task_run_all || true
    ! grep -q 'PASS.*m.bad\|✓ m.bad' "$ARCON_TEST_TMP/test.log"
    grep -q 'm.bad' "$ARCON_TEST_TMP/test.log"
}

@test "non-interactive run stops at the first failure without --keep-going" {
    ARCON_KEEP_GOING=0
    task_add a.bad low "bad" bad
    task_add a.after low "after" ok
    task_run_all || true
    [ "${TASK_STATUS[a.after]}" = pending ]
}

@test "resume: done tasks are skipped, failed and interrupted ones re-run" {
    task_add r.done low "d" ok
    task_add r.fail low "f" bad
    task_add r.int low "i" ok
    TASK_STATUS[r.done]=done; TASK_STATUS[r.fail]=failed; TASK_STATUS[r.int]=running
    _state_write_tasks
    TASK_STATUS[r.done]=pending; TASK_STATUS[r.fail]=pending; TASK_STATUS[r.int]=pending
    state_load_tasks
    [ "${TASK_STATUS[r.done]}" = done ]
    [ "${TASK_STATUS[r.fail]}" = pending ]
    [ "${TASK_STATUS[r.int]}" = pending ]
}

@test "tasks.tsv is written atomically (no temp file left behind)" {
    task_add w.ok low "ok" ok
    task_run_all
    [ -s "$ARCON_RUN_DIR/tasks.tsv" ]
    [ -z "$(find "$ARCON_RUN_DIR" -name '*.tmp')" ]
}

@test "a corrupted state pointer is ignored" {
    echo '../../etc' > "$ARCON_STATE_DIR/current"
    run state_current_run
    [ "$status" -ne 0 ]
}
