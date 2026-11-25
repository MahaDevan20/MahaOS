#!/usr/bin/env bash
# M3 phase B: prove that a snapshot boots read-only through the overlayfs hook,
# that it still has the file the broken system lost, and that the documented
# rollback procedure turns the disk back into a working system.
#
#   tests/install/snapshot-boot-check.sh      (as the installed user, elevates itself)
#
# Run on the installed disk, booted from the Snapshots submenu
# (scripts/test-install-auto.sh --snapshot-boot). Phase A
# (tests/install/snapshots-check.sh) deleted /usr/bin/kitty and left
# /etc/mahadevanos-snapshot-broken behind, so this boot has to disagree with the
# disk and agree with the snapshot:
#
#   1. / is an overlay over the snapshot subvolume named on the kernel command
#      line, and writes to / only touch the tmpfs upper layer;
#   2. the snapshot is still read-only, /usr/bin/kitty is back, and the break
#      marker is absent;
#   3. the manual rollback from documentation/recovery/rollback.md works from
#      this boot: rename @ to @.broken, snapshot @snapshots/<N>/snapshot to @,
#      clear the read-only flag, chroot, mkinitcpio -P, grub-mkconfig;
#   4. the restored tree has both kernels, a rebootable GRUB menu (entry 0
#      linux, entry 3 linux-lts, Snapshots submenu), 4096-aligned /boot files
#      and the overlayfs hook in both initramfs images.
#
# scripts/test-install-auto.sh --boot-installed --kernel both then boots the
# rolled-back disk twice, which is what proves the rollback kept a working
# system on both kernels.
set -uo pipefail

rc=0
fail() { echo "FAIL $*"; rc=1; }
ok()   { echo "ok: $*"; }

SUDO=""
if [[ $(id -u) -ne 0 ]]; then
  if [[ -z "${INSTALL_PASS:-}" ]]; then
    fail "not root and INSTALL_PASS is not set"
    echo "SNAPSHOT BOOT RESULT: FAILED"
    exit 1
  fi
  SUDO="sudo -S"
fi

run_root() { # run_root <command...>
  if [[ -n "$SUDO" ]]; then
    printf '%s\n' "$INSTALL_PASS" | $SUDO "$@"
  else
    "$@"
  fi
}

DISK="${MAHADEVANOS_TEST_DISK:-/dev/vda2}"
ESP="${MAHADEVANOS_TEST_ESP:-/dev/vda1}"

echo "=== booted from the Snapshots submenu"
cat /proc/cmdline | tr ' ' '\n' | grep -E '^(root|rootflags)=' || true
snapnum="$(sed -n 's|.*subvol=/@snapshots/\([0-9][0-9]*\)/snapshot.*|\1|p' /proc/cmdline | head -1)"
if [[ -z "$snapnum" ]]; then
  fail "the kernel command line does not name a /@snapshots/<N>/snapshot root: this is not a snapshot boot"
else
  ok "the kernel command line boots /@snapshots/$snapnum/snapshot"
fi
snap_sub="/.snapshots/${snapnum:-0}/snapshot"

root_fstype="$(findmnt -no FSTYPE / 2>/dev/null)"
printf '/ filesystem: %s\n' "${root_fstype:-unknown}"
if [[ "$root_fstype" == "overlay" ]]; then
  ok "/ is an overlay, so writes land in RAM and the snapshot stays untouched"
else
  fail "/ is '${root_fstype:-unknown}', not overlay: the grub-btrfs-overlayfs hook did not run"
fi
findmnt -no SOURCE,OPTIONS / 2>/dev/null | head -c 400; echo
if findmnt -no OPTIONS / 2>/dev/null | grep -q 'lowerdir=.*/@snapshots/'"$snapnum"'/snapshot'; then
  ok "the overlay's lower layer is snapshot $snapnum"
else
  echo "note: the overlay options do not spell the lowerdir out (an overlayfs hook may pass it differently)"
  findmnt -no OPTIONS / 2>/dev/null | tr ',' '\n' | grep -i lower || true
