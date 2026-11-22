#!/usr/bin/env bash
# Runs inside the target chroot during install (Calamares shellprocess).
# Restore a normal initramfs setup: the live image's archiso hooks are invalid
# on an installed system and would make it unbootable.
set -euo pipefail

export LC_ALL=C

# GRUB 2.16 cannot reliably read a zstd-compressed file off btrfs: the
# 2026-11-22 install failed with
#   error: loader/efi/linux.c:grub_cmd_linux:700:premature end of file
#   /@/boot/vmlinuz-linux-lts
# even though the file was complete on disk. btrfs compresses /boot because it
# inherits `compress=zstd:1` from the root subvolume, and GRUB's btrfs driver
# returns a short read for some compressed extent layouts (the same class of
# failure as the documented amd-ucode.img "premature end of file" reports).
# `chattr +C` (NOCOW, which also disables compression) on /boot makes every file
# written below it uncompressed, i.e. a plain extent map GRUB reads byte for byte.
# It must be set *before* the kernels and initramfs are written.
echo ":: [mahadevanos] disabling btrfs compression on /boot (GRUB cannot read zstd-compressed kernels)"
boot_fs="$(findmnt -no FSTYPE -T /boot 2>/dev/null || true)"
[[ -n "$boot_fs" ]] || boot_fs="$(findmnt -no FSTYPE -T / 2>/dev/null || echo unknown)"
if [[ "$boot_fs" == "btrfs" ]]; then
  chattr +C /boot 2>/dev/null || echo ":: [mahadevanos] WARNING: chattr +C /boot failed; GRUB may not read the kernel" >&2
else
  echo ":: [mahadevanos] /boot is on ${boot_fs}; no btrfs compression to disable"
fi

# The live squashfs has an empty /boot (mkarchiso deletes it before building the
# image), so the unpacked target has kernel modules but no kernel images.
#
# Authoritative source is the kernel package itself: both linux and linux-lts
# install /usr/lib/modules/<kver>/vmlinuz, which mkarchiso keeps. The copy that
# customize_airootfs.sh stashes in /usr/lib/mahadevanos/kernel is only a
# fallback, so a missing stash can no longer leave an empty /boot behind.
kernel_source() {
  local kernel="$1" path
  path="$(pacman -Ql "$kernel" 2>/dev/null | awk '$2 ~ /^\/usr\/lib\/modules\/.*\/vmlinuz$/ { print $2; exit }')"
  if [[ -n "$path" && -s "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  fi
  path="/usr/lib/mahadevanos/kernel/vmlinuz-$kernel"
  if [[ -s "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  fi
  return 1
}

echo ":: [mahadevanos] restoring kernel images"
for kernel in linux linux-lts; do
  # Remove any copy written before compression was disabled, then copy again so
  # the file on disk is definitely uncompressed.
  rm -f "/boot/vmlinuz-$kernel"
  if ! src="$(kernel_source "$kernel")"; then
    echo ":: [mahadevanos] ERROR: no vmlinuz for $kernel (checked /usr/lib/modules/*/vmlinuz and the live stash)" >&2
    exit 1
  fi
  install -Dm644 "$src" "/boot/vmlinuz-$kernel"
  size="$(stat -c %s "/boot/vmlinuz-$kernel")"
  if (( size < 5242880 )); then
    echo ":: [mahadevanos] ERROR: /boot/vmlinuz-$kernel is only ${size} bytes (source $src)" >&2
    exit 1
  fi
  echo ":: [mahadevanos] /boot/vmlinuz-$kernel ${size} bytes from $src"
done

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
