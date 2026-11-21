#!/usr/bin/env bash
# Install rehearsal inside the live ISO, driven over the serial console.
#
# This is NOT the Calamares GUI: it performs the same work the installer's
# partition/mount/unpackfs/shellprocess/bootloader modules perform on /dev/vda,
# which is a qcow2 disk attached to the VM and nothing else. It exists so the
# install pipeline can be tested unattended.
#
# The layout, subvolume list and mount options are READ FROM THE SHIPPED
# CALAMARES CONFIG (/etc/calamares/modules/*.conf), not hardcoded, so a config
# regression such as the 2026-11-21 `fs:`/duplicate-ESP bug fails here:
#   - partitionLayout must contain exactly one entry (the Btrfs root); the ESP
#     is created by Calamares' automatic prepend, sized by efi.recommendedSize
#     - `fs:` must not appear in partition.conf (ignored -> "unformatted" -> the
#     mount module skips the partition and "/" is never mounted)
#   - btrfsSubvolumes must be in mount.conf
#   - shellprocess must use `script:` (3.4.2 ignores `commands:`)
#
# Runs as root inside the live system (invoked with sudo by
# scripts/qemu-serial-run.py).
set -euo pipefail

export LC_ALL=C
DISK=/dev/vda
SFS=/run/archiso/bootmnt/arch/x86_64/airootfs.sfs
CONF=/etc/calamares/modules

step() { printf '\n=== %s ===\n' "$*"; }

step "confirm the only disk is the virtual one"
lsblk -o NAME,SIZE,MODEL,TYPE
[[ -b "$DISK" ]] || { echo "ERROR: $DISK missing"; exit 1; }
[[ -b /dev/sda ]] && { echo "ERROR: unexpected /dev/sda present; aborting"; exit 1; }
[[ -f "$SFS" ]] || { echo "ERROR: $SFS missing (live squashfs not mounted)"; exit 1; }

step "read the shipped Calamares layout (regression guards)"
for f in partition mount shellprocess; do
  [[ -f "$CONF/$f.conf" ]] || { echo "ERROR: $CONF/$f.conf missing"; exit 1; }
done

