#!/usr/bin/env bats
# UNIT: atomic writes, idempotency, backups and rollback of file changes
load ../helpers/common

setup() {
    arcon_load
    state_new_run
    T="$BATS_TEST_TMPDIR/target"; mkdir -p "$T"
}

@test "fs_write creates the file and journals it as ABSENT" {
    fs_write "$T/a.conf" <<< 'hello'
    [ "$(cat "$T/a.conf")" = hello ]
    grep -q "FILE	$T/a.conf	ABSENT" "$(rb_journal)"
}

@test "fs_write is idempotent: identical content -> no second journal entry" {
    fs_write "$T/b.conf" <<< 'x'
    fs_write "$T/b.conf" <<< 'x'
    [ "$(grep -c "$T/b.conf" "$(rb_journal)")" -eq 1 ]
}

@test "modifying a file backs it up first; rollback restores it" {
    printf 'original\n' > "$T/c.conf"
    fs_write "$T/c.conf" <<< 'changed'
    [ "$(cat "$T/c.conf")" = changed ]
    rollback_run "$ARCON_RUN_DIR" 0
    [ "$(cat "$T/c.conf")" = original ]
}

@test "rollback removes files that ArCoN created" {
    fs_write "$T/d.conf" <<< 'new'
    rollback_run "$ARCON_RUN_DIR" 0
    [ ! -e "$T/d.conf" ]
}

@test "fs_append_once never duplicates a line" {
    fs_append_once "$T/e" "line"
    fs_append_once "$T/e" "line"
    [ "$(grep -c '^line$' "$T/e")" -eq 1 ]
}

@test "fs_set_kv replaces an existing key instead of appending a duplicate" {
    printf 'A=1\nZSH_THEME="robbyrussell"\n' > "$T/zshrc"
    fs_set_kv "$T/zshrc" '^ZSH_THEME=' 'ZSH_THEME="agnoster"'
    fs_set_kv "$T/zshrc" '^ZSH_THEME=' 'ZSH_THEME="agnoster"'
    [ "$(grep -c '^ZSH_THEME=' "$T/zshrc")" -eq 1 ]
    grep -q 'agnoster' "$T/zshrc"
}

@test "fs_remove keeps a backup and rollback brings the directory back" {
    mkdir -p "$T/cfgdir"; echo keep > "$T/cfgdir/file"
    fs_remove "$T/cfgdir"
    [ ! -e "$T/cfgdir" ]
    rollback_run "$ARCON_RUN_DIR" 0
    [ "$(cat "$T/cfgdir/file")" = keep ]
}

@test "irreversible steps are recorded and reported by rollback" {
    rb_note_irreversible "journal vacuumed"
    run rollback_run "$ARCON_RUN_DIR" 0
    [[ "$output" == *"journal vacuumed"* ]]
}
