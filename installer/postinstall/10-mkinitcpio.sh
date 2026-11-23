#!/usr/bin/env bash
# Runs inside the target chroot during install (Calamares shellprocess).
# Restore a normal initramfs setup: the live image's archiso hooks are invalid
# on an installed system and would make it unbootable.
set -euo pipefail

export LC_ALL=C

# GRUB 2.16's btrfs driver cannot read the final, partial block of a file: with
# both a zstd-compressed and a nodatacow /boot it returns
#   error: loader/efi/linux.c:grub_cmd_linux:700:premature end of file
#   /@/boot/vmlinuz-linux
# although the file is complete on disk. Measured on 2026-11-22 with the grub
# 2:2.16-1 that ships here: `grub-fstest DEV cp /@/boot/vmlinuz-linux out`
# returned 17,244,160 of 17,244,672 bytes (the last 512 bytes live in a btrfs
# tail extent that GRUB skips), while a copy padded to a whole 4096-byte block
# ("last,eof" extent) was read completely. Every file in /boot is therefore
# padded to a 4096-byte multiple at the end of this script; the kernel's EFI stub
# and the cpio reader stop at their own declared lengths, so trailing zeros are
# ignored.
# `chattr +C` (NOCOW, which also disables compression) keeps /boot a plain extent
# map; it must be set *before* the kernels and initramfs are written.
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

# GRUB reads files in whole blocks and skips a btrfs tail extent (see the note at
# the top): pad every /boot file to a 4096-byte boundary so its last extent is a
# normal "last,eof" block that GRUB reads to the end.
pad_to_block() {
  local file="$1" size rem pad
  [[ -s "$file" ]] || return 0
  size="$(stat -c %s "$file")"
  rem=$(( size % 4096 ))
  (( rem == 0 )) && return 0
  pad=$(( 4096 - rem ))
  head -c "$pad" /dev/zero >>"$file"
  sync
  echo ":: [mahadevanos] padded $file by $pad bytes to a 4096-byte boundary"
}

echo ":: [mahadevanos] aligning /boot files for GRUB's block reader"
for file in /boot/vmlinuz-* /boot/initramfs-*.img; do
  [[ -f "$file" ]] || continue
  pad_to_block "$file"
done

for kernel in linux linux-lts; do
  for file in "/boot/vmlinuz-$kernel" "/boot/initramfs-$kernel.img"; do
    [[ -f "$file" ]] || continue
    size="$(stat -c %s "$file")"
    if (( size % 4096 != 0 )); then
      echo ":: [mahadevanos] ERROR: $file is $size bytes, not a multiple of 4096; GRUB would read it short" >&2
      exit 1
    fi
    echo ":: [mahadevanos] $file $size bytes (aligned for GRUB)"
  done
done

echo ":: [mahadevanos] /boot is ready for GRUB"
