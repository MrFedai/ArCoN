#!/usr/bin/env bash
# ArCoN v3.0 -- platform/pkg/brew.sh   (macOS Homebrew; formulae and "cask:" names)
# Homebrew refuses to run as root, so every call goes through x_user.

_pkgp_brew_check() { command -v brew >/dev/null 2>&1; }

_pkgp_brew_installed_list() {
    as_user brew list --formula -1 2>/dev/null
    as_user brew list --cask -1 2>/dev/null | sed 's/^/cask:/'
}

_pkgp_brew_available_filter() {
    local n
    for n in "$@"; do
        if [[ "$n" == cask:* ]]; then as_user brew info --cask "${n#cask:}" >/dev/null 2>&1 && printf '%s\n' "$n"
        else as_user brew info --formula "$n" >/dev/null 2>&1 && printf '%s\n' "$n"; fi
    done
}

_pkgp_brew_refresh() { x_user COMMAND "brew update" -- brew update; }

_pkgp_brew_install() {
    local f=() c=() n rc=0
    for n in "$@"; do if [[ "$n" == cask:* ]]; then c+=("${n#cask:}"); else f+=("$n"); fi; done
    (( ${#f[@]} )) && { x_user PKG_INSTALL "brew install ${f[*]}" -- brew install "${f[@]}" || rc=1; }
    (( ${#c[@]} )) && { x_user PKG_INSTALL "brew install --cask ${c[*]}" -- brew install --cask "${c[@]}" || rc=1; }
    return $rc
}

_pkgp_brew_remove() {
    local f=() c=() n rc=0
    for n in "$@"; do if [[ "$n" == cask:* ]]; then c+=("${n#cask:}"); else f+=("$n"); fi; done
    (( ${#f[@]} )) && { x_user PKG_REMOVE "brew uninstall ${f[*]}" -- brew uninstall "${f[@]}" || rc=1; }
    (( ${#c[@]} )) && { x_user PKG_REMOVE "brew uninstall --cask ${c[*]}" -- brew uninstall --cask "${c[@]}" || rc=1; }
    return $rc
}

_pkgp_brew_upgrade() { x_user PKG_INSTALL "brew upgrade" -- brew upgrade; }

_pkgp_brew_search() { as_user brew search -- "$1"; }
