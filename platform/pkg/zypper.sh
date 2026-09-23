#!/usr/bin/env bash
# ArCoN v3.0 -- platform/pkg/zypper.sh   (openSUSE Tumbleweed / Leap)

_pkgp_zypper_check() { command -v zypper >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; }

_pkgp_zypper_installed_list() { rpm -qa --qf '%{NAME}\n' 2>/dev/null; }

_pkgp_zypper_is_installed() {
    [[ "$1" == pattern:* ]] || return 1
    rpm -q "patterns-$(printf '%s' "${1#pattern:}" | tr '_' '-')" >/dev/null 2>&1 ||
        zypper -q search -i -t pattern "${1#pattern:}" 2>/dev/null | grep -q '^i'
}

_pkgp_zypper_available_filter() {
    local n
    for n in "$@"; do
        if [[ "$n" == pattern:* ]]; then printf '%s\n' "$n"; continue; fi
        zypper -q --no-refresh search --match-exact -t package -- "$n" 2>/dev/null | grep -q "| $n " && printf '%s\n' "$n"
    done
}

_pkgp_zypper_refresh() { x_root COMMAND "zypper refresh" -- zypper --non-interactive refresh; }

_pkgp_zypper_install() {
    local pkgs=() pats=() n rc=0
    for n in "$@"; do if [[ "$n" == pattern:* ]]; then pats+=("${n#pattern:}"); else pkgs+=("$n"); fi; done
    (( ${#pkgs[@]} )) && { x_root PKG_INSTALL "zypper install ${pkgs[*]}" -- zypper --non-interactive install --no-recommends "${pkgs[@]}" || rc=1; }
    (( ${#pats[@]} )) && { x_root PKG_INSTALL "zypper install pattern ${pats[*]}" -- zypper --non-interactive install -t pattern "${pats[@]}" || rc=1; }
    return $rc
}

_pkgp_zypper_remove() { x_root PKG_REMOVE "zypper remove $*" -- zypper --non-interactive remove --clean-deps "$@"; }

_pkgp_zypper_upgrade() {
    # Tumbleweed must use dist-upgrade; Leap uses update
    if [[ "${OS_RAW_ID:-}" == opensuse-tumbleweed ]]; then
        x_root PKG_INSTALL "zypper dist-upgrade" -- zypper --non-interactive dist-upgrade
    else
        x_root PKG_INSTALL "zypper update" -- zypper --non-interactive update
    fi
}

_pkgp_zypper_search() { zypper -q search -- "$1"; }
