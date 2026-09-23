#!/usr/bin/env bash
# ArCoN v3.0 -- platform/pkg/flatpak.sh
# Optional Linux fallback provider (PKG_ALLOW_FLATPAK=yes) for applications
# that are not in a distribution's official repositories (Discord, Spotify,
# Obsidian, Steam on Debian/Fedora/openSUSE, ...). Adding the Flathub remote is
# a repository change and is shown in the plan / confirmed like any other.

flatpak_has_flathub() { flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; }

flatpak_ensure() {
    if ! command -v flatpak >/dev/null 2>&1; then
        pkg_install_ids flatpak || return 1
        is_dry_run && return 0
    fi
    if ! flatpak_has_flathub; then
        x_root REPO "add Flathub remote (https://flathub.org)" -- \
            flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
    fi
}

flatpak_is_installed() { flatpak info "$1" >/dev/null 2>&1; }

flatpak_install() {
    local todo=() id
    flatpak_ensure || return 1
    for id in "$@"; do
        if command -v flatpak >/dev/null 2>&1 && flatpak_is_installed "$id"; then log_info "flatpak already installed: $id"
        else todo+=("$id"); fi
    done
    (( ${#todo[@]} )) || return 0
    x_root PKG_INSTALL "flatpak install ${todo[*]}" -- flatpak install -y --noninteractive flathub "${todo[@]}" || return 1
    is_dry_run && return 0
    for id in "${todo[@]}"; do flatpak_is_installed "$id" && rb_add PKG flatpak "$id"; done
}

_pkgp_flatpak_check() { command -v flatpak >/dev/null 2>&1; }
_pkgp_flatpak_installed_list() { flatpak list --app --columns=application 2>/dev/null; }
_pkgp_flatpak_remove() { x_root PKG_REMOVE "flatpak uninstall $*" -- flatpak uninstall -y --noninteractive "$@"; }