fi

echo "=== the snapshot is read-only and still has what the broken system lost"
if run_root btrfs property get "$snap_sub" ro 2>/dev/null | grep -q 'ro=true'; then
  ok "$snap_sub is still read-only (a valid rollback target)"
else
  fail "$snap_sub is not read-only: booting may have modified the snapshot"
fi
if [[ -x /usr/bin/kitty ]] || command -v kitty >/dev/null 2>&1; then
  ok "/usr/bin/kitty is back: this root is the snapshot, not the broken disk"
else
  fail "kitty is missing, so this root is not the snapshot that had it"
fi
if [[ -e /etc/mahadevanos-snapshot-broken ]]; then
  fail "/etc/mahadevanos-snapshot-broken exists: this is the broken root, not the snapshot"
else
  ok "the break marker is absent, as it should be in a snapshot from before the break"
fi
# A write to / must not reach the snapshot, but must work.
if run_root sh -c 'echo overlay-write-test > /etc/.mahadevanos-overlay-test' 2>/dev/null \
   && [[ -f /etc/.mahadevanos-overlay-test ]]; then
  ok "the overlay accepts writes to the root filesystem"
  run_root rm -f /etc/.mahadevanos-overlay-test
else
  fail "the root filesystem is not writable: the overlay upper layer is missing"
fi

echo "=== the installed system on disk (before the rollback)"
# / is an overlay, but /home and /.snapshots are real mounts of @home and
# @snapshots, so btrfs can be asked about the filesystem through them.
run_root btrfs subvolume list /home | sed -n '1,20p'
if run_root btrfs subvolume show /home >/dev/null 2>&1; then
  ok "/home is the @home subvolume (rollback leaves documents alone)"
else
  fail "cannot see the @home subvolume"
fi
if run_root btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  ok "/.snapshots is the @snapshots subvolume (rollback leaves snapshots alone)"
else
  fail "cannot see the @snapshots subvolume"
fi

echo "=== rollback (documentation/recovery/rollback.md)"
TOP=/mnt/top
TGT=/target
run_root mkdir -p "$TOP" "$TGT"
if run_root mount -o subvolid=5 "$DISK" "$TOP"; then
  ok "mounted the Btrfs top level at $TOP"
else
  fail "cannot mount the Btrfs top level of $DISK"
  echo "SNAPSHOT BOOT RESULT: FAILED"
  exit 1
fi
run_root btrfs subvolume list "$TOP" | sed -n '1,20p'
if run_root test -d "$TOP/@"; then ok "the live root subvolume @ exists"; else fail "no @ subvolume on the top level"; fi
if [[ -n "$snapnum" ]] && run_root test -d "$TOP/@snapshots/$snapnum/snapshot"; then
  ok "@snapshots/$snapnum/snapshot exists"
else
  fail "@snapshots/${snapnum:-?}/snapshot does not exist"
fi

# @.broken only survives when a previous rollback was never cleaned up.
if run_root test -e "$TOP/@.broken"; then
  echo "note: @.broken already exists; deleting the earlier abandoned root"
  run_root btrfs subvolume delete "$TOP/@.broken" || fail "cannot delete the stale @.broken"
fi
if run_root mv "$TOP/@" "$TOP/@.broken"; then
  ok "renamed @ to @.broken (the broken root is kept, not deleted)"
else
  fail "cannot rename @ to @.broken"
fi
if run_root btrfs subvolume snapshot "$TOP/@snapshots/$snapnum/snapshot" "$TOP/@"; then
  ok "created @ from snapshot $snapnum"
else
  fail "btrfs subvolume snapshot failed"
fi
# A snapshot of a read-only subvolume is read-only too; the new root must be
# writable or nothing can boot from it.
if run_root btrfs property set -ts "$TOP/@" ro false; then
  ok "cleared the read-only flag on the restored @"
else
  fail "cannot make the restored @ writable"
fi
if run_root btrfs property get "$TOP/@" ro 2>/dev/null | grep -q 'ro=false'; then
  ok "the restored @ is writable"
