#!/usr/bin/env bats
# UNIT: configuration loader, profiles, validation
load ../helpers/common

setup() { arcon_load; }

@test "values are never evaluated by the shell" {
    printf 'A=$(touch %s/pwned)\nB=`id`\nC="quoted value" # comment\nD=# only comment\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/c.conf"
    cfg_load_file "$BATS_TEST_TMPDIR/c.conf" t 1
    [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
    [ "$(cfg A)" = '$(touch '"$BATS_TEST_TMPDIR"'/pwned)' ]
    [ "$(cfg B)" = '`id`' ]
    [ "$(cfg C)" = 'quoted value' ]
    [ "$(cfg D)" = '' ]
}

@test "invalid syntax is rejected with file:line" {
    printf 'GOOD=1\nnot valid\n' > "$BATS_TEST_TMPDIR/bad.conf"
    run cfg_load_file "$BATS_TEST_TMPDIR/bad.conf" t 1
    [ "$status" -ne 0 ]
    [[ "$output" == *bad.conf:2* ]]
}

@test "later layers win and the source is tracked" {
    cfg_load_file "$ARCON_REPO/config/defaults.conf" defaults 1
    cfg_load_file "$ARCON_REPO/profiles/gaming.conf" profile/gaming 1
    cfg_set_kv OPT_PROFILE=developer cli
    [ "$(cfg OPT_PROFILE)" = developer ]
    [ "${ARCON_CFG_SRC[OPT_PROFILE]}" = cli ]
    cfg_bool GAMING
}

@test "every shipped profile loads and validates" {
    local p
    for p in "$ARCON_REPO"/profiles/*.conf; do
        ARCON_CFG=(); ARCON_CFG_SRC=()
        cfg_load_file "$ARCON_REPO/config/defaults.conf" defaults 1
        cfg_load_file "$p" "$(basename "$p")" 1
        cfg_validate || { echo "profile $(basename "$p") invalid"; return 1; }
    done
}

@test "no profile enables an aggressive or destructive default" {
    local p
    for p in "$ARCON_REPO"/profiles/*.conf; do
        ! grep -qE '^(BASE_GPG_RESET|BLACKARCH_OVERWRITE|SEC_USBGUARD)=yes' "$p" || { echo "$p enables a destructive step"; return 1; }
    done
    grep -q '^OPT_PROFILE=minimal' "$ARCON_REPO/config/defaults.conf"
}

@test "invalid enum values are rejected" {
    cfg_load_file "$ARCON_REPO/config/defaults.conf" defaults 1
    cfg_set SHELL_STARSHIP_PRESET pastel      # v2.5 value that does not exist upstream
    run cfg_validate
    [ "$status" -ne 0 ]
}

@test "list helpers" {
    cfg_set L "a, b,c"
    cfg_list_has L b
    ! cfg_list_has L d
    [ "$(cfg_list L | wc -l)" -eq 3 ]
}
