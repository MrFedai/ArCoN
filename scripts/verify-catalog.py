#!/usr/bin/env python3
"""Validate data/packages.catalog against official package indexes.

Checks every non "-" cell against the authoritative index of that platform:

  arch     archlinux.org JSON API (official) + AUR RPC v5
  debian   Debian ftp-master "madison" API (suite: stable)
  ubuntu   Launchpad API, published binaries (series: noble / 24.04 LTS)
  fedora   Fedora mdapi (branch: latest stable found at runtime)
  opensuse Repology API (repo: opensuse_tumbleweed), binary names
  brew     formulae.brew.sh formula.json / cask.json
  winget   microsoft/winget-pkgs manifests tree (GitHub API)
  flatpak  Flathub appstream API

Output: a Markdown report (stdout) and a non-zero exit code when any cell
is NOT_FOUND. Cells that could not be checked are reported as UNVERIFIED and
never counted as PASS.

Usage: scripts/verify-catalog.py [--only arch,brew] [--json out.json]
       scripts/verify-catalog.py --offline   (structure only, no network)
Environment: GITHUB_TOKEN (optional, raises GitHub rate limits)
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "data", "packages.catalog")
COLS = ["id", "groups", "arch", "debian", "ubuntu", "fedora", "opensuse",
        "brew", "winget", "flatpak", "description"]
UA = {"User-Agent": "ArCoN-catalog-verifier/3.0 (+https://github.com/MrFedai/ArCoN)"}


def get(url, headers=None, timeout=30, retries=3):
    h = dict(UA)
    if headers:
        h.update(headers)
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=timeout) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            if e.code in (404, 410):
                return e.code, b""
            if e.code == 429 and attempt < retries - 1:
                time.sleep(5 * (attempt + 1))
                continue
            return e.code, b""
        except Exception:  # network error
            if attempt < retries - 1:
                time.sleep(2)
                continue
            return None, b""
    return None, b""


def load_catalog():
    rows = []
    with open(CATALOG, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("|")
            if len(parts) != len(COLS):
                raise SystemExit(f"malformed catalog line ({len(parts)} cols): {line}")
            rows.append(dict(zip(COLS, parts)))
    return rows


# ---------------------------------------------------------------- checkers
def check_arch(names):
    out = {}
    for n in names:
        st, body = get(f"https://archlinux.org/packages/search/json/?name={urllib.parse.quote(n)}")
        if st == 200 and json.loads(body)["results"]:
            out[n] = "FOUND(official)"
        elif st is None:
            out[n] = "UNVERIFIED"
    rest = [n for n in names if n not in out]
    for i in range(0, len(rest), 50):
        chunk = rest[i:i + 50]
        q = "&".join("arg[]=" + urllib.parse.quote(n) for n in chunk)
        st, body = get("https://aur.archlinux.org/rpc/v5/info?" + q)
        found = {r["Name"] for r in json.loads(body)["results"]} if st == 200 else None
        for n in chunk:
            out[n] = "UNVERIFIED" if found is None else ("FOUND(aur)" if n in found else "NOT_FOUND")
    return out


def check_debian(names):
    out = {}
    for n in names:
        st, body = get(f"https://api.ftp-master.debian.org/madison?package={urllib.parse.quote(n)}&s=stable&f=json")
        if st != 200:
            out[n] = "UNVERIFIED"
            continue
        data = json.loads(body or b"[]")
        out[n] = "FOUND" if data and data[0] else "NOT_FOUND"
    return out


def check_ubuntu(names, series="noble"):
    out = {}
    for n in names:
        url = ("https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedBinaries"
               f"&binary_name={urllib.parse.quote(n)}&exact_match=true&status=Published"
               f"&distro_arch_series=https://api.launchpad.net/1.0/ubuntu/{series}/amd64&ws.size=1")
        st, body = get(url)
        if st != 200:
            out[n] = "UNVERIFIED"
            continue
        out[n] = "FOUND" if json.loads(body).get("total_size", 0) > 0 else "NOT_FOUND"
    return out


def fedora_branch():
    for rel in range(46, 39, -1):
        st, _ = get(f"https://mdapi.fedoraproject.org/f{rel}/pkg/bash")
        if st == 200:
            return f"f{rel}"
    return "rawhide"


def check_fedora(names):
    br = fedora_branch()
    out = {}
    for n in names:
        if n.startswith("@"):
            # dnf groups are not in mdapi; validated in CI containers instead.
            out[n] = "UNVERIFIED(group)"
            continue
        st, _ = get(f"https://mdapi.fedoraproject.org/{br}/pkg/{urllib.parse.quote(n)}")
        if st == 200:
            out[n] = f"FOUND({br})"
        else:
            # binary sub-packages: search by provides
            st2, _ = get(f"https://mdapi.fedoraproject.org/{br}/provides/{urllib.parse.quote(n)}")
            out[n] = f"FOUND({br},provides)" if st2 == 200 else ("NOT_FOUND" if st in (404,) else "UNVERIFIED")
    return out


def check_opensuse(names):
    out = {}
    for n in names:
        if n.startswith("pattern:"):
            out[n] = "UNVERIFIED(pattern)"
            continue
        # Repology project name usually equals the upstream name; we look the
        # binary name up through the project that contains it.
        st, body = get(f"https://repology.org/api/v1/projects/?search={urllib.parse.quote(n)}&inrepo=opensuse_tumbleweed")
        time.sleep(1.1)  # repology asks for <= 1 req/s
        if st != 200:
            out[n] = "UNVERIFIED"
            continue
        found = False
        for _proj, pkgs in json.loads(body).items():
            for p in pkgs:
                if p.get("repo") == "opensuse_tumbleweed" and n in (p.get("binname"), p.get("srcname")):
                    found = True
        out[n] = "FOUND(tumbleweed)" if found else "NOT_FOUND"
    return out


def check_brew(names):
    _, f = get("https://formulae.brew.sh/api/formula.json", timeout=120)
    _, c = get("https://formulae.brew.sh/api/cask.json", timeout=120)
    if not f or not c:
        return {n: "UNVERIFIED" for n in names}
    formulae = {x["name"] for x in json.loads(f)} | {a for x in json.loads(f) for a in x.get("aliases", [])}
    casks = {x["token"] for x in json.loads(c)}
    out = {}
    for n in names:
        if n.startswith("cask:"):
            out[n] = "FOUND(cask)" if n[5:] in casks else "NOT_FOUND"
        else:
            out[n] = "FOUND(formula)" if n in formulae else "NOT_FOUND"
    return out


def check_winget(names):
    hdr = {"Accept": "application/vnd.github+json"}
    tok = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if tok:
        hdr["Authorization"] = f"Bearer {tok}"
    out = {}
    for n in names:
        path = "/".join(n.split("."))
        url = f"https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/{n[0].lower()}/{path}"
        st, body = get(url, headers=hdr)
        if st == 200:
            items = json.loads(body)
            # a package folder contains version folders; a namespace folder contains
            # other package folders. Heuristic: a version folder name starts with a digit.
            ok = any(i["type"] == "dir" and i["name"][:1].isdigit() for i in items)
            out[n] = "FOUND" if ok else "NOT_FOUND(namespace-only)"
        elif st == 404:
            out[n] = "NOT_FOUND"
        else:
            out[n] = "UNVERIFIED"
    return out


def check_flatpak(names):
    out = {}
    for n in names:
        st, _ = get(f"https://flathub.org/api/v2/appstream/{urllib.parse.quote(n)}")
        out[n] = "FOUND" if st == 200 else ("NOT_FOUND" if st == 404 else "UNVERIFIED")
    return out


CHECKERS = {"arch": check_arch, "debian": check_debian, "ubuntu": check_ubuntu,
            "fedora": check_fedora, "opensuse": check_opensuse, "brew": check_brew,
            "winget": check_winget, "flatpak": check_flatpak}


def offline_check():
    """Structure of data/packages.catalog; returns an exit code."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "packages.catalog")
    errors, ids = [], set()
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cols = line.split("|")
            if len(cols) != 11:
                errors.append(f"line {n}: {len(cols)} fields (expected 11)")
                continue
            if cols[0] in ids:
                errors.append(f"line {n}: duplicate id {cols[0]}")
            ids.add(cols[0])
            if not cols[1].strip():
                errors.append(f"line {n}: no group")
            if all(c.strip() == "-" for c in cols[2:10]):
                errors.append(f"line {n}: {cols[0]} is not available on any platform")
            if not cols[10].strip():
                errors.append(f"line {n}: {cols[0]} has no description")
    for e in errors:
        print("CATALOG FAIL:", e)
    print(f"catalog: {len(ids)} ids, {len(errors)} structural error(s)")
    return 1 if errors else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=",".join(CHECKERS))
    ap.add_argument("--json")
    ap.add_argument("--offline", action="store_true",
                    help="structural checks only (field count, unique ids, groups)")
    a = ap.parse_args()
    if a.offline:
        sys.exit(offline_check())
    rows = load_catalog()
    results = {}
    for col in a.only.split(","):
        names = sorted({r[col] for r in rows if r[col] != "-"})
        print(f"[verify] {col}: {len(names)} names", file=sys.stderr)
        results[col] = CHECKERS[col](names)
    bad = 0
    print("# Package catalog verification report\n")
    print(f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S %z')}\n")
    for col, res in results.items():
        found = sum(1 for v in res.values() if v.startswith("FOUND"))
        nf = [k for k, v in res.items() if v.startswith("NOT_FOUND")]
        unv = [k for k, v in res.items() if v.startswith("UNVERIFIED")]
        bad += len(nf)
        print(f"## {col}\n\nFOUND {found} / NOT_FOUND {len(nf)} / UNVERIFIED {len(unv)}\n")
        if nf:
            print("NOT_FOUND: " + ", ".join(f"`{x}`" for x in nf) + "\n")
        if unv:
            print("UNVERIFIED: " + ", ".join(f"`{x}`" for x in unv) + "\n")
    if a.json:
        with open(a.json, "w") as f:
            json.dump(results, f, indent=1, sort_keys=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
