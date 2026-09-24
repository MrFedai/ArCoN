# ArCoN v3.0 — Project Rules (persistent, read every session)

## Mission
Migrate ArCoN v2.5 to ArCoN v3.0: Python, object-oriented, modular, testable.
Primary user today: the owner, on ONE machine. Later: all users. Design for one machine, do not block multi-user later.
Order of priority: 1) protect the owner's configuration, 2) preserve v2.5 intent, 3) improve architecture, 4) add new features.
This is a migration + refactor, NOT a blind rewrite.

## Final decisions (made by the owner — do not re-litigate)
If you find a strong technical reason to deviate, STOP, explain the reason and wait. Do not deviate silently.

| ID | Decision |
|----|----------|
| D1 | Language: Python 3.11+. Single entry point `arcon`. `setup.sh` / `setup.ps1` are thin bootstrap only (install uv, create environment, launch arcon). No business logic in shell. |
| D2 | Ultimate-style Windows performance tweaks are OUT OF SCOPE (separate project). Do not add registry/service/boot tweaks. |
| D3 | v3.0 acceptance: Linux = full. Windows and macOS = skeleton only (interfaces + stub providers that report "not implemented"). Never claim Windows/macOS support. |
| D4 | Full Linux scope: Arch, Debian, Ubuntu, Fedora. Debian and Ubuntu share ONE Debian-family provider; differences via config or a small subclass. |
| D5 | Distribution: thin bootstrap + uv. No PyInstaller/binaries in v3.0. |
| D6 | Rollback is HYBRID: use filesystem snapshot (Btrfs/Snapper/Timeshift, etc.) when available; otherwise per-file backup of every file changed. A JSON-lines journal is ALWAYS written and drives resume/idempotency. Never claim package installs were rolled back unless verified. |
| D7 | New CLI + migration guide. v2.5 CLI compatibility is NOT required. |
| D8 | **Dotfiles are sacred and stay in their NATIVE format.** `configs/gno.conf` (dconf keyfile), `configs/terminator/config` (ConfigObj), `configs/hypr/*.conf` (Hyprland syntax) are NEVER converted to TOML. They are deployed byte-identical except for explicit template variables (e.g. `USER_PLACEHOLDER` → user name). Acceptance test: diff between repo file and deployed file shows ONLY template substitutions. The owner's dark theme (`color-scheme='prefer-dark'`, `gtk-theme='adw-gtk3-dark'`), terminal colors/fonts and keybindings must survive migration unchanged. |
| D9 | TOML is ONLY for ArCoN's own profile: selected modules, package lists, user choices, monitor layout. Read with stdlib `tomllib`. For writing, choose one writer library explicitly and justify it. |
| D10 | **Dotfile manager is built into ArCoN** (no chezmoi dependency). Minimal scope: `deploy`, `capture` (live machine → repo), `diff`. Rule: no file is overwritten without (a) showing a diff and (b) a backup recorded in the journal. |
| D11 | **Source of truth for dotfiles in v3.0 = the files currently in the repo.** The owner will refresh them later with `arcon capture`. Do not pull from the live machine automatically. |
| D12 | **Desktop: GNOME is primary and must be fully supported. Hyprland is optional** — installable by anyone who selects it, but not the default. Gaming, terminal, shell and security modules MUST NOT depend on GNOME or Hyprland (remove the v2.5 "gaming requires GNOME" coupling). |
| D13 | **Monitors:** layout (position, scale, primary) is the owner's personal setting, stored in the profile and changeable. Mode (resolution + refresh rate) is DETECTED automatically: pick the maximum supported mode per monitor. Match monitors by identity (vendor/model/serial), never by connector name (`eDP-1` vs `eDP-2` changes with the driver). After applying a mode, verify it is active; if not (cable/port bandwidth), fall back to the next best mode and report it. Tie-break when max resolution and max refresh cannot coexist: **resolution first** (default, configurable in profile). Owner has 1 machine with 2–3 monitors. GNOME: apply through Mutter's display-config interface (it persists `monitors.xml` itself) — do not hand-write XML unless justified. Hyprland: generate monitor lines. |
| D14 | **Interaction model:** sections stay user-selectable (any section may be wanted or not). ALL questions are asked up front by a wizard → a summary screen (what installs, which files change, estimated size) → ONE confirmation → silent apply. Answers are saved to the profile; next run offers "reuse previous answers". Mid-run prompts only when unavoidable (sudo password, AUR PKGBUILD review). All output is also written to a log file. |
| D15 | **Privilege model:** ArCoN runs as the normal user. Only individual commands are elevated via sudo through `CommandRunner`. Refuse to run the whole process as root (it breaks `$HOME`/`$USER`). |
| D17 | **Existing `v3.0` branch (Bash + PowerShell, 2026-09-23) is a REFERENCE, not the base.** v3.0 is rebuilt in Python on `v3-dev` (branched from `main` / tag `v2.5.0`). Reuse from `v3.0`: bug-fix knowledge, `data/packages.catalog` and `data/optimizations.catalog` (after re-verification), bats tests as behavior specification. Do NOT trust its documentation claims without evidence: many docs it links (ARCHITECTURE, SECURITY, PLATFORMS, FINAL-AUDIT, TESTING, CHANGELOG, MIGRATION) do not exist on the branch. Never delete or rewrite the `v3.0` branch. |
| D16 | **Third-party installers** (Ax-Shell, Hyprdots/HyDE, ML4W, JaKooLit, oh-my-zsh, BlackArch strap.sh — anything `curl | sh` or `git clone && ./install.sh`) are kept as OPTIONAL actions labeled **ONE-WAY**: excluded from rollback promises, shown with a warning in the summary, never selected by default. |