else
  fail "the restored @ is still read-only"
fi

echo "=== chroot into the restored system"
mkdir -p "$TGT" 2>/dev/null || true
run_root mkdir -p "$TGT"
mounted=()
mount_subvol() { # mount_subvol <subvol> <mountpoint>
  run_root mkdir -p "$2" || return 1
  run_root mount -o "subvol=$1" "$DISK" "$2" && mounted+=("$2")
}
mount_subvol @ "$TGT"              || fail "cannot mount the restored @ at $TGT"
for pair in "@home:/home" "@log:/var/log" "@cache:/var/cache" "@snapshots:/.snapshots"; do
  mount_subvol "${pair%%:*}" "$TGT${pair#*:}" || fail "cannot mount ${pair%%:*}"
done
run_root mkdir -p "$TGT/boot/efi"
run_root mount "$ESP" "$TGT/boot/efi" && mounted+=("$TGT/boot/efi") || fail "cannot mount the ESP at $TGT/boot/efi"
for d in dev proc sys run; do
  run_root mount --rbind "/$d" "$TGT/$d" && run_root mount --make-rslave "$TGT/$d" || fail "cannot rbind /$d"
done
# The ESP is vfat with umask=0077, so only root can see it; everything below runs
# as root.

echo "=== the restored tree is the good state"
run_root test -x "$TGT/usr/bin/kitty" && ok "the restored tree has /usr/bin/kitty back" \
  || fail "the restored tree still lacks kitty"
run_root test -e "$TGT/etc/mahadevanos-snapshot-broken" \
  && fail "the break marker survived the rollback" \
  || ok "the break marker is gone from the restored tree"
for k in linux linux-lts; do
  if run_root test -s "$TGT/boot/vmlinuz-$k"; then
    ok "the restored tree has vmlinuz-$k"
  else
    fail "the restored tree lacks vmlinuz-$k"
  fi
done
run_root grep -q 'subvol=@' "$TGT/etc/fstab" && ok "the restored fstab still mounts subvol=@" \
  || fail "the restored fstab has no subvol=@ entry"

echo "=== regenerate the initramfs and the GRUB menu for the restored system"
if run_root chroot "$TGT" mkinitcpio -P >/tmp/rollback-mkinitcpio.log 2>&1; then
  ok "mkinitcpio -P ran in the restored system"
else
  fail "mkinitcpio -P failed"
  tail -20 /tmp/rollback-mkinitcpio.log
fi
grep -iE 'padboot|aligned' /tmp/rollback-mkinitcpio.log | tail -6
if run_root chroot "$TGT" grub-mkconfig -o /boot/grub/grub.cfg >/tmp/rollback-grub.log 2>&1; then
  ok "grub-mkconfig regenerated the menu"
else
  fail "grub-mkconfig failed"
  tail -20 /tmp/rollback-grub.log
fi
grep -iE 'snapshot|found linux' /tmp/rollback-grub.log | tail -6
run_root cp "$TGT/boot/grub/grub.cfg" /tmp/rollback-grub.cfg.audit
run_root cp "$TGT/boot/grub/grub-btrfs.cfg" /tmp/rollback-grub-btrfs.cfg.audit 2>/dev/null || true
run_root chmod a+r /tmp/rollback-grub.cfg.audit /tmp/rollback-grub-btrfs.cfg.audit 2>/dev/null || true

if grep -q 'vmlinuz-linux-lts' /tmp/rollback-grub.cfg.audit; then
  ok "the restored menu still has the linux-lts fallback"
else
  fail "the restored menu lost linux-lts"
