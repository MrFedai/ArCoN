#!/usr/bin/env bash
# ArCoN v3.0 -- platform/pkg/pacman.sh
# Arch Linux provider: pacman for official repos, yay/paru for AUR.
# Routing is identical to v2.5: a name found in the sync DB is official,
# otherwise it is treated as an AUR package (when PKG_ALLOW_AUR=yes).

_PACMAN_SYNC_LOADED=0
declare -gA _PACMAN_SYNC=()

_pkgp_pacman_check() { command -v pacman >/dev/null 2>&1; }

_pkgp_pacman_installed_list() { pacman -Qq 2>/dev/null; }

_pacman_load_sync() {
    (( _PACMAN_SYNC_LOADED == 1 )) && return 0
    local n
    while IFS= read -r n; do _PACMAN_SYNC["$n"]=1; done < <(pacman -Slq 2>/dev/null)
    # groups (e.g. base-devel is a meta package, blackarch-* are groups)
    while IFS= read -r n; do _PACMAN_SYNC["$n"]=1; done < <(pacman -Sgq 2>/dev/null | sort -u; pacman -Sg 2>/dev/null | awk '{print $1}' | sort -u)
    _PACMAN_SYNC_LOADED=1
}

pacman_is_official() { _pacman_load_sync; [[ -n "${_PACMAN_SYNC[$1]+x}" ]]; }

aur_helper() {
    local h; h="$(cfg AUR_HELPER yay)"
    command -v "$h" >/dev/null 2>&1 && { printf '%s' "$h"; return 0; }
    for h in yay paru; do command -v "$h" >/dev/null 2>&1 && { printf '%s' "$h"; return 0; }; done
    return 1
}

_pkgp_pacman_available_filter() {
    local n
    for n in "$@"; do
        if pacman_is_official "$n"; then printf '%s\n' "$n"
        elif cfg_bool PKG_ALLOW_AUR yes; then printf '%s\n' "$n"   # verified by helper at install time
        fi
    done
}

_pkgp_pacman_refresh() {
    # v2.5 used `pacman -Sy <pkg>` in places (partial upgrade risk). v3 only
    # refreshes together with a full upgrade (-Syu) — see base module.
    x_root COMMAND "sync pacman databases" -- pacman -Sy --noconfirm
}

_pkgp_pacman_install() {
    local official=() aur=() n rc=0 helper
    for n in "$@"; do if pacman_is_official "$n"; then official+=("$n"); else aur+=("$n"); fi; done
    if (( ${#official[@]} )); then
        x_root PKG_INSTALL "pacman install ${official[*]}" -- pacman -S --needed --noconfirm "${official[@]}" || rc=1
    fi
    if (( ${#aur[@]} )); then
        if ! cfg_bool PKG_ALLOW_AUR yes; then
            log_warn "AUR disabled (PKG_ALLOW_AUR=no): ${aur[*]}"; return 1
        fi
        helper="$(aur_helper)" || { log_error "AUR packages requested but no AUR helper (yay/paru) is installed: ${aur[*]}"; return 1; }
        local flags=(-S --needed)
        case "$helper" in
            yay)  flags+=(--answerdiff=None --answerclean=None) ;;
            paru) flags+=(--skipreview) ;;
        esac
        [[ "${ARCON_INTERACTIVE:-1}" != "1" ]] && flags+=(--noconfirm)
        if [[ "${ARCON_INTERACTIVE:-1}" == "1" ]]; then
            x_utty PKG_INSTALL "$helper install (AUR) ${aur[*]}" -- "$helper" "${flags[@]}" "${aur[@]}" || rc=1
        else
            x_user PKG_INSTALL "$helper install (AUR) ${aur[*]}" -- "$helper" "${flags[@]}" "${aur[@]}" || rc=1
        fi
    fi
    return $rc
}

_pkgp_pacman_remove() {
    # -Rs (not -Rns / -Rc): remove package + unneeded deps, never cascade (v2.5 behaviour kept)
    x_root PKG_REMOVE "pacman remove $*" -- pacman -Rs --noconfirm "$@"
}

_pkgp_pacman_upgrade() { x_root PKG_INSTALL "full system upgrade" -- pacman -Syu --noconfirm; }

_pkgp_pacman_search() { pacman -Ss -- "$1"; }

# helpers used by optimize/cleanup
pacman_orphans() { pacman -Qdtq 2>/dev/null; }

# pacman_download_size <names...> -> "name<TAB>size unit" (batched -Si, v2.5 preview table)
pacman_download_size() {
    (( $# )) || return 0
    LC_ALL=C pacman -Si "$@" 2>/dev/null | awk -F': *' '
        /^Name/ {n=$2}
        /^Download Size/ {print n "\t" $2}'
}

pacman_repo_enabled() { grep -q "^\[$1\]" "${ARCON_SYSROOT}/etc/pacman.conf" 2>/dev/null; }
