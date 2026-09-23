#!/usr/bin/env bash
# ArCoN v3.0 -- core/state.sh
# Run state, resume and task execution.
#
# Layout ($ARCON_STATE_DIR, default ~/.local/state/arcon):
#   current                 -> id of the last run that did not finish
#   runs/<id>/config.conf   effective config (answers) used by the run
#   runs/<id>/tasks.tsv     id \t status \t updated \t description
#   runs/<id>/rollback.journal, backup/, plan.txt, hardware.env
#
# tasks.tsv is rewritten atomically (tmp + mv) on every transition, so an
# interrupted process (Ctrl+C, power loss mid-write) leaves either the old or
# the new file — never a truncated one (v2.5 resume log was never written at
# all — bug #A-05).
#
# Task statuses: pending running done failed skipped
# "running" found on resume == interrupted -> re-executed (tasks are idempotent).

[[ -n "${_ARCON_STATE_SH:-}" ]] && return 0
_ARCON_STATE_SH=1

: "${ARCON_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/arcon}"
ARCON_RUN_ID=""
ARCON_RUN_DIR=""
declare -ga TASK_IDS=()
declare -gA TASK_FN=() TASK_DESC=() TASK_RISK=() TASK_MODULE=() TASK_STATUS=()

state_init_dirs() {
    mkdir -p "$ARCON_STATE_DIR/runs" || die 3 "cannot create state dir $ARCON_STATE_DIR"
    chmod 700 "$ARCON_STATE_DIR" 2>/dev/null || true
}

state_new_run() {
    state_init_dirs
    ARCON_RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
    ARCON_RUN_DIR="$ARCON_STATE_DIR/runs/$ARCON_RUN_ID"
    mkdir -p "$ARCON_RUN_DIR/backup"
    if ! is_dry_run; then
        printf '%s\n' "$ARCON_RUN_ID" > "$ARCON_STATE_DIR/current.tmp" && mv -f "$ARCON_STATE_DIR/current.tmp" "$ARCON_STATE_DIR/current"
    fi
    export ARCON_RUN_ID ARCON_RUN_DIR
}

state_current_run() {
    [[ -f "$ARCON_STATE_DIR/current" ]] || return 1
    local id; id="$(head -n1 "$ARCON_STATE_DIR/current")"
    [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]] || { log_warn "corrupted state pointer ignored"; return 1; }
    [[ -d "$ARCON_STATE_DIR/runs/$id" ]] || return 1
    printf '%s' "$id"
}

state_open_run() {
    ARCON_RUN_ID="$1"
    ARCON_RUN_DIR="$ARCON_STATE_DIR/runs/$1"
    [[ -d "$ARCON_RUN_DIR" ]] || die 3 "unknown run id: $1"
    export ARCON_RUN_ID ARCON_RUN_DIR
}

state_clear_current() {
    is_dry_run && return 0
    rm -f "$ARCON_STATE_DIR/current"
}