fi
mapfile -t entry_kernels < <(awk '
  /^menuentry / { idx++; want=1; next }
  want && /vmlinuz-/ {
    line=$0; sub(/.*vmlinuz-/, "vmlinuz-", line); sub(/[ \t].*/, "", line)
    print idx-1, line; want=0
  }
' /tmp/rollback-grub.cfg.audit)
printf '     entry %s\n' "${entry_kernels[@]}"
[[ "${entry_kernels[0]}" == "0 vmlinuz-linux" ]] \
  && ok "entry 0 is still the regular linux kernel" \
  || fail "entry 0 is '${entry_kernels[0]:-none}', not vmlinuz-linux"
if printf '%s\n' "${entry_kernels[@]}" | grep -qx '3 vmlinuz-linux-lts'; then
  ok "entry 3 is still linux-lts"
else
  fail "linux-lts is not entry 3 after the rollback"
fi
if grep -q "submenu 'Snapshots'" /tmp/rollback-grub.cfg.audit; then
  ok "the restored menu still has the Snapshots submenu"
else
  fail "the restored menu has no Snapshots submenu"
fi
timeout_value="$(sed -n 's/^[[:space:]]*set timeout=\([0-9-]*\).*/\1/p' /tmp/rollback-grub.cfg.audit | head -1)"
if [[ -n "$timeout_value" ]] && (( timeout_value >= 3 )); then
  ok "the restored menu is visible for ${timeout_value}s"
else
  fail "the restored menu timeout is '${timeout_value:-unset}'"
fi
if [[ -f /tmp/rollback-grub-btrfs.cfg.audit ]] && grep -q 'menuentry ' /tmp/rollback-grub-btrfs.cfg.audit; then
  ok "grub-btrfs.cfg still lists snapshots ($(grep -cE '^[[:space:]]*menuentry ' /tmp/rollback-grub-btrfs.cfg.audit) entries)"
else
  fail "grub-btrfs.cfg is empty after the rollback: the submenu would be empty on the next boot"
fi

echo "=== /boot in the restored tree is still GRUB-readable"
boot_flags="$(run_root lsattr -d "$TGT/boot" 2>/dev/null | awk '{print $1}')"
if [[ "$boot_flags" == *C* ]]; then
  ok "/boot still carries the btrfs C flag (no compression)"
else
  fail "/boot lost the C flag (${boot_flags:-unreadable}); GRUB may read the kernels short"
fi
for f in vmlinuz-linux vmlinuz-linux-lts initramfs-linux.img initramfs-linux-lts.img; do
  size="$(run_root stat -c %s "$TGT/boot/$f" 2>/dev/null)"
  if [[ -n "$size" ]] && (( size % 4096 == 0 )); then
    ok "$f is $size bytes (4096-aligned)"
  else
    fail "$f is '${size:-missing}' bytes; not 4096-aligned"
  fi
done
for img in initramfs-linux.img initramfs-linux-lts.img; do
  if run_root chroot "$TGT" lsinitcpio "/boot/$img" 2>/dev/null | grep -q 'grub-btrfs-overlayfs'; then
    ok "$img has the overlayfs hook (a future snapshot boot works)"
  else
    fail "$img lost the overlayfs hook: the next snapshot boot would be read-only"
  fi
done

echo "=== unmount and shut down"
sync
for d in run sys proc dev; do run_root umount -l "$TGT/$d" 2>/dev/null || true; done
for mp in "$TGT/boot/efi" "$TGT/.snapshots" "$TGT/var/cache" "$TGT/var/log" "$TGT/home" "$TGT"; do
  run_root umount "$mp" 2>/dev/null || run_root umount -l "$mp" 2>/dev/null || true
done
run_root umount "$TOP" 2>/dev/null || fail "cannot unmount $TOP"
findmnt -rn -o TARGET | grep -E '^/(target|mnt/top)' && fail "mounts left behind" || ok "no mounts left behind"
run_root btrfs subvolume list /home 2>/dev/null | grep -E '@(\.broken)?$' || true

echo
if (( rc == 0 )); then
  echo "SNAPSHOT BOOT RESULT: PASSED"
else
  echo "SNAPSHOT BOOT RESULT: FAILED"
fi
# Same delayed shutdown as phase A: the caller still has to echo PAYLOAD-EXIT.
run_root sh -c 'nohup sh -c "sleep 4; systemctl poweroff" >/dev/null 2>&1 &' || true
exit "$rc"
