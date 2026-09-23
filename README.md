# ArCoN v3.0

Setup, hardening and gaming configuration toolkit for Arch Linux, Debian, Ubuntu, Fedora,
openSUSE, macOS and Windows — with dry-run, profiles, resume and rollback.

[![CI](https://github.com/MrFedai/ArCoN/actions/workflows/ci.yml/badge.svg?branch=v3.0)](https://github.com/MrFedai/ArCoN/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

ArCoN v3.0 is a refactor of [ArCoN v2.5](legacy/v2.5/README.md). Every v2.5 feature is kept,
fixed or explicitly marked as not applicable to a platform — see the
[feature parity matrix](docs/FEATURE-PARITY.md) and the [v2.5 audit](docs/AUDIT-v2.5.md).

## Platform status

Honest status as of this release. "CI" means a GitHub Actions job exercises the code path;
it does **not** mean the result was checked on real hardware. Details and evidence:
[docs/PLATFORMS.md](docs/PLATFORMS.md) and [docs/FINAL-AUDIT-v3.0.md](docs/FINAL-AUDIT-v3.0.md).

| Platform | Entry point | Level reached |
|---|---|---|
| Arch Linux (+ EndeavourOS, CachyOS as derivatives) | `setup.sh` | container dry-run in CI, mocked integration tests |
| Debian stable | `setup.sh` | container dry-run in CI, mocked integration tests |
| Ubuntu 24.04 / 26.04 | `setup.sh` | real run in an Ubuntu 26.04 VM (packages, resume, rollback); container dry-run for 24.04 |
| Fedora | `setup.sh` | container dry-run in CI, mocked integration tests |
| openSUSE Tumbleweed / Leap | `setup.sh` | container dry-run in CI (Tumbleweed), mocked integration tests |
| macOS (Apple Silicon, Intel) | `setup.sh` (Homebrew) | dry-run on the GitHub macOS runner |
| Windows 11 | `setup.ps1` (PowerShell 7) | Pester (mocked) + dry-run on the GitHub Windows runner |
| Windows 10 | `setup.ps1` | experimental, not tested |

Other distributions are detected and refused, or run as "experimental" when they are a known
derivative of one of the above. Nothing has been validated on native hardware yet.

## Quick start

Linux / macOS:

```bash
git clone https://github.com/MrFedai/ArCoN.git
cd ArCoN
./setup.sh --dry-run          # see what would change
./setup.sh                    # interactive wizard (the v2.5 flow)
./setup.sh --profile gaming   # or pick a profile
```

Windows (PowerShell 7, elevated):

```powershell
git clone https://github.com/MrFedai/ArCoN.git
cd ArCoN
.\setup.ps1 -DryRun
.\setup.ps1 -Profile Gaming
```

Every run follows **detect → validate → plan → show → confirm if risky → apply → verify**.
A run can be continued with `--resume` / `-Resume` and undone with `--rollback` / `-Rollback`.

## Profiles

No profile is aggressive by default; high-risk steps always need an explicit confirmation.

| Profile | Content |
|---|---|
| `minimal` | base update + essential packages, low-risk maintenance only |
| `balanced` | essentials + media, terminal & shell, firewall, low-risk optimizations |
| `performance` | balanced + performance power profile, zram, storage maintenance |
| `gaming` | Steam, GPU drivers (auto-detected), GameMode, MangoHud |
| `developer` | essentials + power tools, kitty + zsh/powerlevel10k |
| `security` | cyber and audit tools, firewall, sysctl + SSH hardening |
| `full` | everything v2.5 offered (all groups, GNOME, gaming, terminal, security) |
| `custom` | the classic v2.5 wizard — every sector asked step by step |

Optimizations are listed with risk, effect, rollback and verification in
[docs/OPTIMIZATIONS.md](docs/OPTIMIZATIONS.md). ArCoN does not promise FPS or speed gains.

## Modules

| Module | v2.5 sector | Platforms |
|---|---|---|
| base | 1 — base system, mirrors, keyring, AUR helper | Linux, macOS (Homebrew), Windows (preflight) |
| packages | 3 — package engine | all ([catalog](docs/PACKAGE-CATALOG.md)) |
| gnome | 2A — GNOME settings, debloat | Linux with GNOME |
| gaming | 2B — Steam, GPU drivers, GameMode | Linux; Windows equivalents |
| blackarch | 4 — BlackArch repository | Arch only |
| hyprland | 6 — Hyprland + themes | Linux where Hyprland is packaged; each theme lists its own supported distros |
| dotfiles | 7 — Terminator config, wallpapers | Linux, macOS |
| terminal, shell | 8 — terminal emulator, zsh/fish/bash, Starship, Nerd Font | Linux, macOS |
| security | 9 — tools, scans, firewall, hardening, Hardened Mode | Linux; macOS/Windows: tools where packaged; Windows: Defender/Firewall/BitLocker/UAC report |
| optimize, cleanup | 9 + final cleanup | all |
| reset | Smart Factory Reset | Linux, macOS (bash); not ported to Windows |

## Documentation

- [Usage](docs/USAGE.md) — every option, configuration keys, examples
- [Architecture](docs/ARCHITECTURE.md) · [Platforms](docs/PLATFORMS.md) · [Security](docs/SECURITY.md)
- [Testing](docs/TESTING.md) · [Development](docs/DEVELOPMENT.md) · [Change management](docs/CHANGE-MANAGEMENT.md)
- [Migration from v2.5](docs/MIGRATION.md) · [Changelog](CHANGELOG.md)
- [v2.5 audit](docs/AUDIT-v2.5.md) · [Feature parity](docs/FEATURE-PARITY.md) · [Final audit v3.0](docs/FINAL-AUDIT-v3.0.md)

## Notes

- Live USB: detected; all changes are lost after reboot.
- BlackArch: the repository is only added on explicit request, after checksum and key verification.
- Remote installers (Hyprland themes, ML4W) are third-party code; ArCoN shows the source and commit
  and asks before running them.
- v2.5 is preserved unchanged in [legacy/v2.5](legacy/v2.5/README.md) and as git tag `v2.5.0`.

## License

[MIT](LICENSE)
