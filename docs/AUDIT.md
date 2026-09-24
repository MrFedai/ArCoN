# ArCoN v2.5 — Phase 1 Audit

| | |
|---|---|
| Audited revision | `771fb48` = `main` = tag `v2.5.0` (tag already existed; `v2.5-final` NOT created, see Deviations) |
| Reference branch | `origin/v3.0` @ `208473f` (Bash + PowerShell rewrite, 2026-09-23) — read, not modified |
| Working branch | `v3-dev` (from `main`) |
| Date | 2026-09-24 |
| Method | Full read of `setup.sh` (1885 lines), `README.md`, `pacs.txt`, `configs/*`; `bash -n`; ShellCheck 0.9.0; HTTP status of every theme/installer URL; `bats` unit suite of `v3.0` |
| Changes to the system | none |

Feature IDs **F01–F33** follow `docs/AUDIT-v2.5.md` on the `v3.0` branch so both documents can be cross-referenced.

---

## 0. Verification of prior audits

### 0.1 `docs/PRIOR_AUDIT.md` (17 findings)

| # | Finding | Result | Evidence |
|---|---|---|---|
| 1 | stray `END` | CONFIRMED | `setup.sh:75` |
| 2 | undefined colour vars | CONFIRMED | only `GREEN BLUE YELLOW RED NC` defined (`:6`); `CYAN BOLD DIM GRAY MAGENTA` used from `:142` |
| 3 | internet check prints OK | CONFIRMED | check commented `:33-38`, `echo "Internet connection: OK"` `:39` |
| 4 | resume never written | CONFIRMED | `RESUME_LOG` only read/deleted `:308-325`; no write anywhere; `RESUME_ENABLED` never read |
| 5 | Firejail label mismatch | CONFIRMED | `:1499` vs `:1569` |
| 6 | ufw / zram-generator not installed | CONFIRMED | `sec_tools` `:1483` has neither; both steps guarded by presence checks |
| 7 | Debian path nominal | CONFIRMED | `pacman` unconditional at `:1485-1489`, `:1795-1830`, `:1856-1866`; Arch names in all groups `:102-135` |
| 8 | theme downloads overwrite config | CONFIRMED | see §7; Alacritty 5/5 URLs 404, Kitty 4/5 404; `curl -sS` without `-f` `:1286`, `:1308` |
| 9 | factory reset deletes by guess | CONFIRMED | `*) target_config="$pkg"` `:223`, no protected-list check in config loop `:202-235`; `dconf reset -f /` `:281` |
| 10 | gnupg + sync DB wiped every run | CONFIRMED | `:354-355` |
| 11 | gaming requires GNOME | CONFIRMED | `if [ "$gnome_done" = true ]` `:580` |
| 12 | `default.jpg` missing | CONFIRMED | `gno.conf:5-6,43`; `wallp/` has 11 files, none `default.jpg` |
| 13 | hard-coded monitors / shutdown bind | CONFIRMED | `hyprland.conf:20-21`, `:241` |
| 14 | `pacman -Scc` | CONFIRMED | `:1866` |
| 15 | unknown name → AUR | CONFIRMED | `:799-823` (`pacman -Si` miss ⇒ `aur_list`) |
| 16 | README over-claims | CONFIRMED | README "GPU auto-detect", "conflict resolution", "Resume"; code: manual `select` `:597`, resume §9 |
| 17 | third-party IP in `wallp/` | PARTIAL | inferred from file names only (`jinx.jpg`, `BladeRun.jpg`, `Khabib.jpg` …); images NOT inspected |

Line numbers in `PRIOR_AUDIT.md` were approximate; the table above is authoritative.

### 0.2 `v3.0` branch `docs/AUDIT-v2.5.md` — spot checks

