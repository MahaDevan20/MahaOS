#!/usr/bin/env bash
# Runs inside the built airootfs chroot by mkarchiso, *after* the packages are
# installed. That timing is the whole point: /etc/os-release and
# /usr/lib/os-release are owned by the `filesystem` package, so shipping them
# from airootfs/ (copied before pacstrap) is a pacman file conflict. Writing them
# here cannot conflict with anything.
set -euo pipefail

echo ":: [mahadevanos] branding the live system"
defaults=/usr/share/mahadevanos/defaults

if [[ ! -f "$defaults/os-release" ]]; then
  echo ":: [mahadevanos] ERROR: $defaults/os-release missing (mahadevanos-branding not installed?)" >&2
  exit 1
fi

# /etc takes precedence over /usr/lib in the os-release lookup order, so the
# distribution identity comes from here while the Arch file stays untouched.
rm -f /etc/os-release
install -m644 "$defaults/os-release" /etc/os-release

echo ":: [mahadevanos] live system branded"

# snap-pac's pacman hooks are AbortOnFail, and the live root is a read-only
# squashfs under an overlay: a pacman transaction in the live session would ask
# snapper to snapshot a root it cannot snapshot, the hook would fail, and pacman
# would abort. Keep snap-pac inert in the live session only. The installer
# rewrites this file for the target (installer/postinstall/40-snapshots.sh, which
# runs before 99-cleanup removes the installer packages), where / is the real @
# subvolume.
{
  echo '# Live session only: the squashfs root cannot be snapshotted.'
  echo '# The installed system replaces this file (postinstall/40-snapshots.sh).'
  echo '[root]'
  echo 'snapshot = False'
} >/etc/snap-pac.ini
chmod 644 /etc/snap-pac.ini
echo ":: [mahadevanos] snap-pac disabled in the live session"

# mkarchiso deletes the contents of /boot right before it builds the squashfs
# (_cleanup_pacstrap_dir), so the airootfs the installer unpacks onto the target
# has no kernel. The kernel packages are installed and their modules are in
# /usr/lib/modules, so only the /boot images are missing: keep a copy outside
# /boot for /usr/share/mahadevanos/postinstall/10-mkinitcpio.sh to restore.
install -d -m 755 /usr/lib/mahadevanos/kernel
for vmlinuz in /boot/vmlinuz-*; do
  [[ -e "$vmlinuz" ]] || continue
  install -m 644 "$vmlinuz" /usr/lib/mahadevanos/kernel/
  echo ":: [mahadevanos] kept $(basename "$vmlinuz") for the installed system"
done

# The live account gets the same practice folder a new user gets from /etc/skel
# (mahadevanos-learning). Only that folder: liveuser's own hyprland.lua must not
# be replaced by the skel copy, which does not start the installer.
if [[ -d /etc/skel/practice ]]; then
  rm -rf /home/liveuser/practice
  cp -a /etc/skel/practice /home/liveuser/practice
  chown -R 1000:1000 /home/liveuser/practice
  echo ":: [mahadevanos] practice files placed in /home/liveuser/practice"
fi