state_list_runs() {
    local d id total done_n failed
    for d in "$ARCON_STATE_DIR"/runs/*/; do
        [[ -d "$d" ]] || continue
        id="$(basename "$d")"
        total=0; done_n=0; failed=0
        if [[ -f "$d/tasks.tsv" ]]; then
            total=$(grep -c . "$d/tasks.tsv")
            done_n=$(awk -F'\t' '$2=="done"' "$d/tasks.tsv" | wc -l | tr -d ' ')
            failed=$(awk -F'\t' '$2=="failed"' "$d/tasks.tsv" | wc -l | tr -d ' ')
        fi
        printf '%s  tasks=%s done=%s failed=%s%s\n' "$id" "$total" "$done_n" "$failed" \
            "$([[ -f "$d/rollback.journal" ]] && printf '  rollback=%s' "$(wc -l < "$d/rollback.journal" | tr -d ' ')")"
    done
}

# --------------------------------------------------------------- tasks
# task_add <id> <risk:low|medium|high> <description> <function>
task_add() {
    local id="$1" risk="$2" desc="$3" fn="$4"
    [[ -n "${TASK_FN[$id]+x}" ]] && { log_debug "task $id already queued"; return 0; }
    declare -F "$fn" >/dev/null || { log_error "task $id: function $fn not defined"; return 1; }
    TASK_IDS+=("$id")
    TASK_FN[$id]="$fn"; TASK_DESC[$id]="$desc"; TASK_RISK[$id]="$risk"
    TASK_MODULE[$id]="${ARCON_MODULE:-core}"; TASK_STATUS[$id]="pending"
}

task_reset_queue() {
    TASK_IDS=(); TASK_FN=(); TASK_DESC=(); TASK_RISK=(); TASK_MODULE=(); TASK_STATUS=()
}

_state_write_tasks() {
    is_dry_run && return 0
    [[ -n "$ARCON_RUN_DIR" ]] || return 0
    local tmp="$ARCON_RUN_DIR/tasks.tsv.tmp" id
    {
        for id in "${TASK_IDS[@]}"; do
            printf '%s\t%s\t%s\t%s\n' "$id" "${TASK_STATUS[$id]}" "$(date +%s)" "${TASK_DESC[$id]}"
        done
    } > "$tmp" && mv -f "$tmp" "$ARCON_RUN_DIR/tasks.tsv"
}

# state_load_tasks -> restores TASK_STATUS from tasks.tsv of the opened run
state_load_tasks() {
    local f="$ARCON_RUN_DIR/tasks.tsv" id st _ts _d
    [[ -f "$f" ]] || return 0
    while IFS=$'\t' read -r id st _ts _d; do
        [[ -n "${TASK_FN[$id]+x}" ]] || { log_warn "resume: task $id no longer exists, ignored"; continue; }
        case "$st" in
            done|skipped) TASK_STATUS[$id]="$st" ;;
            running) log_warn "resume: task $id was interrupted — it will be re-run"; TASK_STATUS[$id]=pending ;;
            failed)  TASK_STATUS[$id]=pending ;;
            pending) ;;
            *) log_warn "resume: invalid status '$st' for $id — treated as pending" ;;
        esac
    done < "$f"
}

task_set_status() { TASK_STATUS[$1]="$2"; _state_write_tasks; }

task_print_queue() {
    local id i=0
    for id in "${TASK_IDS[@]}"; do
        i=$((i + 1))
        printf '  %2d. %-8s %-7s %-34s %s\n' "$i" "[${TASK_STATUS[$id]}]" "${TASK_RISK[$id]}" "$id" "${TASK_DESC[$id]}"
    done
}

_ARCON_CURRENT_TASK=""
_state_on_interrupt() {
    trap - INT TERM
    printf '\n' >&2
    if [[ -n "$_ARCON_CURRENT_TASK" ]]; then
        log_warn "interrupted during task ${_ARCON_CURRENT_TASK} — state saved"
        _state_write_tasks
    fi
    sudo_keepalive_stop
    log_warn "resume later with: ./setup.sh --resume"
    exit 130
}

# task_run_all -> executes pending tasks; returns number of failures
task_run_all() {
    local id total=${#TASK_IDS[@]} idx=0 failures=0 rc
    trap _state_on_interrupt INT TERM
    _state_write_tasks
    for id in "${TASK_IDS[@]}"; do
        idx=$((idx + 1))
        case "${TASK_STATUS[$id]}" in
            done|skipped) log_info "[$idx/$total] $id already ${TASK_STATUS[$id]} — skipping"; continue ;;
        esac
        ARCON_MODULE="${TASK_MODULE[$id]}"; ARCON_TASK="$id"; _ARCON_CURRENT_TASK="$id"
        is_dry_run || ui_progress $((idx - 1)) "$total" "${TASK_DESC[$id]}"
        is_dry_run || printf '\n'
        log_info "[$idx/$total] ${TASK_DESC[$id]}"
        task_set_status "$id" running
        "${TASK_FN[$id]}"; rc=$?
        case "$rc" in
            0)  task_set_status "$id" 'done';    log_result "$id" PASS ;;
            99) task_set_status "$id" skipped; log_result "$id" SKIP ;;
            *)  task_set_status "$id" failed;  log_result "$id" FAIL "exit $rc"
                failures=$((failures + 1))
                if [[ "${ARCON_KEEP_GOING:-0}" != "1" ]]; then
                    if [[ "${ARCON_INTERACTIVE:-1}" == "1" ]] && ui_confirm "Task '$id' failed. Continue with the remaining tasks" y; then
                        :
                    elif [[ "${ARCON_INTERACTIVE:-1}" == "1" ]]; then
                        log_error "aborting on user request; resume later with --resume"; break
                    else
                        log_error "aborting (non-interactive; use --keep-going to continue after failures)"; break
                    fi
                fi ;;
        esac
    done
    is_dry_run || ui_progress "$total" "$total" "complete"
    _ARCON_CURRENT_TASK=""; ARCON_TASK=""
    trap - INT TERM
    return "$failures"
}

# task_skip -> helper for task functions: "not applicable / nothing to do"
TASK_SKIP=99