| Claim | Result | Evidence |
|---|---|---|
| "every Kitty theme URL 404" | PARTIAL | `Dracula.conf` → 200; `Tokyo Night`, `Nord`, `Gruvbox Dark`, `Cyberpunk` → 404 |
| Alacritty names wrong case | CONFIRMED | `Dracula.toml` 404, `dracula.toml` 200; Nord/Gruvbox_Dark/TokyoNight/Omni 404 |
| "3 of 4 Hyprland installer URLs dead" | PARTIAL | at v2.5 paths: ML4W `installer.sh` 404, JaKooLit `install.sh` 404, Ax-Shell `install.sh` 200, hyprdots `Scripts/install.sh` 200. Archive status NOT checked |
| stray `END` at line 76 | REFUTED (off by one) | line 75 |
| BlackArch key fingerprint wrong (S-02) | UNCLEAR | `blackarch.org` unreachable from audit environment (HTTP 000); not verified |
| ShellCheck 49 findings | PARTIAL | ShellCheck 0.9.0 here: 52 (23 warning, 29 note); version difference likely |
| Docs referenced by README/audit | **REFUTED** | `ARCHITECTURE.md`, `SECURITY.md`, `PLATFORMS.md`, `FINAL-AUDIT-v3.0.md`, `TESTING.md`, `CHANGELOG.md`, `MIGRATION.md`, `PACKAGE-CATALOG.md` do not exist on the branch. The "real run in an Ubuntu 26.04 VM" claim has no evidence file |
| unit tests | CONFIRMED | `bats tests/bats/unit_*.bats` → 68/68 ok (UNIT TESTED; integration/container/VM suites not run) |

### 0.3 New findings (not in either prior audit)

| ID | Finding | Evidence |
|---|---|---|
| N-01 | `hyprlock.conf` sources a file that only exists with Ax-Shell | `hyprlock.conf:1` `source = ~/.config/Ax-Shell/config/hypr/colors.conf`; `$primary/$foreground` used `:31,51,66,85` |
| N-02 | `hyprlock.conf` background `~/.current.wall` is never created by ArCoN | `hyprlock.conf:6` |
| N-03 | Hyprland official packages installed through `yay` (`$AUR_MGR`) | `:1094` |
| N-04 | `sudo ./setup.sh` puts every dotfile in `/root` (`$HOME`, `$USER`, `~`) | all `~/.config` writes, e.g. `:1215`, `:1276` |
| N-05 | GNOME clipboard extension installed but never enabled in `gno.conf` (no `enabled-extensions`) | `:522`; `gno.conf` `[org/gnome/shell]` |
| N-06 | `hyprland.conf` references `$web = google-chrome-stable`, `$fileManager = nautilus`, but Hyprland module installs `dolphin` | `hyprland.conf:32,34`; `setup.sh:1078` |

---

## 1. Repository structure

```
setup.sh            1885 lines, the whole program (1 top-level function ask_step + 3 helpers defined inside branches)
pacs.txt            custom package list — 1 entry: cmake
configs/gno.conf    dconf keyfile for GNOME (151 lines)
configs/terminator/config   Terminator profile (ConfigObj, 35 lines)
configs/hypr/{hyprland,hypridle,hyprlock}.conf   Hyprland defaults (319/27/89 lines)
configs/scrn/*.png  10 README screenshots
wallp/*.jpg         11 wallpapers (12 MB)
README.md, LICENSE (MIT)
```
Entry point: `./setup.sh` run as the normal user from the repo root (relative paths `configs/`, `wallp/`, `pacs.txt`). No arguments, no environment variables.

## 2. Feature inventory

