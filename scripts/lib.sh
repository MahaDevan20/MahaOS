#!/usr/bin/env bash
# Shared helpers for the MahaDevan's OS scripts. Source it, never execute it.
# shellcheck shell=bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

BUILD_DIR="$PROJECT_ROOT/build"
OUT_DIR="$PROJECT_ROOT/out"
LOG_DIR="$BUILD_DIR/logs"
PROFILE_SRC="$PROJECT_ROOT/iso/profile"
REPO_DIR="$PROJECT_ROOT/repo"
ISO_DATE="${ISO_DATE:-$(date +%Y%m%d)}"

mkdir -p "$BUILD_DIR" "$OUT_DIR" "$LOG_DIR" "$REPO_DIR/x86_64"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} )); then
    die "missing required command(s): ${missing[*]}"
  fi
}

# Compute the ISO label the same way profiledef.sh does: MAHADEVANOS_YYYYMM.
iso_label() {
  local epoch="${SOURCE_DATE_EPOCH:-$(date +%s)}"
  printf 'MAHADEVANOS_%s' "$(date --date="@$epoch" +%Y%m)"
}

pinned_date() {
  local f="$PROFILE_SRC/PINNED_DATE"
  [[ -f "$f" ]] || die "missing $f"
  tr -d '\n[:space:]' <"$f"
}
