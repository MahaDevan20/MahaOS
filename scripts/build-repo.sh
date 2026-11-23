#!/usr/bin/env bash
# Build the packages that are not in the official Arch repos (calamares, ckbcomp,
# mahadevanos-branding, mahadevanos-settings, calamares-config) into repo/x86_64/
# using devtools clean chroots. Never builds as root.
#
# Local dependencies: a clean chroot only knows the official Arch mirrors, so a
# package that depends on another package of ours (calamares-config -> calamares)
# would not resolve. Any dependency of ours that is already built is injected
# into the throwaway working copy with `makechrootpkg -I`, for that build only.
# The host pacman.conf and the chroot's own configuration are never modified, and
# nothing carries over to the next build or to a recreated chroot.
#
# Debug symbol packages and makepkg's *-namcap.log / *-package.log files are not
# shipped: they stay out of repo/x86_64/ and out of the repository database.
#
# Usage: scripts/build-repo.sh [--force] [package ...]
#
# Without package names every PKGBUILD under packaging/ is handled. Naming one or
# more packages (directory names) rebuilds only those, which is what a changed
# PKGBUILD needs and avoids recompiling Calamares every time.
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ $EUID -eq 0 ]]; then
  # The normal path is "run as your user, devtools elevates itself". A host that
  # cannot prompt for a password (unattended build) can opt in explicitly; the
  # packages are still compiled by makepkg inside the clean chroot.
  [[ "${MAHADEVANOS_ALLOW_ROOT:-0}" == "1" ]] ||
    die "do not run this as root; devtools elevates via sudo itself (set MAHADEVANOS_ALLOW_ROOT=1 to override)"
  warn "running as root because MAHADEVANOS_ALLOW_ROOT=1"
fi
require makepkg repo-add

# Generated documentation is rebuilt from its source of truth before packaging:
# learning/shortcuts.md comes from configs/hypr/hyprland.lua, which the generator
# refuses to document incompletely (see scripts/gen-shortcuts.sh).
"$PROJECT_ROOT/scripts/gen-shortcuts.sh"

CHROOT_BUILD=""
for candidate in extra-x86_64-build core-x86_64-build; do
  if command -v "$candidate" >/dev/null 2>&1; then
    CHROOT_BUILD="$candidate"
    break
  fi
done
[[ -n "$CHROOT_BUILD" ]] || die "devtools not installed: need extra-x86_64-build (pacman -S devtools)"

force=0
only=()
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    -*) die "unknown option: $arg" ;;
    *) only+=("$arg") ;;
  esac
done

mkdir -p "$REPO_DIR/x86_64" "$LOG_DIR"
REPO_DB="$REPO_DIR/x86_64/mahadevanos-local.db.tar.zst"

