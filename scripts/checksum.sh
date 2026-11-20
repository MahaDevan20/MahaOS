#!/usr/bin/env bash
# Generate or verify ISO checksums.
#   scripts/checksum.sh                # (re)generate sums for out/*.iso
#   scripts/checksum.sh --verify-only  # verify existing sums, fail on mismatch
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

mode="${1:-generate}"

mapfile -t isos < <(find "$OUT_DIR" -maxdepth 1 -name '*.iso' -type f | sort)
(( ${#isos[@]} )) || die "no ISO found in $OUT_DIR; run scripts/build-iso.sh first"

case "$mode" in
  generate)
    for iso in "${isos[@]}"; do
      ( cd "$OUT_DIR" && sha256sum "$(basename "$iso")" >"$(basename "$iso").sha256" )
      manifest="${iso}.manifest.txt"
      [[ -f "$manifest" ]] && ( cd "$OUT_DIR" && sha256sum "$(basename "$manifest")" >>"$(basename "$iso").sha256" )
      log "wrote $(basename "$iso").sha256"
    done
    ;;
  --verify-only)
    rc=0
    for iso in "${isos[@]}"; do
      sums="${iso}.sha256"
      [[ -f "$sums" ]] || { warn "missing $sums"; rc=1; continue; }
      log "verifying $(basename "$iso")"
      ( cd "$OUT_DIR" && sha256sum -c "$(basename "$sums")" ) || rc=1
    done
    exit "$rc"
    ;;
  *)
    die "usage: $0 [--verify-only]"
    ;;
esac
