#!/usr/bin/env python3
"""Generate docs/OPTIMIZATIONS.md and docs/PACKAGE-CATALOG.md from data/*.catalog.

Usage: python3 scripts/gen-catalog-docs.py [--verify-report FILE]
The verification summary is taken from the Markdown report printed by
`scripts/verify-catalog.py > FILE` (online check against official indexes).
"""
import argparse
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COLS = ["arch", "debian", "ubuntu", "fedora", "opensuse", "brew", "winget", "flatpak"]


def rows(path):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line and not line.startswith("#"):
                yield line.split("|")


def cell(value):
    return "–" if value in ("", "-") else "`" + value.replace("|", "\\|") + "`"


def gen_optimizations():
    out = [
        "# Optimization Catalog",
        "",
        "Generated from [`data/optimizations.catalog`](../data/optimizations.catalog) by",
        "`scripts/gen-catalog-docs.py`. Every optimization ArCoN can apply is listed here; nothing",
        "outside this catalog is applied. ArCoN makes **no FPS or speed promises**: the \"effect\"",
        "column states what changes, not a measured gain.",
        "",
        "Rules (enforced by `tests/bats/unit_catalog.bats` and `tests/pester/ArCoN.Tests.ps1`):",
        "unique ids, 9 fields, every Linux/macOS id has an `opt_<id>()` implementation, every Windows",
        "id matches a task in `Modules.ps1`, no `high`-risk item is enabled by any profile.",
        "",
        "| id | category | platforms | risk | profiles | description | effect | rollback | verification |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for f in rows(os.path.join(ROOT, "data", "optimizations.catalog")):
        f = [x.replace("|", "\\|") for x in f]
        out.append("| `%s` | %s |" % (f[0], " | ".join(f[1:])))
    out.append("")
    return "\n".join(out)


def parse_report(path):
    res = {}
    if not path or not os.path.exists(path):
        return res
    cur = None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"## (\w+)", line)
            if m:
                cur = m.group(1)
                continue
            m = re.match(r"FOUND (\d+) / NOT_FOUND (\d+) / UNVERIFIED (\d+)", line)
            if m and cur:
                res[cur] = tuple(int(x) for x in m.groups())
            m = re.match(r"Generated: (.*)", line)
            if m:
                res["_date"] = m.group(1).strip()
    return res


def gen_packages(report):
    data = list(rows(os.path.join(ROOT, "data", "packages.catalog")))
    rep = parse_report(report)
    out = [
        "# Package Catalog",
        "",
        "Generated from [`data/packages.catalog`](../data/packages.catalog) by",
        "`scripts/gen-catalog-docs.py`. `–` = not packaged for that platform (the package is",
        "reported as unavailable and skipped, never silently replaced).",
        "",
        "## Verification",
        "",
        "`scripts/verify-catalog.py` checks every name against the official index of each",
        "source: archlinux.org + AUR RPC, Debian madison (stable), Launchpad (Ubuntu 24.04",
        "\"noble\"), Fedora mdapi, Repology (openSUSE Tumbleweed), formulae.brew.sh, winget-pkgs",
        "manifests on GitHub, Flathub API. `.github/workflows/catalog.yml` repeats the check weekly.",
        "`--offline` only checks structure. In addition, the CI distro jobs resolve every name of",
        "the `full` profile with the real package manager inside a container (dry-run).",
        "",
    ]
    if rep:
        out += ["Last online report: %s" % rep.get("_date", "unknown"), "",
                "| column | found | not found | unverified |", "|---|---|---|---|"]
        for c in COLS:
            if c in rep:
                out.append("| %s | %d | %d | %d |" % ((c,) + rep[c]))
        out += ["",
                "\"Unverified\" means the index could not be queried from the verification",
                "environment (rate limit / no API), not that the package is missing. Names that",
                "were not found have been corrected or set to `–`; see CHANGELOG.md.", ""]
    else:
        out += ["No online report available in this build.", ""]
    out += ["Notes:", "",
            "- Debian column = current Debian stable; Ubuntu column = packages of the running",
            "  release. Some names exist only in newer releases (e.g. `hyprland` is in Ubuntu 26.04",
            "  but not in 24.04); on older releases they are reported unavailable at run time.",
            "- `cask:` = Homebrew cask, `@group`/`pattern:` = dnf group / zypper pattern.",
            "",
            "## Packages (%d)" % len(data), "",
            "| id | groups | " + " | ".join(COLS) + " | description |",
            "|---|---|" + "---|" * len(COLS) + "---|"]
    for f in data:
        out.append("| `%s` | %s | %s | %s |" % (f[0], f[1], " | ".join(cell(x) for x in f[2:10]), f[10]))
    out.append("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify-report")
    a = ap.parse_args()
    with open(os.path.join(ROOT, "docs", "OPTIMIZATIONS.md"), "w", encoding="utf-8") as fh:
        fh.write(gen_optimizations())
    with open(os.path.join(ROOT, "docs", "PACKAGE-CATALOG.md"), "w", encoding="utf-8") as fh:
        fh.write(gen_packages(a.verify_report))
    print("wrote docs/OPTIMIZATIONS.md docs/PACKAGE-CATALOG.md")


if __name__ == "__main__":
    main()
