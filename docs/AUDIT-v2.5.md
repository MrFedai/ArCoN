# ArCoN v2.5 Audit Report

Audited revision: `771fb48` (tag `v2.5.0`, 2026-03-02). The v2.5 files are kept unchanged in
[`legacy/v2.5/`](../legacy/v2.5/) and in git history. Line numbers below refer to
`legacy/v2.5/setup.sh` (1885 lines).

Method: full read of `setup.sh`, `README.md`, `pacs.txt` and `configs/`; `bash -n`;
ShellCheck 0.10.0; verification of every external URL, key fingerprint, package name and
theme name against its upstream source (September 2026). Nothing in this report is based
on the README alone; where the README and the code disagree, the code is the reference.

## 1. Repository structure

| Path | Content |
|---|---|
| `setup.sh` | the entire program: 1885 lines of top-level Bash, 1 function (`ask_step`) plus 3 helpers defined inside `case` branches |
| `pacs.txt` | user package list (1 entry: `cmake`) |
| `configs/gno.conf` | dconf dump for GNOME (theme, keybindings, extensions) with `USER_PLACEHOLDER` |
| `configs/hypr/{hyprland,hypridle,hyprlock}.conf` | default Hyprland configuration |
| `configs/terminator/config` | Terminator profile |
| `configs/scrn/*.png` | README screenshots (10) |
| `wallp/*.jpg` | 11 wallpapers |
| `README.md`, `LICENSE` | documentation, MIT licence |

There are no tests, no CI, no modules and no configuration format. 13 commits, all via the
GitHub web UI.

## 2. Feature inventory (v2.5)

Every feature the code actually implements, in execution order. "README" marks features the
README advertises; the "Works?" column is the audit result.

| ID | Sector / step | Feature | Lines | Works? |
|---|---|---|---|---|
| F01 | start | stale pacman lock removal (`db.lck` when no pacman runs) | 19-29 | yes, silently, also on Debian (harmless no-op) |
| F02 | pre-flight | internet check | 33-39 | **no** — check commented out, "Internet connection: OK" always printed |
| F03 | pre-flight | disk space ≥ 10 GB | 41-49 | yes |
| F04 | pre-flight | sudo check | 51-57 | yes |
| F05 | pre-flight | Live-USB detection | 61-74 | **no** — commented out; followed by a stray `END` command (line 76, "command not found") |
| F06 | detect | OS detection via `. /etc/os-release` | 77-84 | yes (arch/debian/ubuntu only; sources the file) |
| F07 | detect | package-manager selection (pacman+yay / apt) | 86-96 | yes |
| F08 | data | package groups essentials/media/cyber/remote/power (78 names) | 100-137 | Arch names only |
| F09 | menu | main menu: install / Smart Factory Reset / exit | 140-305 | yes |
| F10 | reset | backup of config dirs, protected-package whitelist, uninstall, orphan cleanup, GNOME/shell reset, typed `CLEAN` confirmation | 160-295 | partially (see S-08, D-07) |
| F11 | resume | "Resume from last checkpoint" | 307-325 | **no** — `~/.arcon_progress.log` is read but never written; `RESUME_ENABLED` is never used |
| F12 | sector 1 | GPG keyring reset, keyring refresh | 331-368 | yes, destructive on every run (S-04) |
| F13 | sector 1 | mirror benchmark with reflector (live, colourised) | 384-458 | yes, no backup of the mirrorlist |
| F14 | sector 1 | download speed test (Cloudflare) | 460-478 | yes |
| F15 | sector 1 | yay-bin build | 490-497 | yes (clones and builds inside the current/repo directory) |
| F16 | sector 1 | dependency install + system upgrade | 365-382 | `pacman -Sy archlinux-keyring`, then `-S` of other packages, then `-Su` — partial-upgrade window (D-03) |
| F17 | sector 2A | GNOME settings from `gno.conf` (theme, keybindings) | 509-556 | partially — wallpaper `wallp/default.jpg` does not exist; AUR theme |
| F18 | sector 2A | GNOME debloat | 557-575 | yes (regex match can hit unrelated packages) |
| F19 | sector 2B | Gaming Mode: multilib, Steam, GameMode, GPU drivers | 582-658 | partially — GPU chosen manually (README says auto-detect), NVIDIA without kernel module, config written to a path GameMode never reads, only offered after GNOME step |
| F20 | sector 3 | package engine: group selection, `pacs.txt`, size preview, progress bar, official vs AUR split | 665-958 | yes on Arch; Arch names used on Debian/Ubuntu |
| F21 | sector 4 | BlackArch: enable repo (strap.sh), full / core groups, provider-lock fix, removal | 961-1068 | partially — wrong key fingerprint (S-02), no checksum (S-01) |
| F22 | sector 6 | Hyprland: packages + default config + 4 theme installers (Ax-Shell, Hyprdots, ML4W, JaKooLit) with "edit installer" option | 1073-1200 | partially — 3 of 4 installer URLs dead in 2026-09 (D-10) |
| F23 | sector 7 | restore Terminator config + wallpapers | 1207-1220 | yes (overwrites without backup) |
| F24 | sector 8A | terminal emulator (Terminator/Kitty/Alacritty/GNOME Terminal) + theme | 1225-1330 | **no for themes** — every Kitty theme URL 404 (space in name, wrong repo), Alacritty names wrong case and theme overwrote `alacritty.toml` |
| F25 | sector 8B | shell: Zsh + Oh-My-Zsh + plugins + 4 themes, Fish, Bash + Starship presets, Nerd Font | 1331-1470 | partially — `curl \| sh` installers, Starship preset "pastel" does not exist |
| F26 | sector 9 | security tools + dashboard | 1479-1600 | yes (pacman names on every OS) |
| F27 | sector 9 | optimization steps: TRIM, UFW, Bluetooth, ZRAM, ClamAV/rkhunter DB, Firejail, Arch cleanup | 1490-1598 | partially — UFW configured without being installed; ZRAM without zram-generator; Firejail branch name mismatch → `firecfg` never ran |
| F28 | sector 9 | security scans (Lynis, rkhunter, ClamAV, arch-audit) | 1600-1656 | yes (`/home/$USER` hard-coded) |
| F29 | sector 9 | hardening: sysctl, SSH root login, SSH password auth | 1658-1745 | partially — `sed` on `sshd_config`, no `sshd -t`, drop-ins can override |
| F30 | sector 9 | Hardened Mode (OpenSnitch + USBGuard) | 1747-1785 | partially — `opensnitch-ui` does not exist; reachable only inside "Apply All Hardening Fixes" |
| F31 | sector 10 | final summary | 1786-1843 | **misleading** — "Packages: Processed", "Shell & Term: Configured" printed unconditionally |
| F32 | end | cleanup: orphans, `pacman -Scc`, temp files | 1851-1876 | yes, Arch commands |
| F33 | end | reboot prompt | 1879-1885 | yes |

