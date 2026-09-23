#!/usr/bin/env bash
# ArCoN v3.0 -- core/rollback.sh
# Backup journal + reverse replay.
#
# Journal: $ARCON_RUN_DIR/rollback.journal  (append-only, TAB separated)
#   FILE     <path> <backup-path|ABSENT> [root]
#   PKG      <provider> <name>
#   SERVICE  <unit> <previous: enabled|disabled|absent>
#   DCONF    <dconf-dir> <dump-file>
#   SHELL    <user> <previous-shell>
#   POWER    <previous-profile>
#   NOTE     <irreversible description>
#
# Rollback replays the journal in reverse order. Package removal is opt-in
# (--rollback-packages) because removing packages can cascade.

[[ -n "${_ARCON_ROLLBACK_SH:-}" ]] && return 0
_ARCON_ROLLBACK_SH=1

rb_journal() { printf '%s' "${ARCON_RUN_DIR:-}/rollback.journal"; }
rb_backup_dir() { printf '%s' "${ARCON_RUN_DIR:-}/backup"; }

rb_add() {
    is_dry_run && return 0
    [[ -n "${ARCON_RUN_DIR:-}" ]] || return 0
    local IFS=$'\t'
    printf '%s\n' "$*" >> "$(rb_journal)"
}

rb_note_irreversible() {
    plan_record COMMAND "IRREVERSIBLE: $*"
    rb_add NOTE "$*"
    log_warn "irreversible step: $*"
}

# fs_backup <path> [root]  -> copies the file into the run backup dir once
fs_backup() {
    local path="$1" root="${2:-}" bdir dest
    is_dry_run && return 0
    [[ -n "${ARCON_RUN_DIR:-}" ]] || return 0
    bdir="$(rb_backup_dir)"; mkdir -p "$bdir"
    # already backed up in this run?
    if grep -qF "FILE	$path	" "$(rb_journal)" 2>/dev/null; then return 0; fi
    if [[ -e "$path" || -L "$path" ]]; then
        dest="$bdir/$(printf '%s' "$path" | sed 's|/|%|g')"
        if [[ "$root" == "root" ]]; then
            as_root cp -a "$path" "$dest" && as_root chown -R "$(id -u):$(id -g)" "$dest" 2>/dev/null
        else
            cp -a "$path" "$dest"
        fi || { log_error "backup failed for $path"; return 1; }
        rb_add FILE "$path" "$dest" "${root:-user}"
    else
        rb_add FILE "$path" ABSENT "${root:-user}"
    fi
}

# rollback_run <run_dir> [with_packages]
rollback_run() {
    local run_dir="$1" with_pkgs="${2:-0}" j lines i type a b c ok=0 fail=0
    j="$run_dir/rollback.journal"
    [[ -d "$run_dir" ]] || { log_error "run directory not found: $run_dir"; return 1; }
    if [[ ! -s "$j" ]]; then
        log_info "run $(basename "$run_dir") made no recorded changes — nothing to roll back"
        return 0
    fi
    mapfile -t lines < "$j"
    log_info "rolling back ${#lines[@]} journal entries from $run_dir"
    for (( i=${#lines[@]}-1; i>=0; i-- )); do
        IFS=$'\t' read -r type a b c <<< "${lines[$i]}"
        case "$type" in
            FILE)
                if [[ "$b" == "ABSENT" ]]; then
                    if [[ "$c" == "root" ]]; then x_root FILE "remove file created by ArCoN" -- rm -rf -- "$a"
                    else x_run FILE "remove file created by ArCoN" -- rm -rf -- "$a"; fi
                else
                    if [[ "$c" == "root" ]]; then
                        x_root FILE "restore $a" -- rm -rf -- "$a" && x_root FILE "restore $a" -- cp -a "$b" "$a" && x_root FILE "fix owner $a" -- chown -R root:root "$a"
                    else
                        x_run FILE "restore $a" -- rm -rf -- "$a" && x_run FILE "restore $a" -- cp -a "$b" "$a"
                    fi
                fi ;;
            SERVICE)
                if [[ "$b" == "disabled" || "$b" == "absent" ]]; then
                    x_root SERVICE "disable $a (was $b)" -- systemctl disable --now "$a"
                else true; fi ;;
            DCONF)
                # shellcheck disable=SC2016  # positional args of the inner sh, intentionally literal
            x_run SETTING "restore dconf $a" -- sh -c 'dconf reset -f "$1" && dconf load "$1" < "$2"' _ "$a" "$b" ;;
            SHELL)
                x_root SETTING "restore login shell of $a to $b" -- chsh -s "$b" "$a" ;;
            POWER)
                x_run SETTING "restore power profile $a" -- powerprofilesctl set "$a" ;;
            PKG)
                if [[ "$with_pkgs" == "1" ]]; then
                    local _prev="$PKG_PROVIDER" _prc=0
                    if pkg_use_provider "$a"; then
                        if [[ "$a" == flatpak ]]; then _pkgp_flatpak_remove "$b" || _prc=1; else pkg_remove "$b" || _prc=1; fi
                    else _prc=1; fi
                    pkg_use_provider "$_prev" >/dev/null 2>&1 || true
                    (( _prc == 0 ))
                else
                    log_info "keeping package $b (use --rollback-packages to remove)"; true
                fi ;;
            NOTE) log_warn "cannot roll back automatically: $a"; true ;;
            *) log_warn "unknown journal entry: ${lines[$i]}"; true ;;
        esac
        # shellcheck disable=SC2181
        if [[ $? -eq 0 ]]; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
    done
    log_info "rollback finished: $ok ok, $fail failed"
    (( fail == 0 ))
}
