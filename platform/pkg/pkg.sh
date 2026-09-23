#!/usr/bin/env bash
# ArCoN v3.0 -- platform/pkg/pkg.sh
# PackageManager facade. Modules call ONLY these functions; never pacman/apt/... directly.
#
#   pkg_init                      load provider for $PKG_PROVIDER
#   pkg_refresh                   update package database (once per run)
#   pkg_is_installed <native>
#   pkg_available <native>        exists in configured repositories
#   pkg_install <native...>       idempotent (installed ones are skipped)
#   pkg_remove <native...>        only installed ones are removed
#   pkg_upgrade_all
#   pkg_search <term>
#   pkg_resolve <catalog-id...>   -> prints native names (unavailable ids go to stderr as "UNAVAILABLE id")
#   pkg_install_ids <catalog-id...>
#
# Provider contract (platform/pkg/<provider>.sh) — each implements:
#   _pkgp_<p>_installed_list  _pkgp_<p>_available_filter <names...>
#   _pkgp_<p>_refresh  _pkgp_<p>_install <names...>  _pkgp_<p>_remove <names...>
#   _pkgp_<p>_upgrade  _pkgp_<p>_search <term>

[[ -n "${_ARCON_PKG_SH:-}" ]] && return 0
_ARCON_PKG_SH=1

declare -gA _PKG_INSTALLED=()
_PKG_CACHE_VALID=0
_PKG_REFRESHED=0
PKG_LAST_FAILED=()
PKG_LAST_INSTALLED=()
PKG_LAST_SKIPPED=()

# pkg_load_provider <name> -> makes _pkgp_<name>_* available (idempotent)
pkg_load_provider() {
    local p="$1"
    [[ -n "$p" ]] || return 1
    declare -F "_pkgp_${p}_installed_list" >/dev/null && return 0
    [[ -f "$ARCON_ROOT/platform/pkg/$p.sh" ]] || { log_error "unknown package provider: $p"; return 1; }
    # shellcheck source=/dev/null
    source "$ARCON_ROOT/platform/pkg/$p.sh" || { log_error "cannot load package provider '$p'"; return 1; }
    return 0
}

# pkg_use_provider <name> -> switch the active provider (rollback across providers)
pkg_use_provider() {
    pkg_load_provider "$1" || return 1
    PKG_PROVIDER="$1"
    pkg_invalidate
}

pkg_init() {
    local p="${PKG_PROVIDER_OVERRIDE:-$PKG_PROVIDER}"
    [[ -n "$p" ]] || { log_error "no package manager for this platform"; return 1; }
    pkg_load_provider "$p" || return 1
    pkg_load_provider flatpak || true
    if ! declare -F "_pkgp_${p}_check" >/dev/null || ! "_pkgp_${p}_check"; then
        log_error "package manager '$p' is not usable on this system"
        return 1
    fi
    PKG_PROVIDER="$p"
    log_debug "package provider: $p"
}

_pkg_call() { local fn="_pkgp_${PKG_PROVIDER}_$1"; shift; "$fn" "$@"; }

pkg_invalidate() { _PKG_CACHE_VALID=0; }

_pkg_load_cache() {
    (( _PKG_CACHE_VALID == 1 )) && return 0
    # A missing provider must fail loudly: silently returning an empty list would
    # make every package look "not installed" (and rollback a no-op).
    if ! declare -F "_pkgp_${PKG_PROVIDER}_installed_list" >/dev/null; then
        log_error "package provider '${PKG_PROVIDER:-none}' is not loaded (pkg_init/pkg_use_provider missing)"
        return 1
    fi
    _PKG_INSTALLED=()
    local n
    while IFS= read -r n; do [[ -n "$n" ]] && _PKG_INSTALLED["$n"]=1; done < <(_pkg_call installed_list)
    _PKG_CACHE_VALID=1
}

pkg_is_installed() {
    _pkg_load_cache || return 1
    [[ -n "${_PKG_INSTALLED[$1]+x}" ]] && return 0
    # groups/patterns/casks are checked by the provider directly
    declare -F "_pkgp_${PKG_PROVIDER}_is_installed" >/dev/null && _pkg_call is_installed "$1"
}

pkg_refresh() {
    (( _PKG_REFRESHED == 1 )) && return 0
    _pkg_call refresh || { log_error "package database refresh failed (network? mirrors? lock?)"; return 1; }
    _PKG_REFRESHED=1
}

pkg_available() { [[ -n "$(_pkg_call available_filter "$1")" ]]; }