## 3. Architecture analysis

- **Monolith.** One top-level script; state is global variables (`IS_ARCH`, `gnome_done`, `gpu`,
  `install_term` ...). Three helpers are *defined inside `case` branches* (`apply_starship_preset`,
  `update_ui` ×2), so they only exist if that branch ran.
- **Platform logic inline.** `[ "$IS_ARCH" = true ] && pacman ... || apt-get ...` is repeated
  across the script (ShellCheck SC2015 — if pacman fails, apt-get is attempted on Arch).
- **Implicit coupling.** Gaming Mode depends on the GNOME step (line 582 is inside the GNOME
  `if`); Hardened Mode depends on "Apply All Hardening Fixes".
- **Working directory as state.** Hyprland theme installers `cd` into clone directories and
  never return; later relative paths (`configs/`, `wallp/`) then break.
- **No separation of plan and execution.** Every prompt immediately executes; a dry run is
  impossible.
- **No error model.** Output of most installs is discarded (`&>/dev/null`), exit codes are
  ignored, success messages are printed unconditionally.

## 4. Dependency analysis

| Dependency | Used for | Source in v2.5 | Issue |
|---|---|---|---|
| pacman, makepkg, git | everything on Arch | system | — |
| yay (yay-bin) | AUR | built from AUR | built in the repo directory; used for official Hyprland packages too |
| reflector | mirrors | pacman | mirrorlist overwritten without backup |
| curl | installers, themes | system | `curl \| sh` (S-03); no HTTP error handling (`-s` without `-f`) |
| dconf | GNOME | system | no backup before `load` / `reset -f /` |
| Oh-My-Zsh installer | zsh | `sh -c "$(curl …install.sh)"` | remote code, unpinned |
| Starship installer | bash/zsh prompt | `curl … \| sh` | remote code, no checksum |
| strap.sh | BlackArch | curl to CWD, run as root | no checksum, wrong key |
| dexpota/kitty-themes | kitty themes | raw URLs | wrong names → 404 page saved as config |
| alacritty-theme | alacritty themes | raw URLs | wrong case → 404 saved **over** `alacritty.toml` |
| Axenide/Ax-Shell, prasanthrangan/hyprdots, ML4W, JaKooLit | Hyprland themes | curl/git | archived or moved (verified 2026-09) |

