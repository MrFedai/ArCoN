#!/usr/bin/env bash
# ArCoN v3.0 -- setup.sh  (entry point)
#
# IMPORTANT: this file must stay compatible with bash 3.2, because that is the
# /bin/bash shipped with macOS. It only detects the platform, makes sure a
# bash >= 4.2 interpreter is used (associative arrays are required by the core)
# and then hands over to core/main.sh.
#
# Usage: ./setup.sh [options]   (see --help)

set -u

ARCON_ROOT_DIR=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd -P)
export ARCON_ROOT="$ARCON_ROOT_DIR"

_arcon_err() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; }
_arcon_info() { printf '\033[1;34m[*]\033[0m %s\n' "$1"; }

# --- bash version gate -------------------------------------------------------
_bash_ok() {
    # $1 = bash binary; requires >= 4.2
    local v
    v=$("$1" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2>/dev/null) || return 1
    case "$v" in
        [5-9].*|[1-9][0-9].*) return 0 ;;
        4.[2-9]|4.[1-9][0-9]) return 0 ;;
        *) return 1 ;;
    esac
}

if ! _bash_ok "$BASH"; then
    for _cand in /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash 2>/dev/null)"; do
        [ -n "$_cand" ] && [ -x "$_cand" ] || continue
        if _bash_ok "$_cand"; then
            _arcon_info "re-executing with a newer bash: $_cand"
            exec "$_cand" "$0" "$@"
        fi
    done
    _arcon_err "ArCoN v3.0 requires bash 4.2 or newer (found ${BASH_VERSION})."
    case "$(uname -s)" in
        Darwin)
            _arcon_err "macOS ships bash 3.2. Install a current bash and re-run:"
            _arcon_err "    brew install bash && ./setup.sh"
            [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ] || \
                _arcon_err "Homebrew itself: https://brew.sh" ;;
        *)
            _arcon_err "Install bash >= 4.2 from your distribution's repositories." ;;
    esac
    exit 4
fi

# shellcheck source=core/main.sh
. "$ARCON_ROOT/core/main.sh"
arcon_main "$@"