# pkg_install <names...>  — sets PKG_LAST_INSTALLED / PKG_LAST_SKIPPED / PKG_LAST_FAILED
pkg_install() {
    PKG_LAST_INSTALLED=(); PKG_LAST_SKIPPED=(); PKG_LAST_FAILED=(); PKG_LAST_UNAVAILABLE=()
    local todo=() n
    for n in "$@"; do
        [[ -z "$n" ]] && continue
        if pkg_is_installed "$n"; then PKG_LAST_SKIPPED+=("$n"); else todo+=("$n"); fi
    done
    (( ${#PKG_LAST_SKIPPED[@]} )) && log_info "already installed: ${PKG_LAST_SKIPPED[*]}"
    (( ${#todo[@]} == 0 )) && return 0
    # Repository availability (catalog names can be missing on older releases,
    # e.g. hyprland on Ubuntu 24.04). Unavailable names are reported and skipped,
    # never silently dropped; they do not block the available ones.
    local -A _avail=(); local ok=() missing=()
    while IFS= read -r n; do [[ -n "$n" ]] && _avail["$n"]=1; done < <(_pkg_call available_filter "${todo[@]}")
    for n in "${todo[@]}"; do
        if [[ -n "${_avail[$n]+x}" ]]; then ok+=("$n"); else missing+=("$n"); fi
    done
    PKG_LAST_UNAVAILABLE=("${missing[@]+"${missing[@]}"}")
    if (( ${#missing[@]} )); then
        log_warn "not available from the $PKG_PROVIDER repositories (skipped): ${missing[*]}"
        if is_dry_run; then
            for n in "${missing[@]}"; do plan_record PKG_UNAVAILABLE "$n  ($PKG_PROVIDER)"; done
        fi
    fi
    todo=("${ok[@]+"${ok[@]}"}")
    (( ${#todo[@]} == 0 )) && return 0
    if is_dry_run; then
        for n in "${todo[@]}"; do plan_record PKG_INSTALL "$n  (via $PKG_PROVIDER)"; done
        return 0
    fi
    # batch first (fast path), then per-package fallback to isolate failures
    if _pkg_call install "${todo[@]}"; then
        pkg_invalidate
    else
        log_warn "batch install failed — retrying packages one by one to isolate the failure"
        pkg_invalidate
        for n in "${todo[@]}"; do pkg_is_installed "$n" || _pkg_call install "$n" || true; done
        pkg_invalidate
    fi
    for n in "${todo[@]}"; do
        if pkg_is_installed "$n"; then PKG_LAST_INSTALLED+=("$n"); rb_add PKG "$PKG_PROVIDER" "$n"
        else PKG_LAST_FAILED+=("$n"); fi
    done
    (( ${#PKG_LAST_INSTALLED[@]} )) && log_info "installed: ${PKG_LAST_INSTALLED[*]}"
    (( ${#PKG_LAST_FAILED[@]} )) && { log_error "failed to install: ${PKG_LAST_FAILED[*]}"; return 1; }
    return 0
}

pkg_remove() {
    local todo=() n
    for n in "$@"; do pkg_is_installed "$n" && todo+=("$n"); done
    (( ${#todo[@]} == 0 )) && { log_debug "nothing to remove"; return 0; }
    if is_dry_run; then
        for n in "${todo[@]}"; do plan_record PKG_REMOVE "$n  (via $PKG_PROVIDER)"; done
        return 0
    fi
    _pkg_call remove "${todo[@]}"; local rc=$?
    pkg_invalidate
    return $rc
}

pkg_upgrade_all() {
    if is_dry_run; then plan_record PKG_INSTALL "full system upgrade (via $PKG_PROVIDER)"; return 0; fi
    _pkg_call upgrade
}

pkg_search() { _pkg_call search "$1"; }

# ------------------------------------------------------------ catalog
: "${ARCON_CATALOG:=$ARCON_ROOT/data/packages.catalog}"
declare -gA _CAT_ROW=()
_CAT_LOADED=0
CAT_COLUMNS=(id groups arch debian ubuntu fedora opensuse brew winget flatpak description)

catalog_load() {
    (( _CAT_LOADED == 1 )) && return 0
    local line id
    [[ -r "$ARCON_CATALOG" ]] || { log_error "package catalog missing: $ARCON_CATALOG"; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        id="${line%%|*}"
        _CAT_ROW["$id"]="$line"
    done < "$ARCON_CATALOG"
    _CAT_LOADED=1
}

# catalog_field <id> <column>
catalog_field() {
    catalog_load
    local row="${_CAT_ROW[$1]:-}" i
    [[ -n "$row" ]] || return 1
    local IFS='|'; local -a f; read -r -a f <<< "$row"
    for i in "${!CAT_COLUMNS[@]}"; do
        [[ "${CAT_COLUMNS[$i]}" == "$2" ]] && { printf '%s' "${f[$i]}"; return 0; }
    done
    return 1
}

catalog_has() { catalog_load; [[ -n "${_CAT_ROW[$1]+x}" ]]; }

# catalog_group <group> -> ids (catalog order)
catalog_group() {
    catalog_load
    awk -F'|' -v g="$1" '!/^#/ && NF>2 { n=split($2,a,","); for(i=1;i<=n;i++) if (a[i]==g) { print $1; break } }' "$ARCON_CATALOG"
}

# pkg_resolve <ids...> : prints "native<TAB>source" (source: native|flatpak) per resolvable id,
# unresolvable ids are reported via UNAVAILABLE lines on stderr.
pkg_resolve() {
    local col id name fp
    col="$(platform_catalog_column)"
    for id in "$@"; do
        if ! catalog_has "$id"; then
            printf '%s\tnative\n' "$id"   # raw native name (pacs.txt compatibility)
            continue
        fi
        name="$(catalog_field "$id" "$col")"
        if [[ -n "$name" && "$name" != "-" ]]; then
            printf '%s\tnative\n' "$name"
        else
            fp="$(catalog_field "$id" flatpak)"
            if is_linux && cfg_bool PKG_ALLOW_FLATPAK && [[ -n "$fp" && "$fp" != "-" ]]; then
                printf '%s\tflatpak\n' "$fp"
            else
                printf 'UNAVAILABLE %s on %s\n' "$id" "$OS_ID" >&2
            fi
        fi
    done
}

pkg_install_ids() {
    local native=() flat=() line name src rc=0
    while IFS=$'\t' read -r name src; do
        [[ -z "$name" ]] && continue
        if [[ "$src" == flatpak ]]; then flat+=("$name"); else native+=("$name"); fi
    done < <(pkg_resolve "$@" 2> >(while read -r line; do log_warn "$line (platform-inapplicable, skipped)"; done))
    (( ${#native[@]} )) && { pkg_install "${native[@]}" || rc=1; }
    (( ${#flat[@]} )) && { flatpak_install "${flat[@]}" || rc=1; }
    return $rc
}