# The package files that belong in the repository: *.pkg.tar.zst only, so
# makepkg's *-namcap.log and *-package.log files can never be picked up by the
# glob, and debug symbol packages are dropped.
shipped_packages() {
  local dir="$1" f base
  for f in "$dir"/*.pkg.tar.zst; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    case "$base" in
      *-debug-*) continue ;;
    esac
    printf '%s\n' "$f"
  done
}

# Names of the packages this run has already put in the repository. Used both to
# report the database and to inject local dependencies into the chroot.
repo_package_files() {
  find "$REPO_DIR/x86_64" -maxdepth 1 -type f -name '*.pkg.tar.zst' ! -name '*-debug-*' | sort
}

mapfile -t pkgs < <(find "$PROJECT_ROOT/packaging" -mindepth 1 -maxdepth 1 -type d | sort)
(( ${#pkgs[@]} )) || die "no PKGBUILDs found under packaging/"

if (( ${#only[@]} )); then
  selected=()
  for name in "${only[@]}"; do
    [[ -f "$PROJECT_ROOT/packaging/$name/PKGBUILD" ]] ||
      die "no packaging/$name/PKGBUILD"
    selected+=("$PROJECT_ROOT/packaging/$name")
  done
  pkgs=("${selected[@]}")
fi

for dir in "${pkgs[@]}"; do
  name="$(basename "$dir")"
  [[ -f "$dir/PKGBUILD" ]] || { warn "skipping $name (no PKGBUILD)"; continue; }

  if (( ! force )) && compgen -G "$REPO_DIR/x86_64/${name}-[0-9]*.pkg.tar.zst" >/dev/null; then
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

  # Inject the dependencies of ours that are already in the repository, so the
  # clean chroot can satisfy them without touching any pacman configuration.
  inject=()
  while read -r dep; do
    [[ -n "$dep" ]] || continue
    dep="${dep%%[<>=]*}"
    for pkgfile in "$REPO_DIR"/x86_64/"$dep"-[0-9]*.pkg.tar.zst; do
      [[ -f "$pkgfile" ]] || continue
      case "$(basename "$pkgfile")" in *-debug-*) continue ;; esac
      inject+=(-I "$pkgfile")
      log "injecting local dependency $dep into the chroot working copy"
    done
  done < <( cd "$dir" && makepkg --printsrcinfo 2>/dev/null | sed -n 's/^[[:space:]]*depends = //p' )

  log "building $name in a clean chroot with $CHROOT_BUILD"
  # archbuild only understands -h/-c/-r itself; every makechrootpkg option has to
  # be passed after its own `--`, and makepkg's options after a second one.
  ( cd "$dir" && "$CHROOT_BUILD" -- ${inject[@]+"${inject[@]}"} -- -c ) 2>&1 \
    | tee "$LOG_DIR/build-$name.log"

  mapfile -t built < <(shipped_packages "$dir")
  (( ${#built[@]} )) || die "chroot build produced no package for $name"

  for pkgfile in "${built[@]}"; do
    cp -v "$pkgfile" "$REPO_DIR/x86_64/"
    repo-add --remove --quiet "$REPO_DB" "$REPO_DIR/x86_64/$(basename "$pkgfile")"
  done

  # Never leave build artefacts (or a debug package) behind in the PKGBUILD dir.
  rm -f "$dir"/*.pkg.tar.zst "$dir"/*.tar.gz
  rm -f "$dir"/*-namcap.log "$dir"/*-package.log "$dir"/*-prepare.log "$dir"/*-build.log
  rm -f "$dir/$name-assets.tar.zst"
done

# Anything a previous run copied in that must not ship: debug symbols and the
# log files that an older glob could pick up. The database is rebuilt from the
# package list below, so excluded files cannot stay listed either.
rm -f "$REPO_DIR"/x86_64/*-debug-*.pkg.tar.zst "$REPO_DIR"/x86_64/*-namcap.log \
  "$REPO_DIR"/x86_64/*-package.log "$REPO_DIR"/x86_64/*-prepare.log \
  "$REPO_DIR"/x86_64/*-build.log

log "rebuilding local repository database from the shipped packages"
# Regenerate instead of updating, so the database lists exactly the packages that
# ship and a stale entry (for example a debug package from an earlier run) cannot
# survive in it.
rm -f "$REPO_DIR"/x86_64/mahadevanos-local.db* "$REPO_DIR"/x86_64/mahadevanos-local.files*
mapfile -t repo_pkgs < <(repo_package_files)
(( ${#repo_pkgs[@]} )) || die "no packages in $REPO_DIR/x86_64; nothing to add"
repo-add --remove --quiet "$REPO_DB" "${repo_pkgs[@]}" 2>&1 | tee -a "$LOG_DIR/repo-add.log"

log "local repo contents:"
find "$REPO_DIR/x86_64" -maxdepth 1 -type f -name '*.pkg.tar.zst' -printf '  %f\n' | sort

# Read the database exactly the way a client does: pacman finds repositories in
# a config and their sync databases under <dbpath>/sync/<repo>.db. Mirror the
# generated database into a throwaway dbpath instead of claiming the packages
# came from a real installation.
tmpdb="$BUILD_DIR/pacman-db"
rm -rf "$tmpdb"
mkdir -p "$tmpdb/sync"
ln -sf "$REPO_DB" "$tmpdb/sync/mahadevanos-local.db"
printf '[options]\nArchitecture = x86_64\nSigLevel = Never\n\n[mahadevanos-local]\nServer = file://%s/x86_64\n' \
  "$REPO_DIR" >"$tmpdb/pacman.conf"
log "pacman -Sl mahadevanos-local (from $REPO_DB):"
pacman -Sl --config "$tmpdb/pacman.conf" --dbpath "$tmpdb" mahadevanos-local ||
  warn "could not read the generated database with pacman -Sl"
