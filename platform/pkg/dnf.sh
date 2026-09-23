#!/usr/bin/env bash
# ArCoN v3.0 -- platform/pkg/dnf.sh   (Fedora; dnf4 and dnf5 compatible calls only)

_pkgp_dnf_check() { command -v dnf >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; }

_pkgp_dnf_installed_list() { rpm -qa --qf '%{NAME}\n' 2>/dev/null; }

_pkgp_dnf_is_installed() {
    # groups: "@development-tools" — ask dnf
    [[ "$1" == @* ]] || return 1
    dnf -q group list --installed 2>/dev/null | grep -qi -- "${1#@}"
}

_pkgp_dnf_available_filter() {
    local groups=() names=() n
    for n in "$@"; do if [[ "$n" == @* ]]; then groups+=("$n"); else names+=("$n"); fi; done
    printf '%s\n' "${groups[@]}" | sed '/^$/d'
    (( ${#names[@]} )) || return 0
    dnf -q repoquery --qf '%{name}\n' "${names[@]}" 2>/dev/null | sort -u
}

_pkgp_dnf_refresh() { x_root COMMAND "dnf makecache" -- dnf -y makecache; }

_pkgp_dnf_install() {
    x_root PKG_INSTALL "dnf install $*" -- dnf install -y "$@"
}

_pkgp_dnf_remove() { x_root PKG_REMOVE "dnf remove $*" -- dnf remove -y "$@"; }

_pkgp_dnf_upgrade() { x_root PKG_INSTALL "dnf upgrade --refresh" -- dnf upgrade -y --refresh; }

_pkgp_dnf_search() { dnf -q search -- "$1"; }

dnf_repo_enabled() { dnf -q repolist --enabled 2>/dev/null | awk '{print $1}' | grep -qx -- "$1"; }
