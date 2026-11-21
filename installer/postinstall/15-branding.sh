#!/usr/bin/env bash
# Runs inside the target chroot, before the bootloader module runs grub-mkconfig.
# Applies the branding defaults that no package may own directly: /etc/default/grub
# belongs to grub, /etc/ufw/* and /etc/default/ufw to ufw, and /etc/os-release to
# filesystem. They ship in /usr/share/mahadevanos/defaults instead.
set -euo pipefail

export LC_ALL=C

defaults=/usr/share/mahadevanos/defaults

echo ":: [mahadevanos] applying branding defaults"

if [[ ! -d "$defaults" ]]; then
  echo ":: [mahadevanos] WARNING: $defaults missing; skipping branding defaults" >&2
  exit 0
fi

if [[ -f "$defaults/os-release" ]]; then
  rm -f /etc/os-release
  install -m644 "$defaults/os-release" /etc/os-release
fi

# Written before grub-mkconfig so the theme and snapshot menu are in the first
# generated grub.cfg.
if [[ -f "$defaults/grub-defaults" ]]; then
  install -m644 "$defaults/grub-defaults" /etc/default/grub
fi

if [[ -f "$defaults/default-ufw" ]]; then
  install -Dm644 "$defaults/default-ufw" /etc/default/ufw
fi

if [[ -f "$defaults/ufw.conf" ]]; then
  install -Dm644 "$defaults/ufw.conf" /etc/ufw/ufw.conf
fi

echo ":: [mahadevanos] branding defaults applied"
