# PHASE 1 — ArCoN v2.5 AUDIT (READ-ONLY)

Read `CLAUDE.md` first. Its decisions and rules are binding.
Read `docs/PRIOR_AUDIT.md` second. It lists 17 findings from an earlier review. Do not rediscover them from scratch: verify each one.

## Your task
Audit the ArCoN v2.5 repository in this working directory. This phase is READ-ONLY analysis.
Do NOT refactor, rename, move or delete anything. Do NOT execute scripts that change the system
(package installs, service changes, config writes, dconf loads). Reading files and running harmless inspection
commands (ls, grep, shellcheck, bash -n, git log, git diff) is fine.

## Before you start (the only allowed writes besides docs/)
1. Create a git tag `v2.5-final` on the current commit if it does not exist (do not push unless asked).
2. Create and switch to a branch `v3-dev`.

## Deliverable: `docs/AUDIT.md`
Base every statement on files you actually read. Cite file paths and line ranges.
If something is unclear, write "UNCLEAR" instead of guessing. Prefer tables over prose.

0. **Prior audit verification** — for each finding in `docs/PRIOR_AUDIT.md`: CONFIRMED / REFUTED / PARTIAL, with line evidence. Then list NEW findings.
1. **Repository structure** — tree, entry points, how setup/run works today.
2. **Feature inventory** — every user-visible feature (gaming, security, GNOME, Hyprland, terminal/shell, optimization, resume, factory reset, BlackArch, package management, hardware/GPU selection, cleanup, reboot), where it lives, how it is triggered, and which other features it depends on (e.g. gaming → GNOME).
3. **Dotfile inventory (critical, see D8/D10)** — per file in `configs/`: native format, target path on the system, how v2.5 deploys it (copy / dconf load / sed), template variables, **machine-specific values** (monitor lines, user name, absolute paths, hardware names), references to files that do not exist, secrets (yes/no). Key-level detail ONLY for templatable/machine-specific values and for the owner's theme settings (dark theme, GTK/icon theme, fonts, terminal colors, keybindings). Do NOT list every app-folder entry.
4. **Display / monitor handling** — how v2.5 configures monitors today (hyprland.conf lines, GNOME), what is hard-coded. Input for D13.
5. **Existing CLI surface** — prompts (in order), menus, flags, environment variables. Mark which prompts happen mid-install (input for D14).
6. **Distro behavior** — what is Arch/Debian/Ubuntu/Fedora specific; what is hard-coded to one distro; package names that do not exist outside Arch/AUR (table: package → section → likely source per distro, UNCLEAR if unsure).
7. **Dependencies** — external tools, packages, network resources (every URL fetched), versions.
8. **Unsafe or risky operations** — anything touching repos, services, kernel params, system files, boot, SSH, firewall; anything run as root; anything downloaded and executed (label ONE-WAY per D16); anything deleting user data.
9. **State and resume** — how progress/resume works today, where state is stored, whether it is actually written.
10. **Duplicated logic and technical debt** — concrete examples with line numbers.
11. **Existing tests** — what exists; run only read-only checks (`bash -n`, `shellcheck`) and report results.
12. **Migration risks** — what is most likely to break during the port, especially anything that could alter the owner's dotfiles.
13. **Proposed module map** — map every v2.5 feature to `arcon/<domain>/<provider>.py` following `CLAUDE.md`. Flag features that fit no domain.
14. **Feature parity matrix skeleton** — write `docs/FEATURE_MATRIX.md`: every v2.5 feature, target module, action (keep / replace / fix / N-A), reversible (yes / no / ONE-WAY), Linux columns (Arch / Debian / Ubuntu / Fedora) all `NOT MIGRATED`, Windows/macOS `stub`.
15. **Conflicts and questions** — anything conflicting with `CLAUDE.md` decisions. Do not resolve them; list them.

## Rules for this phase
- No feature is "unsupported" or "removed" just because it is awkward; list it.
- Do not claim anything works unless you ran it. Use the test-status labels from `CLAUDE.md`.
- Do not open, load or apply any dotfile on the system.

## Finish
Reply using the reporting format in `CLAUDE.md`. Then STOP and wait for the owner's approval before Phase 2.
