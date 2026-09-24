# ArCoN v2.5 → v3.0 Feature Parity Matrix

Source of feature IDs: `docs/AUDIT.md` §2. Update this file in every phase.

**Action:** keep (same intent/behaviour) · replace (same intent, different mechanism) · fix (v2.5 behaviour is a bug/unsafe; not ported as-is without owner approval) · N-A (with reason) · new
**Reversible:** yes · partial · no · ONE-WAY (third-party code, D16)
**Status values:** NOT MIGRATED · MIGRATED (+ test label: UNIT / INTEGRATION / VM / NATIVE TESTED, or NOT TESTED)

| ID | Feature | Target module | Action | Reversible | Arch | Debian | Ubuntu | Fedora | Windows | macOS |
|---|---|---|---|---|---|---|---|---|---|---|
| F01 | stale pacman lock removal | core/preflight.py | fix (ask, never silent) | n/a | NOT MIGRATED | N-A | N-A | N-A | stub | stub |
| F02 | internet check | core/preflight.py | fix | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F03 | disk ≥ 10 GB | core/preflight.py | keep | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F04 | sudo check | core/preflight.py + core/runner.py | keep | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F05 | Live-USB detection | core/preflight.py | fix (was commented out) | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F06 | OS detection | platform/detect.py | fix (parse, don't source) | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F07 | package-manager selection | package/registry.py | replace | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F08 | package groups (78) | data/packages.toml | replace (per-distro names) | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F09 | main menu | cli.py / core/wizard.py | replace (D14) | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F10 | Smart Factory Reset | recovery/reset.py | fix (C-5 open) | partial | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F11 | resume | recovery/journal.py | fix (never worked) | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F12 | GPG / keyring reset | package/pacman.py | fix (opt-in reset) | no | NOT MIGRATED | N-A | N-A | N-A | N-A | N-A |
| F13 | reflector mirror benchmark | package/pacman.py | keep + backup | yes | NOT MIGRATED | N-A | N-A | N-A | N-A | N-A |
| F14 | speed test | core/preflight.py | keep | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F15 | yay-bin build | package/aur.py | keep (temp dir) | yes | NOT MIGRATED | N-A | N-A | N-A | N-A | N-A |
| F16 | deps + system upgrade | package/* | fix (no partial upgrade) | no | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F17 | GNOME settings (gno.conf) | desktop/gnome.py + dotfiles/deploy.py | keep (D8 byte-identical; C-2) | yes (dconf dump) | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | N-A | N-A |
| F18 | GNOME debloat | desktop/gnome.py | keep | partial | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | N-A | N-A |
| F19 | Gaming Mode + GPU drivers | gaming/* + hardware/gpu.py | fix (decouple from GNOME, detect GPU) | partial | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F20 | package engine (preview, pacs.txt, AUR split) | package/* | keep (batch install) | partial | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F21 | BlackArch manager | security/blackarch.py | fix (checksum, key, no --overwrite default) | partial | NOT MIGRATED | N-A | N-A | N-A | N-A | N-A |
| F22 | Hyprland + theme installers | desktop/hyprland.py + desktop/third_party.py | keep optional (D12), installers ONE-WAY (D16) | ONE-WAY | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | N-A | N-A |
| F23 | Terminator config + wallpapers | dotfiles/deploy.py | keep + backup/diff (D10) | yes | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | N-A | stub |
| F24 | terminal emulator + theme | terminal/* | fix (URLs, no overwrite) | yes | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F25 | shell + prompt themes | terminal/shell.py | fix (no curl\|sh) | partial | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F26 | security tools + dashboard | security/tools.py | keep | partial | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F27 | optimization steps | optimization/* + data/optimizations.toml | fix (install deps, labels) | yes | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F28 | security scans | security/scan.py | keep (scope C-6) | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F29 | hardening sysctl + SSH | security/hardening.py | fix (drop-in + sshd -t) | yes | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F30 | Hardened Mode (OpenSnitch, USBGuard) | security/hardened_mode.py | fix (decouple from F29) | yes | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F31 | final summary | core/report.py | fix (from journal) | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F32 | cleanup (orphans, cache) | optimization/cleanup.py | fix (no -Scc default) | no | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| F33 | reboot prompt | core/reboot.py | keep | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| N1 | monitor mode detection + layout (D13) | display/* | new | yes | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| N2 | dotfile capture / diff (D10) | dotfiles/capture.py, dotfiles/diff.py | new | yes | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| N3 | wizard → summary → single confirm, saved answers (D14) | core/wizard.py, core/profile.py | new | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| N4 | dry-run for every action | core/runner.py | new | n/a | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
| N5 | rollback (snapshot / file backup) | recovery/* | new (D6) | — | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | NOT MIGRATED | stub | stub |
