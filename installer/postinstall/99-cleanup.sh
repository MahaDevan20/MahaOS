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

# 3. Live shell leftovers, including the live-only Hyprland config that
#    auto-starts the installer and the installer launcher itself.
rm -rf /root/.cache/hyprland /home/*/.cache/hyprland 2>/dev/null || true
rm -f /etc/xdg/autostart/*calamares*.desktop
rm -f /etc/xdg/autostart/mahadevanos-install-prompt.desktop
rm -f /usr/share/applications/install-mahadevanos.desktop
rm -f /usr/local/bin/mahadevanos-installer
rm -rf /home/liveuser

# 3b. The live-only systemd unit that gives liveuser its groups, its enablement
#     symlink, and the live-session marker it keys on. All three are copied into
#     the target by unpackfs and otherwise run (and fail) on first boot.
rm -f /etc/systemd/system/mahadevanos-liveuser.service
rm -f /etc/systemd/system/multi-user.target.wants/mahadevanos-liveuser.service
rm -f /etc/mahadevanos-live

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
# /usr/lib/mahadevanos/kernel holds the live copy of the kernel images, which
# 10-mkinitcpio.sh has already restored into /boot by now.
rm -rf /usr/share/mahadevanos /usr/lib/mahadevanos

# 6. Sanity guard: every live-only item must be gone, or the install fails.
failed=0
check_absent() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "ERROR: $path still present after cleanup" >&2
    failed=1
  fi
}

echo ":: [mahadevanos] verifying the target has no live-only artefacts"

# Live user: no passwd entry, no home directory.
if grep -q '^liveuser:' /etc/passwd 2>/dev/null; then
  echo "ERROR: liveuser still present in /etc/passwd after cleanup" >&2
  failed=1
fi
check_absent /home/liveuser
check_absent /etc/sudoers.d/10-liveuser
check_absent /etc/systemd/system/mahadevanos-liveuser.service
check_absent /etc/systemd/system/multi-user.target.wants/mahadevanos-liveuser.service
check_absent /etc/mahadevanos-live
# Only the LIVE unit is forbidden here: mahadevanos-settings ships the permanent
# mahadevanos-snapshot-guard.service/.timer, which must survive the cleanup.
if systemctl --root=/ list-unit-files 'mahadevanos-liveuser*' 2>/dev/null |
   grep -q 'mahadevanos-liveuser'; then
  echo "ERROR: the MahaDevan's OS live unit is still installed" >&2
  systemctl --root=/ list-unit-files 'mahadevanos-liveuser*' >&2 || true
  failed=1
fi

# No passwordless sudo rule for anything, live or not.
if grep -rqsE '^[^#]*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null; then
  echo "ERROR: a NOPASSWD sudo rule still exists after cleanup" >&2
  grep -rnE '^[^#]*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null >&2 || true
  failed=1
fi

# No autologin for any display manager.
if grep -rqsE '^\s*AutoLogin|^\s*User\s*=' /etc/sddm.conf /etc/sddm.conf.d 2>/dev/null; then
  echo "ERROR: SDDM still has an autologin user configured" >&2
  grep -rnE '^\s*AutoLogin|^\s*User\s*=' /etc/sddm.conf /etc/sddm.conf.d 2>/dev/null >&2 || true
  failed=1
fi
check_absent /etc/sddm.conf.d/10-live-autologin.conf

# No installer: no binary, no launcher, no desktop entry, no Calamares config.
check_absent /usr/bin/calamares
check_absent /usr/local/bin/mahadevanos-installer
check_absent /etc/calamares
check_absent /usr/share/applications/install-mahadevanos.desktop
if compgen -G '/etc/xdg/autostart/*calamares*' >/dev/null; then
  echo "ERROR: a Calamares autostart entry still exists after cleanup" >&2
  failed=1
fi

# No live Hyprland config: neither the liveuser copy nor anything that starts
# the installer from /etc/skel or /etc/xdg.
check_absent /home/liveuser/.config/hypr/hyprland.lua
if grep -rqsE 'mahadevanos-installer|calamares' /etc/skel /etc/xdg/hypr 2>/dev/null; then
  echo "ERROR: a Hyprland/skel config still references the installer" >&2
  grep -rlnE 'mahadevanos-installer|calamares' /etc/skel /etc/xdg/hypr 2>/dev/null >&2 || true
  failed=1
fi

# The installed system keeps the normal (non-live) Hyprland Lua config.
if [[ ! -f /etc/xdg/hypr/hyprland.lua ]]; then
  echo "ERROR: /etc/xdg/hypr/hyprland.lua is missing from the installed system" >&2
  failed=1
fi

if (( failed )); then
  echo "ERROR: live-only artefacts survived the cleanup; aborting the install" >&2
  exit 1
fi

# 7. snap-pac is switched on last. 40-snapshots.sh leaves it off because its
#    pacman hook is AbortOnFail and snapper cannot reach its daemon from this
#    chroot, so a snapshot attempt here would abort the package removals above.
#    This is the last postinstall script: the installed system gets snapshots.
if [[ -f /etc/snap-pac.ini ]]; then
  sed -i 's/^snapshot = False$/snapshot = True/' /etc/snap-pac.ini
  if grep -qx 'snapshot = True' /etc/snap-pac.ini; then
    echo ":: [mahadevanos] snap-pac enabled for the installed system"
  else
    echo "ERROR: snap-pac is still disabled in /etc/snap-pac.ini" >&2
    exit 1
  fi
fi

echo ":: [mahadevanos] cleanup complete, no live-only artefacts remain"