## Architecture rules
- ONE axis: `arcon/<domain>/<provider>.py` (e.g. `package/apt.py`, `hardware/linux.py`). No separate `platforms/` tree.
- Domains (adjust after audit): package, hardware, display, dotfiles, gaming, security, desktop, terminal, optimization, recovery.
- Every system call goes through a `CommandRunner` interface (dry-run, mocking, logging, timeouts, sudo). No direct `subprocess` elsewhere.
- Every action declares: `plan()` (what would change), `apply()`, `verify()`, and `reversible: bool`.
- Depend on abstractions; register providers explicitly; no giant `if OS ==` chains.
- Package names are mapped per distro in a data table (official repo / AUR / Flatpak / unavailable). Missing mapping = reported, never guessed.
- Do not wrap trivial code in classes. Abstraction only where there is real variation.
- Human-readable structure beats clever structure. Do not reorganize files for aesthetics.

## Non-negotiable rules
1. No silent feature loss. Track every v2.5 feature in `docs/FEATURE_MATRIX.md`: keep / replace / fix / N-A (with reason).
2. **Port the intent, not the bugs.** v2.5 behavior identified as a bug or unsafe in the audit is marked `fix` in the matrix and is NOT ported as-is without owner approval (e.g. wiping `/etc/pacman.d/gnupg` every run, `pacman -Scc`, `dconf reset -f /`, config deletion that ignores the protected list).
3. Test status labels, always: UNIT TESTED / INTEGRATION TESTED (container) / VM TESTED / NATIVE TESTED / NOT TESTED. Never claim more than was actually run. Containers do not validate hardware, GPU, monitors, gaming or desktop behavior.
4. Every mutating action supports dry-run and is idempotent. No unsafe or unjustified system changes. Do not modify package repositories without explicit user intent.
5. Never touch the `v2.5.0` tag, `main`, or the `v3.0` reference branch. Work on `v3-dev`.
6. Do not overwrite working code without a documented reason.
7. Report facts with evidence (command + output). If something was not run, say NOT TESTED.

## Phase roadmap (one phase per session; stop and wait for owner approval after each)
1. Audit (read-only): repo, features, configs, dependencies, unsafe operations, debt. Verify `docs/PRIOR_AUDIT.md`.
2. Golden-file tests: capture WHAT v2.5 writes (target paths + content of deployed dotfiles, dconf keys loaded, package lists per section). Do not try to characterize the whole interactive script.
3. Core skeleton: CommandRunner, profile (TOML), journal/recovery, wizard + summary + confirm flow, CLI shell, Windows/macOS stubs.
4. Hardware + display detection (GPU, monitors/EDID modes) + package providers (Arch, Debian family, Fedora) + package mapping table.
5. Dotfiles module (deploy / capture / diff) + feature migration: GNOME, gaming, terminal/shell, security, optimization, optional Hyprland.
6. CLI polish + migration guide.
7. CI + container test matrix (Arch, Debian, Ubuntu, Fedora) and honest test-status report.
8. Documentation, changelog, final audit (PASS / FAIL / PARTIAL / NOT TESTED with evidence).

## Open questions (do not decide these yourself — list them when relevant)
- Wallpapers in `wallp/` include third-party IP; public-repo licensing not decided.
- Security scan / hardening module scope for v3.0 not decided.

## Reporting format after every phase
What was done · Evidence · What is NOT tested · Risks · Deviations from these rules (should be none) · Questions for the owner.
