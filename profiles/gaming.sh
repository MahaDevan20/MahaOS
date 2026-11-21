#!/usr/bin/env bash
# Gaming profile: Steam/Proton, Lutris, GameMode, MangoHud, Wine.
# Requires [multilib] (enabled by the installer) for 32-bit libraries.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
  die "[multilib] is not enabled in /etc/pacman.conf; enable it first (Steam needs 32-bit libs)"
fi

install_profile "gaming (Steam, Lutris, GameMode, MangoHud, Wine)" \
  steam lutris gamemode lib32-gamemode mangohud lib32-mangohud \
  wine wine-mono wine-gecko winetricks \
  gamescope goverlay vulkan-tools
