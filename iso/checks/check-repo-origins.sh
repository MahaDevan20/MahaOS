#!/usr/bin/env bash
# Fail the build if any package in the ISO manifest came from a repository other
# than core/extra/multilib/mahadevanos-local (blueprint §6, §2 #16).
#
# Usage: iso/checks/check-repo-origins.sh <manifest.txt>
# The manifest is produced by scripts/build-iso.sh as "<repo>/<pkgname> <version>".
set -euo pipefail

manifest="${1:-}"
allowed_re='^(core|extra|multilib|mahadevanos-local)/'
bad_re='(cachyos|garuda|chaotic|archlinuxcn|endeavouros|manjaro|[a-z0-9]+-v[234])'

if [[ -z "$manifest" || ! -s "$manifest" ]]; then
  echo "check-repo-origins: manifest missing or empty: ${manifest:-<none>}" >&2
  exit 2
fi

fail=0
count=0
while IFS= read -r line; do
  [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
  count=$((count + 1))
  if [[ ! "$line" =~ $allowed_re ]]; then
    echo "DISALLOWED ORIGIN: $line" >&2
    fail=1
  elif [[ "$line" =~ $bad_re ]]; then
    echo "FOREIGN PACKAGE NAME: $line" >&2
    fail=1
  fi
done <"$manifest"

if (( count == 0 )); then
  echo "check-repo-origins: no package lines found in $manifest" >&2
  exit 2
fi

if (( fail != 0 )); then
  echo "check-repo-origins: FAILED ($count packages inspected)" >&2
  exit 1
fi

echo "check-repo-origins: OK ($count packages, all from Arch or mahadevanos-local)"