# Exactly one partitionLayout entry, and it is the Btrfs root.
layout_count=$(awk '/^partitionLayout:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/^[[:space:]]*-[[:space:]]*name:/{n++} END{print n+0}' "$CONF/partition.conf")
root_fs=$(awk '/^partitionLayout:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/filesystem:/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CONF/partition.conf")
root_mnt=$(awk '/^partitionLayout:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/mountPoint:/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CONF/partition.conf")
esp_mib=$(awk '/^efi:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/recommendedSize:/{gsub(/[^0-9]/,"",$2); print $2; exit}' "$CONF/partition.conf")
esp_mnt=$(awk '/^efi:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/mountPoint:/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CONF/partition.conf")

echo "partitionLayout entries: $layout_count"
echo "root: filesystem=$root_fs mountPoint=$root_mnt"
echo "efi:  mountPoint=$esp_mnt recommendedSize=${esp_mib}MiB"

[[ "$layout_count" == "1" ]] || { echo "FAIL: partitionLayout must have exactly one entry (the ESP is prepended by Calamares; a second ESP entry is the 2026-11-21 bug)"; exit 1; }
[[ "$root_fs" == "btrfs" ]] || { echo "FAIL: root entry filesystem must be btrfs (got '$root_fs'); use the 'filesystem:' key, not 'fs:'"; exit 1; }
[[ "$root_mnt" == "/" ]] || { echo "FAIL: root entry mountPoint must be / (got '$root_mnt')"; exit 1; }
[[ "$esp_mnt" == "/boot/efi" ]] || { echo "FAIL: efi.mountPoint must be /boot/efi (got '$esp_mnt')"; exit 1; }
[[ "$esp_mib" =~ ^[0-9]+$ ]] || { echo "FAIL: efi.recommendedSize not parsed (got '$esp_mib')"; exit 1; }
[[ "$esp_mib" -ge 1024 ]] || { echo "FAIL: efi.recommendedSize must be >= 1024MiB (got ${esp_mib}MiB)"; exit 1; }

# `fs:` is not a partitionLayout key; its presence is the original root cause.
if awk '/^partitionLayout:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/^[[:space:]]*fs:/{found=1} END{exit !found}' "$CONF/partition.conf"; then
  echo "FAIL: partitionLayout uses 'fs:'; Calamares only reads 'filesystem:'"
  exit 1
fi

grep -q '^btrfsSubvolumes:' "$CONF/mount.conf" || { echo "FAIL: btrfsSubvolumes missing from mount.conf"; exit 1; }
grep -q '^extraMounts:' "$CONF/mount.conf" || { echo "FAIL: extraMounts missing from mount.conf"; exit 1; }
grep -q '^script:' "$CONF/shellprocess.conf" || { echo "FAIL: shellprocess.conf must use 'script:' (3.4.2 ignores 'commands:')"; exit 1; }
if grep -q '^commands:' "$CONF/shellprocess.conf"; then
  echo "FAIL: shellprocess.conf still uses the ignored 'commands:' key"
  exit 1
fi
grep -q 'check-root-mount.sh' "$CONF/preflight.conf" || { echo "FAIL: preflight guard not configured"; exit 1; }
[[ -x /usr/share/mahadevanos/calamares/check-root-mount.sh ]] || { echo "FAIL: check-root-mount.sh missing or not executable"; exit 1; }
# Only real sequence entries count: comments in settings.conf mention both
# module names and must not influence the order check.
# Instance keys are "module@id"; a bare id is read as a module name and
# fails to load ("Module preflight@preflight not found").
pre=$(awk '/^  - exec:/{f=1;next} f&&/^[^[:space:]]/{f=0} \
  f&&/^[[:space:]]*-[[:space:]]*shellprocess@preflight[[:space:]]*$/{print NR; exit}' /etc/calamares/settings.conf)
unp=$(awk '/^  - exec:/{f=1;next} f&&/^[^[:space:]]/{f=0} \
  f&&/^[[:space:]]*-[[:space:]]*unpackfs[[:space:]]*$/{print NR; exit}' /etc/calamares/settings.conf)
echo "exec order: preflight=$pre unpackfs=$unp"
[[ -n "$pre" && -n "$unp" && "$pre" -lt "$unp" ]] || { echo "FAIL: preflight must run before unpackfs in settings.conf"; exit 1; }

# btrfsSubvolumes as "mountPoint subvolume" pairs, straight from mount.conf.
mapfile -t subvol_pairs < <(awk '
  /^btrfsSubvolumes:/{f=1;next}
  f&&/^[^[:space:]#]/{f=0}
  f&&/mountPoint:/{line=$0; sub(/^[[:space:]]*-?[[:space:]]*mountPoint:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); mp=line}
  f&&/subvolume:/{line=$0; sub(/^[[:space:]]*subvolume:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); print mp" "line}
' "$CONF/mount.conf")
(( ${#subvol_pairs[@]} >= 2 )) || { echo "FAIL: fewer than two btrfs subvolumes parsed from mount.conf"; exit 1; }
printf 'subvolume: %s\n' "${subvol_pairs[@]}"

btrfs_opts=$(awk '
  /^mountOptions:/{f=1;next}
  f&&/^[^[:space:]#]/{f=0}
  f&&/filesystem:[[:space:]]*btrfs[[:space:]]*$/{g=1;next}
  g&&/options:/{line=$0; sub(/^[[:space:]]*options:[[:space:]]*/,"",line); gsub(/[][[:space:]]/,"",line); print line; exit}
' "$CONF/mount.conf")
[[ -n "$btrfs_opts" ]] || { echo "FAIL: no btrfs mountOptions parsed from mount.conf"; exit 1; }
echo "btrfs mount options: $btrfs_opts"

step "partitioning $DISK (one ${esp_mib}MiB ESP from efi.recommendedSize + Btrfs root)"
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+"${esp_mib}"M -t 1:ef00 -c 1:boot "$DISK"
sgdisk -n 2:0:0              -t 2:8300 -c 2:root "$DISK"
partprobe "$DISK"
sleep 2
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL "$DISK"

step "filesystems (FAT32 ESP, Btrfs root)"
mkfs.fat -F32 "/dev/vda1"
mkfs.btrfs -f -L mahadevanos "/dev/vda2"

step "btrfs subvolumes from mount.conf"
mkdir -p /mnt
mount "/dev/vda2" /mnt
for pair in "${subvol_pairs[@]}"; do
  sv="${pair##* }"
  btrfs subvolume create "/mnt/${sv#/}"
done
umount /mnt

root_sv=$(printf '%s\n' "${subvol_pairs[@]}" | awk '$1=="/"{print $2; exit}')
mount -o "${btrfs_opts},subvol=${root_sv}" "/dev/vda2" /mnt

step "preflight guard: it must reject a target root that is not a mount"
mkdir -p /tmp/not-a-mount
if /usr/share/mahadevanos/calamares/check-root-mount.sh /tmp/not-a-mount; then
  echo "FAIL: preflight guard accepted a tmpfs directory as the target root"
  exit 1
else
  echo "ok: preflight guard rejected /tmp/not-a-mount (exit $?)"
fi

step "unpackfs: unsquashfs $SFS -> /mnt"
unsquashfs -q -d /mnt "$SFS"

step "preflight guard: it must accept the real target root"
/usr/share/mahadevanos/calamares/check-root-mount.sh /mnt

step "mount the remaining subvolumes from mount.conf"
mkdir -p /mnt/boot/efi
for pair in "${subvol_pairs[@]}"; do
  mp="${pair%% *}"
  sv="${pair##* }"
  [[ "$mp" == "/" ]] && continue
  mkdir -p "/mnt${mp}"
  mount -o "${btrfs_opts},subvol=${sv}" "/dev/vda2" "/mnt${mp}"
done
mount "/dev/vda1" /mnt/boot/efi

step "fstab (what Calamares' fstab module writes)"
root_uuid=$(blkid -s UUID -o value "/dev/vda2")
esp_uuid=$(blkid -s UUID -o value "/dev/vda1")
fstab_opts="rw,${btrfs_opts//defaults,/}"
{
  echo "# /etc/fstab — installed by the MahaDevan's OS install rehearsal"
  for pair in "${subvol_pairs[@]}"; do
    mp="${pair%% *}"
    sv="${pair##* }"
    printf 'UUID=%s  %-12s btrfs  %s,subvol=%s  0 0\n' "$root_uuid" "$mp" "$fstab_opts" "$sv"
  done
  printf 'UUID=%s  /boot/efi    vfat   umask=0077  0 2\n' "$esp_uuid"
} >/mnt/etc/fstab
cat /mnt/etc/fstab

step "machine-id, hostname, locale"
echo mahadevanos-test >/mnt/etc/hostname
cat >/mnt/etc/hosts <<'EOF'
127.0.0.1 localhost
::1       localhost
127.0.1.1 mahadevanos-test.localdomain mahadevanos-test
EOF
echo "LANG=en_US.UTF-8" >/mnt/etc/locale.conf
echo "en_US.UTF-8 UTF-8" >/mnt/etc/locale.gen
echo "KEYMAP=us" >/mnt/etc/vconsole.conf
rm -f /mnt/etc/machine-id
systemd-machine-id-setup --root=/mnt

step "create the real user (what Calamares' users module writes)"
chroot /mnt /usr/bin/useradd -m -G wheel -s /bin/bash tester
echo 'tester:test' | chroot /mnt /usr/bin/chpasswd

step "chroot: mounts for the postinstall scripts"
# --rbind, not --bind: /sys/firmware/efi/efivars is a separate efivarfs mount
# and grub-install needs it to register the NVRAM boot entry.
mount --rbind /dev /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --rbind /run /mnt/run
cp -L /etc/resolv.conf /mnt/etc/resolv.conf

step "chroot: postinstall scripts in Calamares module order"
for script in 10-mkinitcpio 15-branding 20-keyring 30-mirrors 40-snapshots 50-hardware-detect 99-cleanup; do
  echo "--- $script"
  chroot /mnt "/usr/share/mahadevanos/postinstall/${script}.sh"
done

step "chroot: kernel images and initramfs"
ls -l /mnt/boot/vmlinuz-* /mnt/boot/initramfs-*.img
[[ -s /mnt/boot/vmlinuz-linux ]] || { echo "ERROR: no vmlinuz-linux after postinstall"; exit 1; }
[[ -s /mnt/boot/initramfs-linux.img ]] || { echo "ERROR: no initramfs-linux.img after postinstall"; exit 1; }

step "chroot: bootloader (grub-install + grub-mkconfig)"
printf '\nGRUB_CMDLINE_LINUX_DEFAULT="quiet console=ttyS0"\nGRUB_TIMEOUT=3\n' >>/mnt/etc/default/grub
# Both an NVRAM entry (what Calamares does) and the removable fallback path
# (installEFIFallback: true in bootloader.conf), so the disk boots even if the
# firmware forgets the entry.
chroot /mnt /usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot/efi \
  --bootloader-id=mahadevanos
chroot /mnt /usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot/efi \
  --removable
chroot /mnt /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg

step "chroot: verify the target has no live-only artefacts"
chroot /mnt /bin/bash -c '
  set -u
  rc=0
  id liveuser >/dev/null 2>&1 && { echo "FAIL liveuser exists"; rc=1; } || echo "ok: no liveuser"
  [ -e /home/liveuser ] && { echo "FAIL /home/liveuser exists"; rc=1; } || echo "ok: no /home/liveuser"
  [ -e /etc/sudoers.d/10-liveuser ] && { echo "FAIL live sudo rule"; rc=1; } || echo "ok: no live sudo rule"
  [ -e /usr/bin/calamares ] && { echo "FAIL calamares present"; rc=1; } || echo "ok: no calamares"
  [ -e /usr/local/bin/mahadevanos-installer ] && { echo "FAIL installer wrapper present"; rc=1; } || echo "ok: no installer wrapper"
  [ -e /etc/calamares ] && { echo "FAIL /etc/calamares present"; rc=1; } || echo "ok: no /etc/calamares"
  [ -e /etc/sddm.conf.d/10-live-autologin.conf ] && { echo "FAIL live autologin"; rc=1; } || echo "ok: no live autologin"
  [ -f /etc/xdg/hypr/hyprland.lua ] && echo "ok: installed hyprland.lua present" || { echo "FAIL hyprland.lua missing"; rc=1; }
  grep -rqsE "mahadevanos-installer|calamares" /etc/skel /etc/xdg/hypr && { echo "FAIL skel/xdg references installer"; rc=1; } || echo "ok: no installer reference in skel/xdg"
  exit $rc
'

step "unmount"
# The chroot bind mounts keep /mnt busy; lazy unmount after the sync is enough
# for a VM that is about to power off.
sync
for dir in /mnt/run /mnt/sys /mnt/proc /mnt/dev; do umount -l "$dir" 2>/dev/null || true; done
umount -lR /mnt 2>/dev/null || true
findmnt -R /mnt || echo "all target mounts released"

step "rehearsal complete"
exit 0