| ID | Feature | Lines | Trigger | Depends on | Works today |
|---|---|---|---|---|---|
| F01 | stale pacman lock removal | 19-29 | always | — | yes (silent `rm`) |
| F02 | internet check | 33-39 | always | — | **no** (#3) |
| F03 | disk ≥ 10 GB | 41-49 | always | — | yes |
| F04 | sudo check | 51-57 | always | — | yes |
| F05 | Live-USB detection | 61-74 | — | — | **no** (commented) |
| F06 | OS detection (`. /etc/os-release`) | 77-84 | always | — | arch/debian/ubuntu |
| F07 | package-manager selection | 86-96 | always | F06 | yes |
| F08 | package groups (78 names) | 102-135 | data | — | Arch names only |
| F09 | main menu install / reset / exit | 139-305 | `read -p` | — | yes |
| F10 | Smart Factory Reset | 157-296 | menu 2 | F08 | partially (#9) |
| F11 | resume | 308-325 | if log exists | — | **no** (#4) |
| F12 | GPG / keyring reset | 331-368 | "Update Base System" | — | destructive every run (#10) |
| F13 | reflector mirror benchmark | 396-458 | same | F12 | yes, no mirrorlist backup |
| F14 | Cloudflare speed test | 460-478 | same | — | yes |
| F15 | yay-bin build | 490-497 | same | — | yes (builds in CWD) |
| F16 | deps + system upgrade | 365-387, 484-489 | same | — | partial-upgrade window |
| F17 | GNOME settings from `gno.conf` | 509-555 | "Apply GNOME Settings" | — | partially (#12) |
| F18 | GNOME debloat | 557-575 | "Remove GNOME Bloatware" | F17 | yes |
| F19 | Gaming: multilib, Steam, GameMode, GPU drivers | 580-659 | "Enable Gaming Mode" | **F17** | partially (manual GPU, #11) |
| F20 | package engine (groups, pacs.txt, preview, progress, AUR split) | 665-958 | "Start Package Installation Module" | F08 | Arch only |
| F21 | BlackArch manager | 960-1067 | menu loop (Arch) | — | partially |
| F22 | Hyprland + 4 theme installers | 1073-1201 | "Install Hyprland Environment" | yay | partially (§0.2) |
| F23 | restore Terminator config + wallpapers | 1207-1220 | "Restore Configs" | — | yes, overwrites without backup |
| F24 | terminal emulator + theme | 1225-1322 | "Configure Terminal…" | — | themes mostly broken (#8) |
| F25 | shell: zsh/OMZ/plugins/themes, fish, bash, Starship, Nerd Font | 1324-1473 | same | — | partially (`curl\|sh`) |
| F26 | security tools + dashboard | 1479-1595 | "Apply Security & System Optimizations" | — | Arch only |
| F27 | optimization steps (TRIM, BT, UFW, ZRAM, ClamAV, rkhunter, Firejail, cleanup) | 1492-1580 | same | — | partially (#5, #6) |
| F28 | security scans | 1596-1640 | "Start Security Scans" | F26 | yes |
| F29 | hardening: sysctl, SSH | 1642-1723 | "Apply All Hardening Fixes" | F26 | yes (no `sshd -t`) |
| F30 | Hardened Mode (OpenSnitch + USBGuard) | 1725-1783 | "Activate Hardened Mode" | **F29** | partially |
| F31 | final summary | 1787-1843 | always | — | misleading (unconditional "Configured") |
| F32 | cleanup: orphans, `-Scc`, strap.sh | 1849-1875 | prompt | — | Arch only (#14) |
| F33 | reboot prompt | 1877-1885 | prompt | — | yes |

## 3. Dotfile inventory (D8 / D10)

| File | Native format | Target | Deploy method (v2.5) | Template vars | Machine-specific values | Missing refs | Secrets |
|---|---|---|---|---|---|---|---|
| `configs/gno.conf` | dconf keyfile (GVariant values: `uint32 30`, lists, tuples) | dconf `/` | `sed USER_PLACEHOLDER` → `/tmp/gno_final.conf` → `dconf reset -f /org/gnome/desktop/app-folders/` → `dconf load /` (`:538-545`) | `USER_PLACEHOLDER` ×3 (`:5,6,43`) | `/home/<user>` path; keyboard `us` | `wallp/default.jpg` | no |
| `configs/terminator/config` | ConfigObj | `~/.config/terminator/config` | `cp` (`:1215`, `:1320`), no backup | none | window size `600, 900` | — | no |
| `configs/hypr/hyprland.conf` | Hyprland | `~/.config/hypr/` | `cp -r` only if "Skip Theme" (`:1191-1194`); existing dir moved to `hypr.bak_<ts>` (`:1100-1104`) | none | `monitor=HDMI-A-1,1920x1080@180,0x0,1`, `monitor=eDP-2,2560x1600@165,1920x-260,1` (`:20-21`), `workspace=2, monitor:HDMI-A-2` (`:49`) | `myColors.conf`, Ax-Shell (commented) | no |
| `configs/hypr/hyprlock.conf` | Hyprland | same | same | none | — | Ax-Shell `colors.conf` (N-01), `~/.current.wall` (N-02), `.face.icon` | no |
| `configs/hypr/hypridle.conf` | Hyprland | same | same | none | — | — | no |

**Owner settings that must survive unchanged (D8):**

| File | Key | Value |
|---|---|---|
| gno.conf | `org/gnome/desktop/interface/color-scheme` | `'prefer-dark'` |
| gno.conf | `…/interface/gtk-theme` / `icon-theme` | `'adw-gtk3-dark'` / `'Adwaita'` |
| gno.conf | `…/interface/font-name` / `monospace-font-name` | `'Adwaita Sans 11'` / `'Adwaita Mono 11'` |
| gno.conf | `…/interface/enable-animations`, `enable-hot-corners` | `false`, `false` |
| gno.conf | `…/settings-daemon/plugins/color` night light | enabled, `uint32 3700` |
| gno.conf | wm/media-keys/shell keybindings | `<Alt>w` close, `<Alt>Return` terminator, `<Alt>t` screenshot, `<Super>1-3` workspaces, … (`:48-108`) |
| gno.conf | app folders | 7 folders (`:115-151`) |
| terminator | `background_color`, `background_darkness`, `background_type` | `#241f31`, `0.56`, `transparent` |
| terminator | `font`, `palette`, `foreground_color`, `cursor_shape` | `Adwaita Mono 10`, 16-colour palette, `#ffffff`, `underline` |
| hyprland.conf | `$terminal`, `$web`, `$menu`, keybinds | `terminator`, `google-chrome-stable`, `wofi --show drun` |

Other user-state touched: `~/.zshrc` (`sed` of `ZSH_THEME`, `plugins`), `~/.bashrc` (append), `~/.config/fish/config.fish` (append), `~/.config/starship.toml` (overwrite), `~/.config/kitty/*`, `~/.config/alacritty/alacritty.toml` (overwrite), `~/.config/gamemode/gamemode.ini`, `~/.config/autostart/opensnitch_ui.desktop`, `~/Pictures/wallp/`.

## 4. Display / monitor handling

| Where | What | Hard-coded? |
|---|---|---|
| `hyprland.conf:19-23` | 2 active monitor lines by connector name, fixed mode and position; 3 commented alternatives | yes — connector names, modes, positions |
| `hyprland.conf:49` | workspace 2 bound to `HDMI-A-2` (not in active monitor list) | yes |
| GNOME | nothing — `gno.conf` contains no monitor data; GNOME keeps its own `~/.config/monitors.xml` | n/a |
| `setup.sh` | no monitor detection anywhere | — |
| `v3.0` branch | no monitor detection (grep `monitor\|xrandr\|hyprctl\|edid` in core/modules/platform: 0 hits) | — |

D13 (detect max mode, keep layout) is entirely new work.

## 5. CLI surface (for the migration guide)

No flags, no env vars. Prompts in execution order (★ = mid-install, i.e. after something already changed the system):

| # | Prompt | Lines | Type |
|---|---|---|---|
| 1 | Main menu `Select [1-3]` | 150 | read |
| 2 | Reset: "START CLEANUP PROCESS?", type `CLEAN`, "Uninstall packages", "reset GNOME and Shell" | 163-279 | y/n + typed |
| 3 | "Resume from last checkpoint" | 318 | y/n (dead) |
| 4 | "Update Base System (Mirrors/Keyrings)" | 331 | y/n |
| 5 ★ | "Apply GNOME Settings", "Remove GNOME Bloatware" | 509, 557 | y/n |
| 6 ★ | "Enable Gaming Mode", GPU `select` | 582, 597 | y/n + select |
| 7 ★ | "Start Package Installation Module", 4× "Include these packages", "pacs.txt", "Proceed with installation" | 665-842 | y/n |
| 8 ★ | AUR interactive `yay` (no `--noconfirm`) | 935 | external |
| 9 ★ | BlackArch menu `[1-4]`, install menu, "Press Enter" | 976-1030 | read loop |
| 10 ★ | "Install Hyprland Environment", theme `select`, "edit installer" + `nano` | 1073-1176 | y/n + select + editor |
| 11 ★ | "Restore Configs" | 1207 | y/n |
| 12 ★ | "Configure Terminal…", terminal `select`, theme `select`, shell `select`, zsh theme `read`, starship `select` | 1225-1432 | mixed |
| 13 ★ | "Apply Security & System Optimizations", "Start Security Scans", "Apply All Hardening Fixes", "Disable Password Authentication", "Activate Hardened Mode" | 1479-1747 | y/n |
| 14 ★ | "remove unnecessary leftovers", "Reboot system now" | 1851, 1879 | y/n |

≈ 30–40 prompts depending on path; all but #1–4 occur after the system has already been modified — the main input for D14.

## 6. Distro behavior

| Area | Arch | Debian / Ubuntu | Fedora |
|---|---|---|---|
| detection | `ID=arch` only (no derivatives) | `ubuntu\|debian` | **refused** ("Unsupported OS") |
| base update | keyring reset, reflector, yay | `apt-get update/upgrade`, `build-essential` | — |
| GNOME deps | `wl-clipboard` + AUR theme/extension | `adw-gtk-theme wl-clipboard` (errors hidden) | — |
| gaming, BlackArch, Hyprland | yes | skipped (`IS_ARCH`) | — |
| package groups | pacman/AUR | same Arch names via apt → most fail | — |
| security tools / summary / cleanup | pacman | **pacman called anyway** | — |

Arch/AUR-only names in groups (need per-distro mapping; source per distro = UNCLEAR until catalog re-verification): `google-chrome`, `localsend-bin`, `code`, `riseup-vpn`, `planify`, `libreoffice-fresh`, `losslesscut-bin`, `upscayl-bin`, `spotify`, `metasploit`, `burpsuite`, `exploitdb`, `wireshark-qt`, `anydesk-bin`, `rustdesk-bin`, `proton-vpn-gtk-app`, `qemu-desktop`, `ananicy-cpp`, `pinokio`, `stirling-pdf`, `devtoys-bin`, `clapgrep`, `metadata-cleaner`, `switcheroo`, `converseen`. The `v3.0` branch has a per-distro table for all 78 names (`data/packages.catalog`) — reusable after re-verification (D17).

## 7. Dependencies and network resources

| Resource | Used at | HTTP (2026-09-24) | Executed? |
|---|---|---|---|
| `https://aur.archlinux.org/yay-bin.git` | 494 | not checked | built with `makepkg` |
| `https://speed.cloudflare.com/__down?bytes=10000000` | 464 | not checked | no |
| `https://blackarch.org/strap.sh` | 985 | 000 (unreachable here) | **as root** |
| `raw.githubusercontent.com/Axenide/Ax-Shell/main/install.sh` | 1119 | 200 | yes |
| `github.com/prasanthrangan/hyprdots` → `Scripts/install.sh` | 1139 | 200 | yes |
| `github.com/mylinuxforwork/dotfiles` → `installer.sh` | 1156 | **404** | yes |
| `github.com/JaKooLit/Hyprland-Dots` → `install.sh` | 1172 | **404** | yes |
| `raw.githubusercontent.com/dexpota/kitty-themes/master/themes/<name>.conf` | 1286 | Dracula 200; other 4 **404** | no (config) |
| `raw.githubusercontent.com/alacritty/alacritty-theme/master/themes/<name>.toml` | 1308 | all 5 **404** (case) | no (config) |
| `raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh` | 1351 | not checked | yes (`sh -c`) |
| `github.com/zsh-users/zsh-autosuggestions`, `zsh-syntax-highlighting`, `romkatv/powerlevel10k` | 1356-1372 | not checked | sourced by zsh |
| `https://starship.rs/install.sh` | 1401, 1435 | not checked | yes (`curl \| sh`, non-Arch) |

System tools: bash, sudo, pacman, makepkg, git, yay, reflector, curl, bc, awk, sed, column, tput, dconf, systemctl, ufw, sysctl, usbguard, freshclam, rkhunter, lynis, clamscan, arch-audit, firecfg, starship, chsh, nano. No versions pinned.

## 8. Unsafe or risky operations

| Operation | Lines | Root | Reversible | Label |
|---|---|---|---|---|
| `rm /var/lib/pacman/db.lck` | 24 | yes | n/a | medium |
| `rm -rf ~/.config/<pkg>` for every target, `dconf reset -f /`, `rm -rf ~/.oh-my-zsh ~/.zshrc …` | 226-235, 281-282 | no | config dirs backed up; dconf/shell files **not** | high |
| `pacman -Rs` / `apt purge` of all group packages, `-Rns $(pacman -Qtdq)` | 256-272 | yes | no | high |
| `sed` on `/etc/pacman.conf` (blackarch, multilib) | 344-374, 587, 1003, 1050 | yes | no backup | high |
| `rm -rf /etc/pacman.d/gnupg`, `/var/lib/pacman/sync/*` | 354-355 | yes | no | high |
| `pacman-key --lsign-key` with fingerprint `…7D796237B` | 376, 990 | yes | — | high (S-02 UNCLEAR) |
| reflector overwrites `/etc/pacman.d/mirrorlist` | 396 | yes | no backup | medium |
| `strap.sh` downloaded to CWD and run as root, no checksum | 985-988 | yes | **ONE-WAY** | high |
| `pacman -S … --overwrite '*'` | 1033-1035 | yes | no | high |
| 4 Hyprland installers (curl/git + run) | 1119-1182 | via sudo inside | **ONE-WAY** | high |
| Oh-My-Zsh `sh -c "$(curl …)"`, Starship `curl \| sh` | 1351, 1401, 1435 | no / installer may sudo | **ONE-WAY** | high |
| `chsh` | 280, 1387, 1419, 1448 | yes | yes (manual) | low |
| `usermod -aG gamemode` | 647 | yes | manual | low |
| UFW default deny + enable (SSH not allowed first) | 1543-1545 | yes | yes | medium (remote lock-out) |
| `/etc/systemd/zram-generator.conf` | 1551 | yes | file | low |
| `sudo firecfg` (never runs today) | 1571 | yes | `firecfg --clean` | medium |
| `/etc/sysctl.d/99-security.conf` + `sysctl --system` | 1673-1690 | yes | delete file | medium |
| `sed` on `/etc/ssh/sshd_config` (`.bak` kept), restart sshd, no `sshd -t` | 1695-1719 | yes | `.bak` | high |
| USBGuard policy + enable | 1768-1775 | yes | disable service | high (input devices) |
| `pacman -Scc` | 1866 | yes | no | medium |
| `sudo reboot` | 1882 | yes | — | — |

## 9. State and resume

- Only state file: `~/.arcon_progress.log` (`:308`). Read (`wc -l`) and deleted, never written. `RESUME_ENABLED` set, never read. **Resume does not exist.**
- Cross-sector state lives in global variables (`IS_ARCH`, `gnome_done`, `base_done`, `gpu`, `install_term`) — lost on exit.
- Backups: `~/arcon_backup_<epoch>` (reset), `~/.config/hypr.bak_<epoch>`, `/etc/ssh/sshd_config.bak`. No index of what was changed.

## 10. Duplicated logic and technical debt

| Pattern | Examples |
|---|---|
| 3 progress-bar implementations | `update_ui` `:623`, `print_status_bar` `:862`, `print_opt_bar` `:1506` |
| `[ "$IS_ARCH" = true ] && pacman … \|\| apt-get …` (SC2015: apt runs on Arch if pacman fails) | `:1345`, `:1397`, `:1401`, `:1435` |
| pacs.txt parsing twice | `:177-183`, `:735-746` |
| multilib enable twice with different `sed` | `:587`, `:1003` |
| Starship preset menu twice | `:1412`, `:1432` |
| helpers defined inside branches | `update_ui` `:623`, `print_status_bar` `:862`, `apply_starship_preset` `:1228` |
| one package manager call per package | `:908-926` (`pacman -S` in loop) |
| success printed without checking | `:1665` "Vulnerabilities patched", `:1838` "Configured" |
| relative paths broken after `cd` | Hyprland installers `cd` `:1140`, `:1157`, `:1173`; later `configs/`, `wallp/` |
| ShellCheck | 52 findings: SC2086 ×14, SC2164 ×6, SC2046 ×6, SC2162 ×5, SC2015 ×5, others ×16 |

## 11. Existing tests

| Check | Result | Label |
|---|---|---|
| `bash -n setup.sh` | OK | — |
| `shellcheck setup.sh` (0.9.0) | 23 warnings, 29 notes | — |
| v2.5 test suite | none exists | NOT TESTED |
| `v3.0` branch `bats tests/bats/unit_*.bats` | 68/68 ok | UNIT TESTED (reference branch, not v2.5) |

## 12. Migration risks

| Risk | Why | Mitigation for Python port |
|---|---|---|
| Owner dotfiles altered | dconf GVariant typing, ConfigObj nesting; any "normalising" writer changes bytes | deploy by copy + explicit substitutions only; golden-file byte diff test (Phase 2) |
| dconf needs the user's D-Bus session | running under sudo or over SSH breaks `dconf load` | D15: run as user; detect `DBUS_SESSION_BUS_ADDRESS` |
| Monitor config diverges between GNOME and Hyprland | two different stores (`monitors.xml` vs `hyprland.conf`) | one layout model in profile, two writers (D13) |
| Wizard answers ≠ v2.5 behaviour | v2.5 couples prompts to side-effects | characterise *outputs* not prompts (Phase 2) |
| Package names per distro | 25+ Arch/AUR-only names | reuse + re-verify `v3.0` catalog; report unmapped |
| Trusting `v3.0` docs | referenced evidence documents missing | D17: code/tests are reference, docs are not |
| Third-party installers keep moving | 2 of 4 already 404 | D16 ONE-WAY, pinned commit, verify before run |

## 13. Proposed module map

| Feature(s) | Target | Notes |
|---|---|---|
| F01-F05 preflight | `arcon/core/preflight.py` | cross-cutting checks, not a domain |
| F06-F07 | `arcon/platform/detect.py` + `arcon/package/registry.py` | os-release parsed, never sourced |
| F08, F20 | `arcon/package/{pacman,aur,apt,dnf,flatpak}.py` + `arcon/data/packages.toml` | Debian+Ubuntu one provider (D4) |
| F09, F10 | `arcon/cli.py` (menu) + `arcon/recovery/reset.py` | |
| F11 | `arcon/recovery/journal.py`, `arcon/recovery/snapshot.py` | D6 |
| F12-F16 | `arcon/package/pacman.py` (keyring, mirrors), `arcon/package/aur.py` (yay) | Arch-specific actions |
| F17, F18 | `arcon/desktop/gnome.py` | uses `arcon/dotfiles` for gno.conf |
| F19 | `arcon/gaming/{common,arch,debian,fedora}.py` + `arcon/hardware/gpu.py` | decoupled from GNOME (D12) |
| F21 | `arcon/security/blackarch.py` | Arch only, repo change needs explicit intent |
| F22 | `arcon/desktop/hyprland.py` + `arcon/desktop/third_party.py` | ONE-WAY installers (D16) |
| F23 | `arcon/dotfiles/{deploy,capture,diff}.py` | D10 |
| F24 | `arcon/terminal/{terminator,kitty,alacritty,gnome_terminal}.py` | |
| F25 | `arcon/terminal/shell.py` | zsh/fish/bash + starship |
| F26, F28-F30 | `arcon/security/{tools,scan,hardening,hardened_mode}.py` | scope open (CLAUDE.md) |
| F27, F32 | `arcon/optimization/{catalog,linux}.py` + `arcon/data/optimizations.toml` | |
| F31 | `arcon/core/report.py` | built from journal |
| F33 | `arcon/core/reboot.py` | |
| **new** D13 | `arcon/display/{detect,gnome,hyprland}.py` | new domain `display` |
| — | `arcon/core/runner.py` (CommandRunner), `arcon/core/profile.py`, `arcon/core/wizard.py` | |

Fits no domain: F14 speed test (proposed: `core/preflight.py` as informational check). Windows/macOS: `arcon/package/{winget,brew}.py` stubs (D3).

## 14. Feature parity matrix

Written to `docs/FEATURE_MATRIX.md`.

## 15. Conflicts and questions

| # | Conflict / question | Relevant rule |
|---|---|---|
| C-1 | `v3.0` branch exists in Bash + PowerShell with full Windows implementation and README claims of openSUSE/macOS/Windows support | D1, D3 — resolved by D17 (reference only); owner confirmed Python |
| C-2 | `gno.conf` must be byte-identical (D8) but `picture-uri` points at a non-existent `default.jpg` → deploying unchanged gives a broken wallpaper | D8 vs correctness. Question: which wallpaper is the owner's? (`v3.0` defaulted to `Katana.jpg`) |
| C-3 | `hyprlock.conf:1` sources an Ax-Shell file; unchanged deploy breaks colours without Ax-Shell | D8 vs D12. Option: ship `arcon-colors.conf` as `v3.0` did (explicit, documented substitution) |
| C-4 | `hyprland.conf` monitor lines are owner's old layout; D13 regenerates them → file no longer byte-identical | D8 vs D13. Proposal: treat `monitor=` lines as a generated block, everything else untouched |
| C-5 | Factory reset (F10) is destructive by design; "port intent not bugs" — keep, restrict, or drop? | rule 2 |
| C-6 | Security scan / hardening scope for v3.0 undecided | open question |
| C-7 | Wallpaper licensing | open question |
| C-8 | Package catalog from `v3.0` claims verification against official indexes but the report file is missing — needs re-verification before reuse | D17 |
