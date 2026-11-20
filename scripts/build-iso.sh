#!/usr/bin/env bash
# Build out/mahadevanos-<date>-x86_64.iso with mkarchiso.
#
# What this guarantees:
#   * Arch repositories pinned to iso/profile/PINNED_DATE (repeatable builds).
#   * Nothing from CachyOS/Garuda/*-v3 can enter the ISO (Arch-only pacman.conf).
#   * The local repo path is rewritten to this checkout, so builds are portable.
#   * @ISO_LABEL@ placeholders in the boot entries are resolved in a working copy;
#     the tracked profile is never mutated.
#   * A package manifest and a repo-origin check are produced before success.
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require pacman sudo sha256sum awk
command -v mkarchiso >/dev/null 2>&1 || die "mkarchiso missing: pacman -S archiso"

[[ $EUID -ne 0 ]] || die "run as your normal user; the script calls sudo mkarchiso itself"

WORK_PROFILE="$BUILD_DIR/profile"
WORK_DIR="$BUILD_DIR/work"
BUILD_LOG="$OUT_DIR/build.log"

pinned="$(pinned_date)"
label="$(iso_label)"
iso_version="$(date +%Y.%m.%d)"
iso_file="$OUT_DIR/mahadevanos-${ISO_DATE}-x86_64.iso"

export ARCHISO_PINNED_DATE="$pinned"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"

log "pinned Arch Linux Archive date: $pinned"
log "ISO label: $label"

# --- 1. Package list -------------------------------------------------------
"$PROJECT_ROOT/scripts/generate-package-list.sh"

# --- 2. Working copy of the profile ---------------------------------------
log "preparing working profile in $WORK_PROFILE"
rm -rf "$WORK_PROFILE"
mkdir -p "$BUILD_DIR"
cp -a "$PROFILE_SRC" "$WORK_PROFILE"

# Rewrite the local repo server path so the build works from any checkout.
repo_abs="$REPO_DIR"
sed -i "s|^Server = file://.*|Server = file://${repo_abs}/\$arch|" "$WORK_PROFILE/pacman.conf"
grep -q "file://${repo_abs}/" "$WORK_PROFILE/pacman.conf" ||
  die "failed to rewrite the local repo server in the working pacman.conf"

# Resolve the ISO label placeholders in the boot entries.
find "$WORK_PROFILE" -type f \( -name '*.conf' -path '*/entries/*' \) -print0 |
  xargs -0 -r sed -i "s|@ISO_LABEL@|${label}|g"
if grep -rqs '@ISO_LABEL@' "$WORK_PROFILE"; then
  die "unresolved @ISO_LABEL@ placeholder remains in the working profile"
fi

# --- 3. Build --------------------------------------------------------------
log "starting mkarchiso (log: $BUILD_LOG)"
set +e
sudo mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$WORK_PROFILE" 2>&1 | tee "$BUILD_LOG"
status="${PIPESTATUS[0]}"
set -e
(( status == 0 )) || die "mkarchiso failed (exit $status); see $BUILD_LOG"

[[ -f "$iso_file" ]] || die "mkarchiso reported success but $iso_file is missing"

# --- 4. Manifest -----------------------------------------------------------
log "generating package manifest"
manifest="$iso_file.manifest.txt"
airootfs="$WORK_DIR/x86_64/airootfs"

origins_ok=0
if [[ -d "$airootfs/var/lib/pacman" ]]; then
  mapfile -t installed < <(pacman -Q --root "$airootfs" 2>/dev/null || true)
  : >"$manifest"
  echo "# <repo>/<package> <version> — generated from the built airootfs" >>"$manifest"
  for db in core extra multilib mahadevanos-local; do
    while read -r repo pkg ver _; do
      for entry in "${installed[@]}"; do
        if [[ "$entry" == "$pkg $ver" ]]; then
          printf '%s/%s %s\n' "$repo" "$pkg" "$ver" >>"$manifest"
          break
        fi
      done
    done < <(pacman -Sl --root "$airootfs" "$db" 2>/dev/null || true)
  done
  # Keep the manifest in a stable order.
  { head -1 "$manifest"; tail -n +2 "$manifest" | sort -u; } >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
  if grep -qv '^#' "$manifest"; then
    origins_ok=1
  fi
fi

if (( origins_ok == 1 )); then
  log "checking package origins"
  "$PROJECT_ROOT/iso/checks/check-repo-origins.sh" "$manifest"
elif [[ "${MAHADEVANOS_SKIP_ORIGIN_CHECK:-0}" == "1" ]]; then
  warn "package origins could not be resolved; origin check SKIPPED by request"
  pacman -Q --root "$airootfs" >"$manifest" 2>/dev/null || true
else
  die "could not resolve package origins from $airootfs; refusing to call this build good.
     Set MAHADEVANOS_SKIP_ORIGIN_CHECK=1 only if you have verified the manifest by hand."
fi

# --- 5. Checksum -----------------------------------------------------------
log "writing checksum"
( cd "$OUT_DIR" && sha256sum "$(basename "$iso_file")" >"$(basename "$iso_file").sha256" )
sha256sum "$manifest" >>"$iso_file.sha256"

size="$(du -h "$iso_file" | cut -f1)"
log "done: $iso_file ($size, pinned $pinned, label $label)"
printf '    manifest lines: %s\n' "$(grep -c . "$manifest" || true)"
