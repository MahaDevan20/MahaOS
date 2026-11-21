#!/usr/bin/env bash
# Pre-unpackfs guard for the Calamares install (module instance `preflight`).
#
# Runs on the live system with the target root as $1 (Calamares substitutes
# ${ROOT} with its root mount point). Fails the install if "/" is not a real
# block-device mount, so unpackfs can never fill the installer's tmpfs again.
#
# Without an argument it falls back to the newest /tmp/calamares-root-* so it
# can also be run by hand while debugging.
set -euo pipefail
export LC_ALL=C

root="${1:-}"
if [[ -z "$root" ]]; then
    root="$(find /tmp -maxdepth 1 -type d -name 'calamares-root-*' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -1 | cut -d' ' -f2-)"
fi

fail() {
    echo "PREFLIGHT FAILED: $*" >&2
    echo "PREFLIGHT FAILED: refusing to run unpackfs; the target root is not mounted on a disk." >&2
    exit 1
}

[[ -n "$root" && -d "$root" ]] || fail "no target root mount point (got '${root}')"

source_spec="$(findmnt -n -o SOURCE -T "$root")" || fail "findmnt cannot resolve '${root}'"
fstype="$(findmnt -n -o FSTYPE -T "$root")"
target="$(findmnt -n -o TARGET -T "$root")"

echo "PREFLIGHT: target root:   $root"
echo "PREFLIGHT: source:        $source_spec"
echo "PREFLIGHT: filesystem:    $fstype"
echo "PREFLIGHT: mount point:   $target"

case "$fstype" in
    tmpfs | ramfs | overlay | squashfs | "")
        fail "/ is on '${fstype}', not on a disk filesystem (the root partition was not mounted)"
        ;;
esac

# btrfs reports "/dev/vda2[/@]": strip the subvolume suffix to test the device.
device="${source_spec%%\[*}"
device="${device%% *}"
[[ -b "$device" ]] || fail "/ is backed by '${device}', which is not a block device"

# The target must itself be the mount point, not just a directory inside /tmp.
[[ "$target" == "$root" || "$target" == "$root/" ]] \
    || fail "'${root}' is not a mount point; findmnt reports '${target}'"

echo "PREFLIGHT: ok: / is ${fstype} on ${device}"
