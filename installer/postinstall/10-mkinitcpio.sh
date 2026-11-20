#!/usr/bin/env bash
# Runs inside the target chroot during install (Calamares shellprocess).
# Restore a normal initramfs setup: the live image's archiso hooks are invalid
# on an installed system and would make it unbootable.
set -euo pipefail

export LC_ALL=C

echo ":: [mahadevanos] restoring /etc/mkinitcpio.conf"
cat >/etc/mkinitcpio.conf <<'EOF'
# Generated for the installed system by MahaDevan's OS post-install.
# btrfs is built into the module list so the root subvolume can be mounted
# before udev settles; sd-encrypt is unnecessary because LUKS1 is unlocked by GRUB.
MODULES=(btrfs)
BINARIES=()
FILES=()
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)
COMPRESSION="zstd"
EOF

# Remove the archiso presets the live image carries.
rm -f /etc/mkinitcpio.d/archiso.preset
for preset in /etc/mkinitcpio.d/linux.preset /etc/mkinitcpio.d/linux-lts.preset; do
  [[ -f "$preset" ]] || continue
  cat >"$preset" <<'EOF'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-KERNEL"
PRESETS=('default' 'fallback')
default_image="/boot/initramfs-KERNEL.img"
fallback_image="/boot/initramfs-KERNEL-fallback.img"
fallback_options="-S autodetect"
EOF
done

# Rewrite the kernel placeholder in each preset with its real kernel version.
if [[ -f /etc/mkinitcpio.d/linux.preset ]]; then
  sed -i "s|KERNEL|linux|g" /etc/mkinitcpio.d/linux.preset
fi
if [[ -f /etc/mkinitcpio.d/linux-lts.preset ]]; then
  sed -i "s|KERNEL|linux-lts|g" /etc/mkinitcpio.d/linux-lts.preset
fi

echo ":: [mahadevanos] regenerating initramfs"
mkinitcpio -P

echo ":: [mahadevanos] initramfs done"
