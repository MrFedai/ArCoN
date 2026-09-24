# Prior audit of ArCoN v2.5 (external review, 2026-09-24)

Status: findings from reading the repository; NOT executed. Line numbers are approximate — the authoritative, verified version is `docs/AUDIT.md` §0.1.

| # | Location | Finding | Impact |
|---|---|---|---|
| 1 | setup.sh ~75 | Stray bare `END` line | "command not found", script continues |
| 2 | global | `CYAN`, `BOLD`, `DIM`, `GRAY`, `MAGENTA` used but never defined (only GREEN/BLUE/YELLOW/RED/NC) | Empty color codes |
| 3 | pre-flight ~27-35 | Internet check is commented out but "Internet connection: OK" is still printed | False status |
| 4 | resume ~307-325 | `~/.arcon_progress.log` is read but never written; `RESUME_ENABLED` is never used | Advertised resume feature does not exist |
| 5 | sector 9 ~1492 vs ~1569 | Array item "Firejail (Sandbox All)" vs case label "Firejail (Sandbox Integration)" | Firejail step never runs |
| 6 | sector 9 | `ufw` and `zram-generator` are never installed; steps are skipped silently if absent | Firewall/ZRAM silently not applied |
| 7 | Debian path | Security tools install, summary, final cleanup call `pacman` unconditionally; many package names are Arch/AUR-only (`google-chrome`, `*-bin`, `metasploit`, `burpsuite`…) | Debian/Ubuntu support is nominal |
| 8 | sector 8 Alacritty/Kitty themes | `curl -sS` without `-f`; theme file name casing may not match upstream repo | 404 body can overwrite `alacritty.toml` |
| 9 | factory reset ~200-235 | Config deletion loop ignores `PROTECTED_PKGS`; `*)` maps every package to `~/.config/<pkg>` (git, nvim, Code); `dconf reset -f /` wipes all GNOME settings | User data removed (a backup is made) |
| 10 | sector 1 ~354-355 | Every run deletes `/etc/pacman.d/gnupg` and `/var/lib/pacman/sync/*` | Unnecessarily destructive |
| 11 | sector 2 | Gaming/GPU setup only offered if GNOME settings were applied | Non-GNOME users cannot get gaming |
| 12 | configs/gno.conf 5-6, 43 | References `~/Pictures/wallp/default.jpg`; no `default.jpg` in `wallp/` | Broken wallpaper |
| 13 | configs/hypr/hyprland.conf 20-21, 241 | Hard-coded monitors (`HDMI-A-1 1920x1080@180`, `eDP-2 2560x1600@165`); `SUPER+P` runs `shutdown now` without confirmation | Breaks on other hardware / accidental shutdown |
| 14 | final cleanup | `pacman -Scc` clears the whole package cache | No downgrade path; conflicts with rollback (D6) |
| 15 | sector 3 package engine | Anything not found by `pacman -Si` is treated as AUR | Typos are sent to yay |
| 16 | README | Claims GPU auto-detect, conflict resolution, resume | Not implemented / manual |
| 17 | wallp/ | Third-party IP and a real person's photo | Licensing risk in a public repo |

Additional notes:
- Running `sudo ./setup.sh` would make `$HOME`/`$USER` resolve to root (dotfiles land in /root).
- GPU selection is a manual `select` menu, not detection.
- Owner's theme settings to protect: gno.conf `color-scheme='prefer-dark'`, `gtk-theme='adw-gtk3-dark'`, fonts (Adwaita Sans/Mono 11); terminator profile colors/palette/font.
