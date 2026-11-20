#!/usr/bin/env bash
# Runs inside the target chroot. The live keyring state is not copied to disk, so
# the installed system needs its own initialised, populated keyring.
set -euo pipefail

export LC_ALL=C

echo ":: [mahadevanos] initialising pacman keyring"
pacman-key --init
pacman-key --populate archlinux

# Refresh the trust database so the first `pacman -Syu` does not stall on keys.
pacman-key --updatedb || true

echo ":: [mahadevanos] keyring ready"
