#!/usr/bin/env bats
# INTEGRATION: the real entry point (./setup.sh) against fixture distributions,
# with package managers replaced by test doubles (tests/mocks/bin).
# Label: INTEGRATION (mocked package managers) -- NOT a VM or native test.
load ../helpers/common

setup() {
    arcon_isolate
    arcon_use_mocks
    export ARCON_HW_MOCK="$ARCON_REPO/tests/fixtures/hw/gaming-nvidia.env"
}

# all names of one catalog column become "available" in the mock repositories
mock_repo_from_catalog() {
    local col
    case "$1" in arch) col=3 ;; debian) col=4 ;; ubuntu) col=5 ;; fedora) col=6 ;; opensuse*) col=7 ;; esac
    awk -F'|' -v c="$col" '!/^#/ && NF==11 && $c != "-" {n=split($c, a, " "); for (i=1;i<=n;i++) print a[i]}' \
        "$ARCON_REPO/data/packages.catalog" | sort -u > "$ARCON_MOCK_AVAILABLE"
}

setup_on() {  # setup_on <fixture> <args...>
    local fx="$1"; shift
    run env HOME="$HOME" XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        ARCON_SYSROOT="$ARCON_REPO/tests/fixtures/os/$fx" ARCON_UNAME_S=Linux \
        ARCON_HW_MOCK="$ARCON_HW_MOCK" ARCON_NO_COLOR=1 PATH="$PATH" \
        ARCON_MOCK_LOG="$ARCON_MOCK_LOG" ARCON_MOCK_INSTALLED="$ARCON_MOCK_INSTALLED" ARCON_MOCK_AVAILABLE="$ARCON_MOCK_AVAILABLE" \
        "$ARCON_REPO/setup.sh" "$@"
}

mutating_calls() {  # package-manager calls that would change the system
    grep -E '^(pacman -S |pacman -S[^lgq]|pacman -R|dnf( -[^ ]+)* (install|remove) |zypper( -[^ ]+)* (in|install|rm|remove) |brew (install|uninstall) )' "$ARCON_MOCK_LOG" || true
}

@test "--help and --version work without touching the system" {
    run "$ARCON_REPO/setup.sh" --help
    [ "$status" -eq 0 ]; [[ "$output" == *"--dry-run"* ]]; [[ "$output" == *"--profile"* ]]
    run "$ARCON_REPO/setup.sh" --version
    [ "$status" -eq 0 ]; [[ "$output" == "ArCoN 3.0.0" ]]
}

@test "unknown options are rejected with exit code 2" {
    run "$ARCON_REPO/setup.sh" --definitely-not-an-option
    [ "$status" -eq 2 ]
}

@test "unknown profile is rejected before anything runs" {
    setup_on arch --dry-run --profile nope -y
    [ "$status" -ne 0 ]; [[ "$output" == *"unknown profile"* ]]
}

@test "unsupported distribution is refused" {
    setup_on alpine --dry-run -y
    [ "$status" -ne 0 ]; [[ "$output" == *unsupported* ]]
}

@test "banner shows OS, CPU, GPU, RAM and disk" {
    mock_repo_from_catalog arch
    setup_on arch --dry-run --profile minimal -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"OS:"*"Arch Linux"* ]]; [[ "$output" == *"CPU:"*"Ryzen"* ]]
    [[ "$output" == *"GPU:"*nvidia* ]]; [[ "$output" == *"RAM:"*"32 GB"* ]]; [[ "$output" == *"Disk:"*nvme* ]]
}

@test "dry-run on every tested distribution: plan shown, zero mutating calls" {
    local fx prov
    for fx in arch debian ubuntu fedora opensuse-tumbleweed; do
        : > "$ARCON_MOCK_LOG"
        mock_repo_from_catalog "$fx"
        case "$fx" in arch) prov=pacman ;; debian|ubuntu) prov=apt ;; fedora) prov=dnf ;; *) prov=zypper ;; esac
        [ "$prov" = apt ] && ! command -v apt-get >/dev/null && continue   # apt needs the real tool
        setup_on "$fx" --dry-run --profile full -y
        [ "$status" -eq 0 ] || { echo "[$fx] rc=$status"; echo "$output" | tail -20; return 1; }
        [[ "$output" == *"DRY-RUN PLAN"* ]] || { echo "[$fx] no plan"; return 1; }
        [[ "$output" == *"(via $prov)"* ]] || { echo "[$fx] provider $prov not used"; return 1; }
        [ -z "$(mutating_calls)" ] || { echo "[$fx] mutating calls in dry-run:"; mutating_calls; return 1; }
    done
}

