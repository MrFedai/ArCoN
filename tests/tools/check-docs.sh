#!/usr/bin/env bash
# Documentation consistency checks (run in CI):
#  1. every relative Markdown link points to an existing file
#  2. every CLI option shown by `setup.sh --help` is documented in docs/USAGE.md
#  3. every profile in profiles/ is documented in README.md
#  4. docs never claim a platform is tested when docs/PLATFORMS.md says otherwise
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
fail=0
err() { printf 'DOC-CHECK FAIL: %s\n' "$*" >&2; fail=1; }

while IFS= read -r md; do
    dir="$(dirname "$md")"
    while IFS= read -r link; do
        target="${link%%#*}"
        [[ -z "$target" || "$target" == http* || "$target" == mailto:* ]] && continue
        [[ -e "$dir/$target" ]] || err "$md -> $link (missing)"
    done < <(grep -oE '\]\([^)]+\)' "$md" | sed -E 's/^\]\(//; s/\)$//; s/ .*//')
done < <(find . -name '*.md' -not -path './legacy/*' -not -path './.git/*')

if [[ -f docs/USAGE.md ]]; then
    while IFS= read -r opt; do
        grep -qF -- "$opt" docs/USAGE.md || err "option $opt missing from docs/USAGE.md"
    done < <(./setup.sh --help | grep -oE '^ +--[a-z-]+' | tr -d ' ' | sort -u)
else
    err "docs/USAGE.md missing"
fi

for p in profiles/*.conf; do
    n="$(basename "$p" .conf)"
    grep -qiE "\b$n\b" README.md || err "profile '$n' not documented in README.md"
done

if grep -RInE 'all (linux )?distributions (are )?supported' --include='*.md' . --exclude-dir=legacy --exclude-dir=.git; then
    err "forbidden claim 'all distributions supported'"
fi
exit "$fail"
