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
