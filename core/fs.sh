#!/usr/bin/env bash
# ArCoN v3.0 -- core/fs.sh
# Idempotent, dry-run aware, journaled file operations.
#
#   fs_install_file <src> <dest> [root] [mode]  copy when content differs
#   fs_write <dest> [root] [mode]  < content      write when content differs
#       NOTE: feed content with a here-doc/here-string, never `cmd | fs_write`:
#       a pipeline runs fs_write in a subshell and the dry-run plan entry would
#       be lost (found by tests/bats/unit_dryrun.bats).
#   fs_append_once <file> <line> [root]         append line if missing (no duplicates)
#   fs_set_kv <file> <regex> <replacement-line> [root]
#                                                replace first matching line or append
#   fs_remove <path> [root]                     backup then remove
#   fs_copy_tree <srcdir> <destdir>             copy files that are missing/different
#
# All writes go through a temp file + mv (atomic on the same filesystem), and
# the previous version is recorded in the rollback journal first.

[[ -n "${_ARCON_FS_SH:-}" ]] && return 0
_ARCON_FS_SH=1

_fs_same() { [[ -f "$1" && -f "$2" ]] && cmp -s "$1" "$2"; }

fs_install_file() {
    local src="$1" dest="$2" root="${3:-}" mode="${4:-}" label="${5:-}"
    [[ -f "$src" ]] || { log_error "source file missing: $src"; return 1; }
    local same=1
    if [[ -f "$dest" ]]; then
        if [[ -r "$dest" ]]; then cmp -s "$src" "$dest" && same=0
        elif [[ "$root" == root ]] && ! is_dry_run; then as_root cmp -s "$src" "$dest" && same=0
        fi
    fi
    if (( same == 0 )); then
        log_debug "unchanged: $dest"
        return 0
    fi
    if is_dry_run; then
        if [[ -n "$label" ]]; then plan_record FILE "$label"
        elif [[ -f "$dest" ]]; then plan_record FILE "modify $dest (backup will be taken)"
        else plan_record FILE "create $dest"; fi
        return 0
    fi
    fs_backup "$dest" "$root" || return 1
    if [[ "$root" == "root" ]]; then
        as_root mkdir -p "$(dirname "$dest")" && as_root install -m "${mode:-0644}" "$src" "$dest"
    else
        mkdir -p "$(dirname "$dest")" && cp -f "$src" "$dest.arcon.tmp" && mv -f "$dest.arcon.tmp" "$dest" &&
            { [[ -z "$mode" ]] || chmod "$mode" "$dest"; }
    fi || { log_error "could not write $dest"; return 1; }
    log_debug "installed $dest"
}

fs_write() {
    local dest="$1" root="${2:-}" mode="${3:-}" tmp rc
    tmp="$(mktemp)"; cat > "$tmp"
    fs_install_file "$tmp" "$dest" "$root" "$mode" \
        "$([[ -f "$dest" ]] && printf 'rewrite %s (backup will be taken)' "$dest" || printf 'create %s' "$dest")"; rc=$?
    rm -f "$tmp"
    return $rc
}

fs_append_once() {
    local file="$1" line="$2" root="${3:-}"
    if [[ -f "$file" ]] && grep -qxF -- "$line" "$file" 2>/dev/null; then
        log_debug "line already present in $file"
        return 0
    fi
    if is_dry_run; then plan_record FILE "append to $file: $line"; return 0; fi
    fs_backup "$file" "$root" || return 1
    if [[ "$root" == "root" ]]; then
        printf '%s\n' "$line" | as_root tee -a "$file" >/dev/null
    else
        mkdir -p "$(dirname "$file")" && printf '%s\n' "$line" >> "$file"
    fi
}

# fs_set_kv <file> <ERE matching existing line(s)> <new line> [root]
fs_set_kv() {
    local file="$1" re="$2" newline="$3" root="${4:-}" tmp
    if [[ -f "$file" ]] && grep -qxF -- "$newline" "$file" 2>/dev/null && ! grep -Eq -- "$re" <(grep -vxF -- "$newline" "$file"); then
        log_debug "setting already applied in $file: $newline"
        return 0
    fi
    if is_dry_run; then plan_record SETTING "$file: set '$newline'"; return 0; fi
    tmp="$(mktemp)"
    if [[ -f "$file" ]]; then
        if [[ "$root" == root ]]; then as_root cat "$file" > "$tmp"; else cat "$file" > "$tmp"; fi
    fi
    awk -v re="$re" -v nl="$newline" '
        BEGIN { done = 0 }
        $0 ~ re { if (!done) { print nl; done = 1 }; next }
        { print }
        END { if (!done) print nl }' "$tmp" > "$tmp.new"
    fs_install_file "$tmp.new" "$file" "$root" "" "set in $file: $newline"
    local rc=$?; rm -f "$tmp" "$tmp.new"; return $rc
}

fs_remove() {
    local path="$1" root="${2:-}"
    [[ -e "$path" || -L "$path" ]] || return 0
    if is_dry_run; then plan_record FILE "remove $path (backup kept)"; return 0; fi
    fs_backup "$path" "$root" || return 1
    if [[ "$root" == root ]]; then as_root rm -rf -- "$path"; else rm -rf -- "$path"; fi
}

fs_copy_tree() {
    local src="$1" dest="$2" f rel n=0
    [[ -d "$src" ]] || { log_warn "directory not found: $src"; return 1; }
    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"
        if ! _fs_same "$f" "$dest/$rel"; then
            fs_install_file "$f" "$dest/$rel" || return 1
            n=$((n + 1))
        fi
    done < <(find "$src" -type f -print0)
    log_debug "fs_copy_tree $src -> $dest: $n file(s) updated"
}