@test "dry-run leaves no state pointer and creates no user files" {
    mock_repo_from_catalog arch
    setup_on arch --dry-run --profile full -y
    [ "$status" -eq 0 ]
    [ ! -e "$XDG_STATE_HOME/arcon/current" ]
    [ -z "$(find "$HOME" -path "$XDG_STATE_HOME" -prune -o -type f -print)" ]
}

@test "gaming profile on an NVIDIA machine plans the NVIDIA driver + 32-bit Vulkan" {
    mock_repo_from_catalog arch
    setup_on arch --dry-run --profile gaming -y
    [ "$status" -eq 0 ]
    [[ "$output" == *nvidia* ]]
    [[ "$output" == *lib32-nvidia-utils* ]]
    [[ "$output" == *gamemode* ]]
}

@test "gaming profile on an AMD machine does NOT plan NVIDIA packages (v2.5 asked blindly)" {
    mock_repo_from_catalog arch
    ARCON_HW_MOCK="$ARCON_REPO/tests/fixtures/hw/gaming-amd.env"
    setup_on arch --dry-run --profile gaming -y
    [ "$status" -eq 0 ]
    [[ "$output" != *nvidia-open* ]]
    [[ "$output" == *vulkan-radeon* ]]
}

@test "BlackArch is never enabled by any profile default" {
    mock_repo_from_catalog arch
    setup_on arch --dry-run --profile full -y
    [[ "$output" != *"strap.sh"* ]]
}

@test "--set overrides are applied and validated" {
    mock_repo_from_catalog arch
    setup_on arch --dry-run --profile minimal -y --set SHELL_STARSHIP_PRESET=pastel
    [ "$status" -ne 0 ]; [[ "$output" == *SHELL_STARSHIP_PRESET* ]]
}

@test "real run (mocked pacman): installs, is idempotent on re-run, and rolls back" {
    mock_repo_from_catalog arch
    local args=(--modules packages -y --set PKG_GROUPS= --set PKG_USE_CUSTOM=no --set PKG_EXTRA=btop,fastfetch)
    setup_on arch "${args[@]}"
    [ "$status" -eq 0 ] || { echo "$output" | tail -20; return 1; }
    grep -qx btop "$ARCON_MOCK_INSTALLED"; grep -qx fastfetch "$ARCON_MOCK_INSTALLED"

    : > "$ARCON_MOCK_LOG"
    setup_on arch "${args[@]}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 already installed, 0 to install"* ]]
    [ -z "$(mutating_calls)" ]

    # no run id: the latest run WITH changes is chosen (the no-op re-run is skipped)
    setup_on arch --rollback --rollback-packages -y
    [ "$status" -eq 0 ] || { echo "$output" | tail; return 1; }
    ! grep -qx btop "$ARCON_MOCK_INSTALLED"
    ! grep -qx fastfetch "$ARCON_MOCK_INSTALLED"
}

@test "failure is reported as failure, run is resumable, --resume finishes it" {
    mock_repo_from_catalog arch
    export ARCON_MOCK_FAIL="btop"
    setup_on arch --modules packages -y --set PKG_GROUPS= --set PKG_USE_CUSTOM=no --set PKG_EXTRA=btop
    [ "$status" -ne 0 ]
    [[ "$output" == *FAILED* ]]
    [[ "$output" != *"Installation complete"* ]]
    [ -e "$XDG_STATE_HOME/arcon/current" ]

    unset ARCON_MOCK_FAIL
    setup_on arch --resume -y
    [ "$status" -eq 0 ]
    grep -qx btop "$ARCON_MOCK_INSTALLED"
    [ ! -e "$XDG_STATE_HOME/arcon/current" ]
}

@test "--list-runs and --show-config are read-only" {
    mock_repo_from_catalog arch
    setup_on arch --show-config
    [ "$status" -eq 0 ]; [[ "$output" == *"(defaults:"* ]]
    setup_on arch --list-runs
    [ "$status" -eq 0 ]
    [ -z "$(mutating_calls)" ]
}