## 5. Platform dependencies

Declared: Arch, Debian, Ubuntu. Actual: Arch only for most sectors.

- Package names are Arch names everywhere (`wireshark-qt`, `libreoffice-fresh`, `qemu-desktop`,
  `*-bin` AUR names); on Debian/Ubuntu `apt-get install` of those names fails.
- Gaming, BlackArch, Hyprland: guarded by `IS_ARCH`.
- Summary uses `pacman -Qi` on every OS → always "Skipped" on Debian.
- Cleanup runs `pacman -Scc` unconditionally.
- No Fedora, openSUSE, macOS or Windows code paths (the README lists them as "Coming in v3.0").

## 6. Security risks

| ID | Severity | Finding | Lines | v3.0 resolution |
|---|---|---|---|---|
| S-01 | high | `strap.sh` downloaded into the current directory and executed as root **without checksum**, although blackarch.org publishes a SHA1 | 985-988 | checksum compared with the value on blackarch.org/downloads.html + optional pinned SHA256; temp dir; confirmation |
| S-02 | high | BlackArch key signed with **wrong fingerprint** `4345771566D76030457303332944B067D796237B`; the real key is `4345771566D76038C7FEB43863EC0ADBEA87E4E3` (blackarch-keyring 20251011). The `lsign` fails (hidden by `2>/dev/null \|\| true` at line 376) | 376, 990 | correct fingerprint, verified with `pacman-key --finger` |
| S-03 | high | remote code piped to a shell: Oh-My-Zsh `sh -c "$(curl …)"`, Starship `curl \| sh` | 1351, 1401, 1435 | git clone of pinned upstream / distro package / release tarball verified against the upstream `.sha256` |
| S-04 | high | `/etc/pacman.d/gnupg` and `/var/lib/pacman/sync/*` deleted **on every run** | 354-360 | opt-in `BASE_GPG_RESET=yes`, safe refresh by default |
| S-05 | medium | `pacman -S … --overwrite '*'` for BlackArch can silently replace files owned by other packages | 1033-1035 | off by default (`BLACKARCH_OVERWRITE`) |
| S-06 | medium | `sshd_config` edited with `sed` without syntax validation; a drop-in in `sshd_config.d` (Ubuntu default) can override it; SSH not allowed through UFW before `ufw enable` (remote lock-out) | 1692-1712, 1542 | drop-in `/etc/ssh/sshd_config.d/10-arcon.conf` + `sshd -t`; SSH allowed when sshd is running |
| S-07 | medium | `/etc/os-release` sourced (executed) with `.` | 78 | parsed as data |
| S-08 | medium | Smart Factory Reset: `dconf reset -f /` and `rm -rf ~/.oh-my-zsh ~/.zshrc ~/.config/starship.toml` with no backup | 279-284 | `dconf dump` + journaled backups, restorable with `--rollback` |
| S-09 | low | predictable temp file `/tmp/gno_final.conf` | 542-550 | `mktemp` under a private run dir |
| S-10 | low | `usbguard generate-policy` + enable with no warning (can block USB keyboards) | 1768-1777 | typed confirmation |
| S-11 | info | unquoted expansions (ShellCheck SC2086 ×14, SC2046 ×6) incl. `$(pacman -Qtdq)` | 270, 1576, 1856 | quoted arrays |

No hard-coded secrets were found. `sudo` is used per command (no `sudo -s`), which is fine.

## 7. Performance issues

- One `pacman -S` / `apt-get install` **per package** in the progress-bar loop (dependency
  resolution repeated N times). v3.0 installs in batches and keeps the per-package bar only
  as display.
- `pacman -Scc` wipes the entire cache (next reinstall downloads everything again).
- BlackArch "provider-lock fix" installs `jdk17-openjdk jdk11-openjdk rust opencl-mesa`
  unconditionally (≈1 GB).
- `pacman -Syy`-style database refreshes more than once per run.
- No performance claims are measured; the README "15-30 minutes" is not substantiated.

## 8. Technical debt

