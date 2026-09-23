#!/usr/bin/env bash
# ArCoN v3.0 -- platform/detect.sh
# OS / distribution / package-manager detection.
#
# Sets:
#   OS_FAMILY     linux | macos
#   OS_ID         arch | debian | ubuntu | fedora | opensuse | macos | <raw id>
#   OS_LIKE       raw ID_LIKE (linux)
#   OS_NAME       pretty name
#   OS_VERSION    version id
#   OS_SUPPORT    tested | experimental | unsupported
#   PKG_PROVIDER  pacman | apt | dnf | zypper | brew
#
# Test hook: ARCON_SYSROOT prefixes every file path (fixtures in tests/fixtures)
#            ARCON_UNAME_S overrides `uname -s`.

[[ -n "${_ARCON_DETECT_SH:-}" ]] && return 0
_ARCON_DETECT_SH=1

: "${ARCON_SYSROOT:=}"

_os_release_get() {
    # safe parse of os-release (never sourced: v2.5 did `. /etc/os-release`)
    local key="$1" file="${ARCON_SYSROOT}/etc/os-release" line v
    [[ -f "$file" ]] || file="${ARCON_SYSROOT}/usr/lib/os-release"
    [[ -f "$file" ]] || return 1
    while IFS= read -r line; do
        if [[ "$line" == "$key="* ]]; then
            v="${line#*=}"; v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
            printf '%s' "$v"; return 0
        fi
    done < "$file"
    return 1
}

# normalize_distro <ID> <ID_LIKE> -> canonical family id
normalize_distro() {
    local id="${1,,}" like=" ${2,,} "
    case "$id" in
        arch|archarm|endeavouros|manjaro|garuda|cachyos|artix) printf 'arch' ;;
        debian|raspbian|kali|devuan) printf 'debian' ;;
        ubuntu|pop|linuxmint|elementary|zorin|neon) printf 'ubuntu' ;;
        fedora|nobara|ultramarine) printf 'fedora' ;;
        opensuse*|sles|sled) printf 'opensuse' ;;
        *)
            if   [[ "$like" == *" arch "* ]]; then printf 'arch'
            elif [[ "$like" == *" ubuntu "* ]]; then printf 'ubuntu'
            elif [[ "$like" == *" debian "* ]]; then printf 'debian'
            elif [[ "$like" == *" fedora "* || "$like" == *" rhel "* ]]; then printf 'fedora'
            elif [[ "$like" == *" suse "* || "$like" == *" opensuse "* ]]; then printf 'opensuse'
            else printf '%s' "$id"; fi ;;
    esac
}

platform_detect() {
    local uname_s="${ARCON_UNAME_S:-$(uname -s)}"
    OS_RAW_ID=""; OS_LIKE=""
    case "$uname_s" in
        Darwin)
            OS_FAMILY=macos; OS_ID=macos; OS_RAW_ID=macos
            OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
            OS_NAME="macOS $OS_VERSION"
            PKG_PROVIDER=brew ;;
        Linux)
            OS_FAMILY=linux
            OS_RAW_ID="$(_os_release_get ID || true)"
            OS_LIKE="$(_os_release_get ID_LIKE || true)"
            OS_NAME="$(_os_release_get PRETTY_NAME || echo Linux)"
            OS_VERSION="$(_os_release_get VERSION_ID || echo rolling)"
            [[ -n "$OS_RAW_ID" ]] || { log_error "cannot read /etc/os-release — unsupported Linux"; return 1; }
            OS_ID="$(normalize_distro "$OS_RAW_ID" "$OS_LIKE")"
            case "$OS_ID" in
                arch) PKG_PROVIDER=pacman ;;
                debian|ubuntu) PKG_PROVIDER=apt ;;
                fedora) PKG_PROVIDER=dnf ;;
                opensuse) PKG_PROVIDER=zypper ;;
                *) PKG_PROVIDER="" ;;
            esac ;;
        MINGW*|MSYS*|CYGWIN*)
            log_error "Windows detected: run setup.ps1 from PowerShell instead of setup.sh"
            return 1 ;;
        *)
            log_error "unsupported operating system: $uname_s"
            return 1 ;;
    esac

    # support tier: only the distributions exercised by CI are "tested"
    case "$OS_RAW_ID" in
        arch|debian|ubuntu|fedora|opensuse-tumbleweed|opensuse-leap|macos) OS_SUPPORT=tested ;;
        *) if [[ -n "$PKG_PROVIDER" ]]; then OS_SUPPORT=experimental; else OS_SUPPORT=unsupported; fi ;;
    esac
    export OS_FAMILY OS_ID OS_RAW_ID OS_LIKE OS_NAME OS_VERSION OS_SUPPORT PKG_PROVIDER
    log_debug "platform: family=$OS_FAMILY id=$OS_ID raw=$OS_RAW_ID like='$OS_LIKE' ver=$OS_VERSION pkg=$PKG_PROVIDER tier=$OS_SUPPORT"
}

# catalog column used for the current platform
platform_catalog_column() {
    case "$OS_ID" in
        arch|debian|ubuntu|fedora|opensuse) printf '%s' "$OS_ID" ;;
        macos) printf 'brew' ;;
        *) printf '' ;;
    esac
}

is_linux() { [[ "$OS_FAMILY" == linux ]]; }
is_macos() { [[ "$OS_FAMILY" == macos ]]; }
is_arch()  { [[ "$OS_ID" == arch ]]; }
is_debian_like() { [[ "$OS_ID" == debian || "$OS_ID" == ubuntu ]]; }
has_systemd() { [[ -d "${ARCON_SYSROOT}/run/systemd/system" ]] && command -v systemctl >/dev/null 2>&1; }
