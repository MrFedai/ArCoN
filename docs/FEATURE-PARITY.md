# v2.5 → v3.0 Feature Parity Matrix

Feature ids (F01…F33) are defined in [AUDIT-v2.5.md](AUDIT-v2.5.md#2-feature-inventory-v25).

Status values:

- **KEPT** — same behaviour, same entry point (interactive wizard) plus a config key.
- **IMPROVED** — same intent, behaviour corrected or extended (reason given).
- **FIXED** — the v2.5 feature did not work; it works in v3.0.
- **N/A (platform)** — the feature cannot exist on that platform; the equivalent (if any) is named.

Test levels (see [TESTING.md](TESTING.md)): `UNIT`, `INTEGRATION` (mocked package managers),
`CONTAINER` (CI, real distro repositories, dry-run), `VM` (real changes inside a VM),
`NATIVE` (real hardware). `NOT TESTED` means exactly that.

## Linux / macOS (`setup.sh`)

| ID | v2.5 feature | v3.0 implementation | Status | Evidence |
|---|---|---|---|---|
| F01 | stale pacman lock removal | `base` preflight, `PACMAN_STALE_LOCK=ask\|remove\|abort` (default ask; non-interactive → abort) | IMPROVED — no silent removal | NOT TESTED (Arch only) |
| F02 | internet check | `net_online` against `NET_CHECK_URLS`, `REQUIRE_NETWORK` | FIXED — was commented out but printed OK | VM (Ubuntu 26.04) |
| F03 | disk ≥ 10 GB | `MIN_DISK_GB=10`; below the limit the run stops (dry-run: reported only) | KEPT | VM (PASS path only; FAIL path NOT TESTED) |
| F04 | sudo check | preflight; `sudo -v` once + keep-alive | IMPROVED — keep-alive for long installs | VM, INTEGRATION |
| F05 | Live-USB detection | `HW_IS_LIVE` (overlay/tmpfs/squashfs root, `/run/archiso`, `/run/live`) + confirmation | FIXED — was commented out | UNIT (fixtures) |
| F06 | OS detection | `platform/detect.sh`, os-release **parsed** not sourced, derivatives mapped | IMPROVED (+Fedora, openSUSE, macOS; support tier) | UNIT (13 fixtures) |
| F07 | package manager selection | provider facade: pacman(+yay/paru), apt, dnf, zypper, brew, flatpak | IMPROVED | UNIT, INTEGRATION, CONTAINER (see CI) |
| F08 | package groups | `data/packages.catalog`, per-distro names, same 5 groups + all 78 v2.5 packages | IMPROVED — correct names per distro | UNIT (regression test covers every v2.5 name) |
| F09 | main menu install/reset/exit | wizard start menu kept; `--reset`, `--help` for scripted use | KEPT | INTEGRATION |
| F10 | Smart Factory Reset | `modules/reset.sh`, `--reset`: protected list (v2.5 whitelist kept), verified backups, `dconf dump`, typed `CLEAN`, `--reset --dry-run` | IMPROVED — backups verified and restorable | UNIT (fs backup/rollback); reset itself NOT TESTED on a real desktop |
| F11 | resume | `--resume`: task state `tasks.tsv` written atomically, interrupted tasks re-run | FIXED — never worked in v2.5 | UNIT, INTEGRATION, VM |
| F12 | GPG keyring reset | refresh by default; full reset only with `BASE_GPG_RESET=yes` | IMPROVED (S-04) | NOT TESTED (Arch only) |
| F13 | reflector mirror benchmark | `BASE_MIRRORS`, mirrorlist backed up and journaled | IMPROVED | CONTAINER dry-run only |
| F14 | speed test | `BASE_SPEEDTEST` | KEPT | VM |
| F15 | yay-bin build | `BASE_AUR_HELPER_INSTALL`, `AUR_HELPER=yay\|paru`, temp dir | IMPROVED | NOT TESTED (Arch only) |
| F16 | system upgrade | `BASE_UPGRADE`, full `-Syu` / `apt-get upgrade` / `dnf upgrade` / `zypper dup\|up` / `brew upgrade` | IMPROVED — no partial upgrades | VM (apt), others CONTAINER dry-run |
| F17 | GNOME settings (gno.conf) | `modules/gnome.sh`, `GNOME_APPLY`, `GNOME_WALLPAPER`, dconf backup + rollback, verification | FIXED (missing wallpaper, AUR theme) | NOT TESTED (needs GNOME session). Debian/Ubuntu: `adw-gtk-theme` not packaged → theme key set, theme not installed (warned) |
| F18 | GNOME debloat | `GNOME_DEBLOAT`, exact installed check, list shown | IMPROVED | NOT TESTED |
| F19 | Gaming Mode | `modules/gaming.sh`, independent of GNOME, GPU auto-detected (`GAMING_GPU=auto`), NVIDIA kernel module, lib32 Vulkan, GameMode config at the path GameMode reads, `gamemode` group | FIXED + IMPROVED | INTEGRATION (NVIDIA/AMD plans), UNIT (GPU detection); real drivers NOT TESTED |
| F20 | package engine (preview, progress bar, pacs.txt, AUR split) | `modules/packages.sh`: preview, progress bar (interactive), batch install, `pacs.txt` with comments, AUR only when not official | IMPROVED — failures reported, idempotent | INTEGRATION, VM (real install/rollback of `tree`) |
| F21 | BlackArch manager | `BLACKARCH=enable\|core\|full\|remove`, checksum, correct key, `--overwrite` opt-in, menu kept | FIXED (S-01, S-02) | UNIT (config), dry-run INTEGRATION; real repo NOT TESTED. **Arch only**; other OS: N/A, equivalent = `PKG_GROUPS=cyber` |
| F22 | Hyprland + 4 themes + edit installer | `HYPR_THEME=default\|ax-shell\|hyde\|ml4w\|jakoolit`, `HYPR_EDIT_INSTALLER`, current upstreams, commit shown, confirmation | FIXED (dead URLs) — Ax-Shell kept but marked deprecated (upstream archived) | CONTAINER dry-run only; themes NOT TESTED |
| F23 | Terminator config + wallpapers | `modules/dotfiles.sh`, backup + skip unchanged | IMPROVED | UNIT (fs), VM |
| F24 | terminal emulator + theme | `TERM_EMULATOR=terminator\|kitty\|alacritty\|gnome-terminal`, `TERM_THEME`, pinned theme repos, alacritty theme imported not overwritten | FIXED | NOT TESTED beyond dry-run |
| F25 | shell (zsh/fish/bash, OMZ, plugins, 4 zsh themes, Starship presets, Nerd Font) | `modules/shell.sh`; no `curl \| sh`; valid Starship presets; `/etc/shells` check before `chsh` | FIXED + IMPROVED (S-03) | UNIT (config validation of presets); real run NOT TESTED |
| F26 | security tools + dashboard | `SEC_TOOLS`, catalog per distro, dashboard kept | IMPROVED | dry-run INTEGRATION |
| F27 | optimization steps | `data/optimizations.catalog` + `modules/optimize.sh`: TRIM only on SSD/NVMe, Bluetooth only with adapter, zram with zram-generator, cache trim, firewall installed before configuring, `firecfg` fixed (`SEC_FIREJAIL_FIRECFG`) | FIXED + IMPROVED | UNIT (catalog ↔ implementation), dry-run INTEGRATION |
| F28 | security scans | `SEC_SCAN`: arch-audit, Lynis, ClamAV (home of the real user), rkhunter; report file | IMPROVED | NOT TESTED (long-running) |
| F29 | hardening (sysctl, SSH) | `SEC_HARDEN_SYSCTL`, `SEC_HARDEN_SSH`, `SEC_SSH_DISABLE_PASSWORD`; sshd drop-in + `sshd -t` | IMPROVED (S-06) | dry-run INTEGRATION; real sshd NOT TESTED |
| F30 | Hardened Mode (OpenSnitch + USBGuard) | `SEC_HARDENED_MODE`, independent of hardening; `opensnitch` only; USBGuard with typed confirmation | FIXED | NOT TESTED |
| F31 | final summary | summary built from task state (done/failed/skipped/not selected) | FIXED (no false "Configured") | INTEGRATION (failure run) |
| F32 | cleanup | `CLEANUP` + catalog cleanup items per platform; `paccache -rk2` instead of `-Scc` | IMPROVED | dry-run INTEGRATION |
| F33 | reboot prompt | `REBOOT`, only suggested when a reboot-requiring task ran | IMPROVED | UNIT |

New in v3.0 (not in v2.5): `--dry-run`, `--profile`, `--rollback [RUN_ID]`, `--rollback-packages`,
`--list-runs`, `--show-config`, `--set KEY=VALUE`, `--config FILE`, non-interactive mode,
structured log files, hardware banner, macOS support (Homebrew), Fedora and openSUSE support.

## Windows (`setup.ps1`, PowerShell 7)

| ID | v2.5 feature | Windows status | Windows implementation / equivalent |
|---|---|---|---|
| F01, F12, F13, F15, F16 | pacman lock, keyring, mirrors, AUR, system upgrade | N/A (platform) | winget has no equivalent state; `winget upgrade` is available as a package action |
| F02-F04 | preflight | IMPROVED | network, disk, **administrator** (`Test-ArConAdmin`), PowerShell 7 check |
| F05 | Live-USB | N/A (platform) | Windows To Go is not detected |
| F06/F07 | OS / package manager | IMPROVED | Windows 11 = tier "tested-by-CI", Windows 10 = "experimental"; `ArConWingetPackageManager` class |
| F08/F20 | package groups | IMPROVED | same catalog, `winget` column (41 ids) |
| F09 | menu | KEPT | wizard |
| F10 | factory reset | N/A in v3.0 | not ported: removing applications on Windows needs per-installer handling; documented, not silently dropped |
| F11 | resume | FIXED | `-Resume`, `state.json` |
| F17/F18, F22-F25 | GNOME, Hyprland, terminal/shell theming | N/A (platform) | Windows Terminal / Starship are available as catalog packages |
| F19 | gaming | IMPROVED | Game Mode registry values (journaled), GPU driver/HAGS report, High performance power plan (not on battery) |
| F21 | BlackArch | N/A (platform) | `PKG_GROUPS=cyber` (winget ids where they exist) |
| F26-F30 | security | IMPROVED | Defender, Firewall, BitLocker, SmartScreen, UAC — report by default, enforce opt-in |
| F27/F32 | optimization / cleanup | IMPROVED | temp cleanup (>7 days), startup report, TRIM report, power plan, winget cache |
| F31 | summary | FIXED | from task state |
| F33 | reboot | KEPT | prompt only |

Windows evidence: Pester (mocked CIM/registry/winget) on Linux pwsh and in the CI Windows job;
`setup.ps1 -DryRun` on the GitHub `windows-latest` runner. **No real Windows 10/11 machine was
used**; see [FINAL-AUDIT-v3.0.md](FINAL-AUDIT-v3.0.md).
