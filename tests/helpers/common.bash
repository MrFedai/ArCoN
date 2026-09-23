# shellcheck disable=SC1090  # libraries are sourced from a computed repo path
# Shared bats helpers for ArCoN v3.0.
# Loads the core, platform and module libraries into the test shell WITHOUT
# running core/main.sh, and isolates HOME/XDG/state into a temp dir.

ARCON_REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
export ARCON_REPO

arcon_isolate() {
    export ARCON_TEST_TMP="$BATS_TEST_TMPDIR"
    export HOME="$ARCON_TEST_TMP/home"; mkdir -p "$HOME"
    export XDG_STATE_HOME="$HOME/.local/state" XDG_CONFIG_HOME="$HOME/.config"
    ARCON_USER="$(id -un)"; export ARCON_ROOT="$ARCON_REPO" ARCON_HOME="$HOME" ARCON_USER
    export ARCON_TMP="$ARCON_TEST_TMP/tmp"; mkdir -p "$ARCON_TMP"
    export ARCON_STATE_DIR="$XDG_STATE_HOME/arcon" ARCON_LOG_DIR="$XDG_STATE_HOME/arcon/logs"
    ARCON_EUID="$(id -u)"; export ARCON_INTERACTIVE=0 ARCON_NO_COLOR=1 ARCON_DRY_RUN=0 ARCON_EUID
}

arcon_load() {
    arcon_isolate
    local f
    for f in log ui config exec fs rollback state cli; do . "$ARCON_REPO/core/$f.sh"; done
    . "$ARCON_REPO/platform/detect.sh"
    . "$ARCON_REPO/platform/hardware.sh"
    . "$ARCON_REPO/platform/pkg/pkg.sh"
    for f in "$ARCON_REPO"/modules/*.sh; do . "$f"; done
    ui_init_colors
    log_init "$ARCON_TEST_TMP/test.log"
}

# Put the package-manager test doubles first in PATH.
arcon_use_mocks() {
    export ARCON_MOCK_LOG="$ARCON_TEST_TMP/mock.log"
    export ARCON_MOCK_INSTALLED="$ARCON_TEST_TMP/installed.txt"
    export ARCON_MOCK_AVAILABLE="$ARCON_TEST_TMP/available.txt"
    : > "$ARCON_MOCK_LOG"; : > "$ARCON_MOCK_INSTALLED"; : > "$ARCON_MOCK_AVAILABLE"
    export PATH="$ARCON_REPO/tests/mocks/bin:$PATH"
}

# arcon_fake_distro <fixture> [hw-mock] -> platform + hardware from fixtures
arcon_fake_distro() {
    export ARCON_SYSROOT="$ARCON_REPO/tests/fixtures/os/$1"
    export ARCON_UNAME_S=Linux
    [[ -n "${2:-}" ]] && export ARCON_HW_MOCK="$ARCON_REPO/tests/fixtures/hw/$2.env"
    platform_detect
    ARCON_SYSROOT=""   # detection done; tools must not read the fixture tree afterwards
    hw_detect force
}

# run setup.sh as a subprocess (isolated state), with mocks available
run_setup() {
    run env HOME="$HOME" XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        ARCON_NO_COLOR=1 "$ARCON_REPO/setup.sh" "$@"
}