| ID | Finding | Lines |
|---|---|---|
| D-01 | internet check commented out but reported OK | 33-39 |
| D-02 | stray `END` command after a commented block | 76 |
| D-03 | partial upgrades (`pacman -Sy` then `-S` before `-Su`; `-Sy` after enabling multilib) | 365-382, 588 |
| D-04 | `CYAN`, `BOLD`, `DIM` used but never defined (only GREEN/BLUE/YELLOW/RED/NC exist, line 6) | 140+ |
| D-05 | resume log never written (feature does not work) | 307-325 |
| D-06 | helpers defined inside `case`/`if` branches (`update_ui`, `apply_starship_preset`) | 623, 1228 |
| D-07 | summary prints success without checking | 1834, 1838 |
| D-08 | GameMode config written to `~/.config/gamemode/gamemode.ini`; GameMode reads `$XDG_CONFIG_HOME/gamemode.ini` | 646 |
| D-09 | Firejail step label "Firejail (Sandbox All)" never matches branch "Firejail (Sandbox Integration)" → `firecfg` never runs | 1499, 1569 |
| D-10 | dead upstreams: Ax-Shell archived, Hyprdots → HyDE-Project/HyDE, ML4W `installer.sh` removed, JaKooLit Hyprland-Dots → Arch-Hyprland (now LinuxBeginnings) | 1112-1180 |
| D-11 | theme URLs 404 (kitty, alacritty); Starship preset `pastel` invalid (`pastel-powerline`) | 1286, 1307, 1234 |
| D-12 | `opensnitch-ui` package does not exist (UI ships in `opensnitch`) | 1754 |
| D-13 | `wallp/default.jpg` referenced by `gno.conf` does not exist | gno.conf |
| D-14 | `/home/$USER` hard-coded | 1622-1625 |
| D-15 | ShellCheck: 49 findings (21 warnings, 28 notes) | — |

## 9. Existing test coverage

None. No test files, no CI, no linting configuration. `bash -n` passes.

## 10. Migration risks

| Risk | Mitigation in v3.0 |
|---|---|
| Users relying on the interactive flow | interactive wizard kept as default; same questions, same order |
| Changed defaults (GPG reset, `--overwrite`, `-Scc`) surprise v2.5 users | documented in CHANGELOG and MIGRATION; each old behaviour available as opt-in key |
| Cross-distro package names wrong | per-distro catalog verified against official indexes; unavailable names reported, never silently dropped |
| Dead theme upstreams | current upstreams, pinned commits, marked deprecated where archived |
| New code breaks working Arch path | regression tests on v2.5 feature ids; Arch container job in CI; v2.5 kept in `legacy/` |
| Windows/macOS claims without testing | test levels labelled; nothing marked supported without evidence (docs/PLATFORMS.md) |

## 11. Proposed v3.0 architecture

See [ARCHITECTURE.md](ARCHITECTURE.md). Summary:

```
setup.sh ─► core/        platform-independent: cli, config (non-executing), log, ui,
                          exec (single mutation gate + dry-run plan), fs (atomic, journaled),
                          rollback, state (tasks, resume)
            platform/    detect (os-release parser), hardware (Linux/macOS/mock backends),
                          pkg/ facade + providers pacman(+yay/paru) apt dnf zypper brew flatpak
            modules/     one file per v2.5 sector: plan() adds tasks, tasks call the facades
            data/        packages.catalog (per-distro names), optimizations.catalog
            profiles/    minimal balanced performance gaming developer security full custom
setup.ps1 ─► windows/ArCoN (PowerShell 7 module): same concepts, PowerShell classes for
             the package manager, CIM hardware detection, registry/service/power journal
```

Flow for every run: DETECT → VALIDATE → PLAN → SHOW → CONFIRM IF RISKY → APPLY → VERIFY.

## 12. Migration plan (phases executed)

| Phase | Content | Status |
|---|---|---|
| 1 | audit (this document), tag `v2.5.0`, copy to `legacy/v2.5/` | done |
| 2 | core: log, ui, config, exec, fs, rollback, state | done |
| 3 | platform detection + hardware detection with fixtures | done |
| 4 | package facade + providers, catalog, catalog verifier | done |
| 5 | modules ported sector by sector with bug fixes | done |
| 6 | CLI: dry-run, profile, resume, rollback, non-interactive | done |
| 7 | optimization catalog with risk/rollback/verification | done |
| 8 | Windows PowerShell module | done (not natively tested) |
| 9 | macOS paths (brew, hardware) | done (CI only) |
| 10 | bats + Pester test suites, mocks, fixtures | done |
| 11 | CI (lint, unit, distro containers, Windows, macOS) | done |
| 12 | security review of v3 code | done ([SECURITY.md](SECURITY.md)) |
| 13 | documentation | done |
| 14 | VM / native validation | partial — see [FINAL-AUDIT-v3.0.md](FINAL-AUDIT-v3.0.md) |
| 15 | release | pending user decision (branch `v3.0`, `main` untouched) |

## 13. Feature parity matrix

See [FEATURE-PARITY.md](FEATURE-PARITY.md) — every F-ID above mapped to its v3.0 implementation,
status and test evidence.
