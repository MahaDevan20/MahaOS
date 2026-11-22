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

require pacman sudo sha256sum awk bsdtar
command -v mkarchiso >/dev/null 2>&1 || die "mkarchiso missing: pacman -S archiso"

# Two supported ways to build: as your normal user (the script elevates with
# sudo itself), or as root with MAHADEVANOS_ALLOW_ROOT=1 when no password prompt
# is possible. mkarchiso requires root either way.
if [[ $EUID -eq 0 ]]; then
  [[ "${MAHADEVANOS_ALLOW_ROOT:-0}" == "1" ]] ||
    die "run as your normal user (the script calls sudo mkarchiso itself), or set MAHADEVANOS_ALLOW_ROOT=1 when already root"
  warn "running as root because MAHADEVANOS_ALLOW_ROOT=1"
  SUDO=()
else
  SUDO=(sudo)
fi

WORK_PROFILE="$BUILD_DIR/profile"
WORK_DIR="$BUILD_DIR/work"
BUILD_LOG="$OUT_DIR/build.log"

pinned="$(pinned_date)"
label="$(iso_label)"

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"

# mkarchiso names the image after iso_version in profiledef.sh (%Y.%m.%d), so the
# expected filename has to use the same format, not the ISO_DATE compact form.
iso_version="$(date --date="@${SOURCE_DATE_EPOCH}" +%Y.%m.%d)"
iso_file="$OUT_DIR/mahadevanos-${iso_version}-x86_64.iso"

log "pinned Arch Linux Archive date: $pinned"
log "ISO label: $label"

# --- 1. Package list -------------------------------------------------------
"$PROJECT_ROOT/scripts/generate-package-list.sh"

# --- 2. Working copy of the profile ---------------------------------------
log "preparing working profile in $WORK_PROFILE"
rm -rf "$WORK_PROFILE"
mkdir -p "$BUILD_DIR"
cp -a "$PROFILE_SRC" "$WORK_PROFILE"

# Rewrite the local repo server path so the build works from any checkout, and
# substitute the archive date: pacman expands only $repo and $arch, so a pinned
# date has to be written into the file itself.
repo_abs="$REPO_DIR"
sed -i "s|^Server = file://.*|Server = file://${repo_abs}/\$arch|" "$WORK_PROFILE/pacman.conf"
sed -i "s|@PINNED_DATE@|${pinned}|g" "$WORK_PROFILE/pacman.conf"
grep -q "file://${repo_abs}/" "$WORK_PROFILE/pacman.conf" ||
  die "failed to rewrite the local repo server in the working pacman.conf"
if grep -q '@PINNED_DATE@' "$WORK_PROFILE/pacman.conf"; then
  die "unresolved @PINNED_DATE@ placeholder remains in the working pacman.conf"
fi

# Resolve the ISO label placeholders everywhere in the working copy, not only in
# the boot entries: loader.conf mentions the placeholder in a comment, and the
# check below must not trip over a file that was never rewritten.
grep -rlZ --binary-files=without-match '@ISO_LABEL@' "$WORK_PROFILE" 2>/dev/null |
  xargs -0 -r sed -i "s|@ISO_LABEL@|${label}|g"
if grep -rqs '@ISO_LABEL@' "$WORK_PROFILE"; then
  die "unresolved @ISO_LABEL@ placeholder remains in the working profile"
fi

# --- 3. Build --------------------------------------------------------------
# Start from scratch: a failed run leaves a half-populated work directory that
# mkarchiso would otherwise resume from. Package archives stay cached on the host.
# mkarchiso creates it as root, so it can only be removed with sudo; the path is
# checked first so this can never delete anything else.
[[ "$WORK_DIR" == "$BUILD_DIR/work" && "$BUILD_DIR" == "$PROJECT_ROOT/build" ]] ||
  die "refusing to remove unexpected work directory: $WORK_DIR"
if [[ -d "$WORK_DIR" ]]; then
  log "clearing previous work directory $WORK_DIR"
  "${SUDO[@]}" rm -rf -- "$WORK_DIR" || die "could not clear $WORK_DIR"
fi

log "starting mkarchiso (log: $BUILD_LOG)"
set +e
"${SUDO[@]}" mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$WORK_PROFILE" 2>&1 | tee "$BUILD_LOG"
status="${PIPESTATUS[0]}"
set -e
(( status == 0 )) || die "mkarchiso failed (exit $status); see $BUILD_LOG"

[[ -f "$iso_file" ]] || die "mkarchiso reported success but $iso_file is missing"

# --- 4. Manifest -----------------------------------------------------------
log "generating package manifest"
manifest="$iso_file.manifest.txt"
airootfs="$WORK_DIR/x86_64/airootfs"

[[ -d "$airootfs/var/lib/pacman/local" ]] ||
  die "no pacman database in the built airootfs ($airootfs/var/lib/pacman/local)"

mapfile -t installed < <(pacman -Q --root "$airootfs" 2>/dev/null | awk 'NF >= 2 { print $1, $2 }')
(( ${#installed[@]} )) || die "the built airootfs reports no installed packages"

# The image carries no sync databases (pacman removes them during install), so an
# origin cannot be read from inside the airootfs. It is resolved from the
# databases the build used instead: a package name lives in exactly one of
# core/extra/multilib, and our own packages come from repo/x86_64.
declare -A origin=()
for db in core extra multilib; do
  while read -r repo name _; do
    [[ -n "${name:-}" ]] || continue
    [[ "$repo" == "$db" ]] || continue
    origin["$name"]="$repo"
  done < <(pacman -Sl "$db" 2>/dev/null || true)
done

for pkgfile in "$REPO_DIR"/x86_64/*.pkg.tar.zst; do
  [[ -e "$pkgfile" ]] || continue
  case "$(basename "$pkgfile")" in *-debug-*) continue ;; esac
  name="$(bsdtar -xOf "$pkgfile" .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p' | head -1 || true)"
  [[ -n "$name" ]] || continue
  origin["$name"]="mahadevanos-local"
done

unresolved=()
{
  echo "# <repo>/<package> <version> — generated from the built airootfs"
  for entry in "${installed[@]}"; do
    name="${entry%% *}"
    ver="${entry#* }"
    if [[ -n "${origin[$name]:-}" ]]; then
      printf '%s/%s %s\n' "${origin[$name]}" "$name" "$ver"
    else
      unresolved+=("$name")
    fi
  done
} >"$manifest.unsorted"

# Keep the manifest in a stable order.
{ head -1 "$manifest.unsorted"; tail -n +2 "$manifest.unsorted" | sort -u; } >"$manifest"
rm -f "$manifest.unsorted"

if (( ${#unresolved[@]} )); then
  die "these installed packages belong to no known repository (core/extra/multilib/mahadevanos-local):
     ${unresolved[*]}
     Set MAHADEVANOS_SKIP_ORIGIN_CHECK=1 only after verifying them by hand."
fi

log "all ${#installed[@]} installed packages resolved to a known repository"
log "checking package origins"
"$PROJECT_ROOT/iso/checks/check-repo-origins.sh" "$manifest"

# --- 5. Checksum -----------------------------------------------------------
log "writing checksum"
( cd "$OUT_DIR" && sha256sum "$(basename "$iso_file")" >"$(basename "$iso_file").sha256" )
sha256sum "$manifest" >>"$iso_file.sha256"

size="$(du -h "$iso_file" | cut -f1)"
log "done: $iso_file ($size, pinned $pinned, label $label)"
printf '    manifest lines: %s\n' "$(grep -c . "$manifest" || true)"
