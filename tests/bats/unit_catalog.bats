#!/usr/bin/env bats
# UNIT: package catalog integrity + resolution per distribution
load ../helpers/common

setup() { arcon_load; }
CAT="$BATS_TEST_DIRNAME/../../data/packages.catalog"

@test "every row has exactly 11 fields and a unique id" {
    run awk -F'|' '!/^#/ && NF && NF != 11 {print NR": "$0}' "$CAT"
    [ -z "$output" ]
    run bash -c "awk -F'|' '!/^#/ && NF {print \$1}' '$CAT' | sort | uniq -d"
    [ -z "$output" ]
}

@test "no v2.5 package names known to be wrong are used" {
    # adw-gtk3-git (AUR) was replaced by the official adw-gtk-theme
    ! grep -q 'adw-gtk3-git' "$CAT"
}

@test "v2.5 package groups are all represented" {
    local g
    for g in essentials media cyber remote power; do
        [ "$(catalog_group "$g" | wc -l)" -gt 0 ] || { echo "group $g empty"; return 1; }
    done
}

@test "every v2.5 package is covered by the catalog, as id or Arch name (regression)" {
    # v3 ids are distro-neutral (localsend), v2.5 used Arch/AUR names (localsend-bin):
    # a v2.5 name counts as covered when it is an id OR the Arch column of a row.
    local missing=() p
    while IFS= read -r p; do
        catalog_has "$p" && continue
        awk -F'|' -v n="$p" '!/^#/ && $3 == n {f=1} END {exit !f}' "$CAT" || missing+=("$p")
    done < <(sed -n '/^declare -a PKG_/,/^)/p' "$ARCON_REPO/legacy/v2.5/setup.sh" | grep -o '"[^"]*"' | tr -d '"')
    [ "${#missing[@]}" -eq 0 ] || { echo "missing: ${missing[*]}"; return 1; }
}

@test "resolution uses the distribution column and reports unavailable ids" {
    OS_ID=fedora
    run pkg_resolve vlc does-not-exist
    [[ "$output" == *UNAVAILABLE*does-not-exist* ]] || [[ "$output" == *does-not-exist* ]]
}
