#!/usr/bin/env bash
# Build the packages that are not in the official Arch repos (calamares, ckbcomp,
# mahadevanos-branding, mahadevanos-settings, calamares-config) into repo/x86_64/
# using devtools clean chroots. Never builds as root.
#
# Usage: scripts/build-repo.sh [--force]
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[[ $EUID -ne 0 ]] || die "do not run this as root; devtools elevates via sudo itself"
require makepkg repo-add

CHROOT_BUILD=""
for candidate in extra-x86_64-build core-x86_64-build; do
  if command -v "$candidate" >/dev/null 2>&1; then
    CHROOT_BUILD="$candidate"
    break
  fi
done
[[ -n "$CHROOT_BUILD" ]] || die "devtools not installed: need extra-x86_64-build (pacman -S devtools)"

force=0
[[ "${1:-}" == "--force" ]] && force=1

mkdir -p "$REPO_DIR/x86_64" "$LOG_DIR"

# Build order matters: branding and settings are consumed by calamares-config.
mapfile -t pkgs < <(find "$PROJECT_ROOT/packaging" -mindepth 1 -maxdepth 1 -type d | sort)
(( ${#pkgs[@]} )) || die "no PKGBUILDs found under packaging/"

for dir in "${pkgs[@]}"; do
  name="$(basename "$dir")"
  [[ -f "$dir/PKGBUILD" ]] || { warn "skipping $name (no PKGBUILD)"; continue; }

  if (( ! force )) && compgen -G "$REPO_DIR/x86_64/${name}-[0-9]*.pkg.tar.*" >/dev/null; then
    log "$name already built (use --force to rebuild)"
    continue
  fi

  log "reviewing PKGBUILD for $name"
  # A PR/build must be able to see what will run. Print the sources line only.
  grep -E '^(pkgname|pkgver|source|sha256sums|md5sums)=' "$dir/PKGBUILD" || true

  # A clean chroot only sees the package directory, so bundle the referenced
  # repository paths into one local tarball. Never downloads anything.
  if [[ -f "$dir/SOURCES" ]]; then
    log "bundling sources from $dir/SOURCES"
    rm -f "$dir/$name-assets.tar.zst"
    ( cd "$PROJECT_ROOT" && tar --zstd -cf "$dir/$name-assets.tar.zst" -T "$dir/SOURCES" ) \
      || die "failed to bundle sources for $name"
  fi

  log "building $name in a clean chroot with $CHROOT_BUILD"
  ( cd "$dir" && "$CHROOT_BUILD" -- -c ) 2>&1 | tee "$LOG_DIR/build-$name.log"

  shopt -s nullglob
  built=("$dir"/*.pkg.tar.*)
  shopt -u nullglob
  (( ${#built[@]} )) || die "chroot build produced no package for $name"
  cp -v "${built[@]}" "$REPO_DIR/x86_64/"
  rm -f "${built[@]}"
  rm -f "$dir/$name-assets.tar.zst"
done

log "updating local repository database"
repo-add --remove --quiet "$REPO_DIR/x86_64/mahadevanos-local.db.tar.zst" \
  "$REPO_DIR"/x86_64/*.pkg.tar.zst 2>&1 | tee -a "$LOG_DIR/repo-add.log"

log "local repo contents:"
pacman -Sl --dbpath "$REPO_DIR/x86_64" mahadevanos-local 2>/dev/null || \
  ls -1 "$REPO_DIR/x86_64" | sed 's/^/  /'
