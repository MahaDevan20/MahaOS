#!/usr/bin/env bash
# Runs inside the target chroot, LAST. Remove every live-only artefact so the
# installed system contains no installer, no live user and no autologin.
set -euo pipefail

export LC_ALL=C

echo ":: [mahadevanos] removing live-only artefacts"

# 1. Live user and its passwordless sudo rule.
if id liveuser >/dev/null 2>&1; then
  userdel -r liveuser 2>/dev/null || userdel liveuser || true
fi
rm -f /etc/sudoers.d/10-liveuser
rm -f /etc/skel/README.live
rm -f /home/liveuser/README.live

# 2. Live autologin and the live SDDM drop-in.
rm -f /etc/sddm.conf.d/10-live-autologin.conf

# 3. Live shell leftovers.
rm -rf /root/.cache/hyprland /home/*/.cache/hyprland 2>/dev/null || true
rm -f /etc/xdg/autostart/*calamares*.desktop
rm -f /usr/share/applications/install-mahadevanos.desktop

# 4. archiso leftovers.
rm -rf /etc/calamares
rm -f /etc/mkinitcpio.d/archiso.preset
rm -rf /run/archiso /opt/archiso 2>/dev/null || true
rm -f /etc/systemd/system/*.wants/*archiso* 2>/dev/null || true
rm -f /usr/lib/systemd/system/archiso* 2>/dev/null || true

# 5. Installer packages (and ckbcomp, which only converts live keymaps).
for pkg in calamares-config calamares ckbcomp; do
  if pacman -Q "$pkg" >/dev/null 2>&1; then
    pacman -Rs --noconfirm "$pkg" 2>/dev/null || pacman -Rdd --noconfirm "$pkg" 2>/dev/null || true
  fi
done
rm -rf /usr/share/mahadevanos

# 6. Sanity guard: refuse to leave a passwordless-sudo live user behind.
if grep -rqs '^liveuser' /etc/passwd; then
  echo "ERROR: liveuser still present after cleanup" >&2
  exit 1
fi
if [[ -e /etc/sudoers.d/10-liveuser ]]; then
  echo "ERROR: live sudoers rule still present after cleanup" >&2
  exit 1
fi

echo ":: [mahadevanos] cleanup complete"
