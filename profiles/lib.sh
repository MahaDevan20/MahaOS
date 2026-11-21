#!/usr/bin/env bash
# Shared logic for the post-install profiles. Sourced, never executed.
# shellcheck shell=bash

set -euo pipefail

PROFILE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROFILE_ROOT

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo: sudo $0"

# Take a snapshot before touching the system, so a bad profile is reversible from
# the GRUB snapshot menu. Not fatal if snapper is unavailable, but say so loudly.
snapshot_pre() {
  local label="$1"
  if command -v snapper >/dev/null 2>&1; then
    log "taking a pre-change snapshot ($label)"
    snapper --no-dbus -c root create --description "profile: $label" --cleanup-algorithm number >/dev/null || \
      warn "snapshot failed; continuing WITHOUT a rollback point"
  else
    warn "snapper not installed; no snapshot taken"
  fi
}

update_db() {
  log "syncing package databases"
  pacman -Sy --noconfirm
}

# install_profile <description> <package...>
install_profile() {
  local description="$1"; shift
  (( $# )) || die "no packages listed"

  echo
  echo "This will install:"
  printf '  - %s\n' "$@"
  echo "Profile: $description"
  echo
  read -r -p "Continue? [y/N] " reply
  [[ "${reply,,}" == "y" ]] || { echo "Cancelled."; exit 0; }

  snapshot_pre "$description"
  update_db
  pacman -S --needed --noconfirm "$@"
  log "done: $description"
}
