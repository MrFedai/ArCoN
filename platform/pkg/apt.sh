#!/usr/bin/env bash
# ArCoN v3.0 -- platform/pkg/apt.sh   (Debian / Ubuntu)

_APT_NAMES_LOADED=0
declare -gA _APT_NAMES=()

_pkgp_apt_check() { command -v apt-get >/dev/null 2>&1 && command -v dpkg-query >/dev/null 2>&1; }

_pkgp_apt_installed_list() {
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1 ~ /^ii/ {print $2}'
}

_apt_load_names() {
    (( _APT_NAMES_LOADED == 1 )) && return 0
    local n
    while IFS= read -r n; do _APT_NAMES["$n"]=1; done < <(apt-cache pkgnames 2>/dev/null)
    _APT_NAMES_LOADED=1
}

_pkgp_apt_available_filter() {
    _apt_load_names
    local n
    for n in "$@"; do [[ -n "${_APT_NAMES[$n]+x}" ]] && printf '%s\n' "$n"; done
}

_apt_env() { [[ "${ARCON_INTERACTIVE:-1}" == "1" ]] && echo "" || echo "DEBIAN_FRONTEND=noninteractive"; }

_pkgp_apt_refresh() {
    x_root COMMAND "apt-get update" -- env DEBIAN_FRONTEND=noninteractive apt-get update
    _APT_NAMES_LOADED=0
}

_pkgp_apt_install() {
    local avail=() n
    _apt_load_names
    for n in "$@"; do
        if [[ -n "${_APT_NAMES[$n]+x}" ]]; then avail+=("$n")
        else log_warn "apt: package '$n' not found in enabled repositories"; fi
    done
    (( ${#avail[@]} )) || return 1
    x_root PKG_INSTALL "apt-get install ${avail[*]}" -- env DEBIAN_FRONTEND=noninteractive apt-get install -y "${avail[@]}"
}

_pkgp_apt_remove() {
    # v2.5 used remove --purge; kept (configs under /etc are purged, user dotfiles untouched)
    x_root PKG_REMOVE "apt-get remove --purge $*" -- env DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y "$@"
}

_pkgp_apt_upgrade() {
    x_root PKG_INSTALL "apt-get upgrade" -- env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
}

_pkgp_apt_search() { apt-cache search -- "$1"; }

apt_component_enabled() {
    # apt_component_enabled contrib|non-free|multiverse|universe
    grep -rhsE "^[^#]*(deb|Components:).*\b$1\b" "${ARCON_SYSROOT}/etc/apt/sources.list" "${ARCON_SYSROOT}/etc/apt/sources.list.d/" >/dev/null 2>&1
}
