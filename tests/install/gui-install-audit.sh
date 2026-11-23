#!/usr/bin/env bash
# Post-install audit of a CALAMARES GUI install, run inside the live system.
#
# scripts/test-install-gui.sh clicks through the real installer, then runs this
# script over the serial console (as root, via sudo) to prove the exec phase
# actually ran. The 2026-11-22 hand install showed the finished page one second
# after the summary page: `finished` sat in the show list before the exec phase,
# so nothing was partitioned, unpacked or bootloaded. A test that only checks
# exit codes cannot see that; this one checks the Calamares session log, the
# partition table, and the installed root itself.
set -uo pipefail

export LC_ALL=C
rc=0
fail() { printf 'FAIL: %s\n' "$*"; rc=1; }
ok()   { printf 'ok: %s\n' "$*"; }

DISK=/dev/vda

# Calamares writes session.log to XDG_CACHE_HOME/calamares. The live launcher
# runs it with `sudo -E`, so that is the live user's cache, not root's.
LOG=""
for candidate in /root/.cache/calamares/session.log /home/*/.cache/calamares/session.log; do
  if [[ -s "$candidate" ]]; then
    LOG="$candidate"
    break
  fi
done
if [[ -z "$LOG" ]]; then
  LOG=$(find /root /home -maxdepth 5 -name session.log -size +0 2>/dev/null | head -1)
fi

# This must run in the live system, never on an installed one.
if [[ ! -f /run/archiso/bootmnt/arch/x86_64/airootfs.sfs ]]; then
  echo "FAIL: not running in the live ISO (the live squashfs is not mounted)"
  exit 1
fi

echo "=== calamares session log"
if [[ -s "$LOG" ]]; then
  ok "session log present: $LOG ($(wc -l <"$LOG") lines)"
else
  fail "no Calamares session.log found under /root or /home; the GUI never ran or never reached a job"
  ls -la /root/.cache /home/*/.cache 2>&1 | head -20
  exit 1
fi

echo "--- queued jobs"
grep -E 'There are .* jobs' "$LOG" | tail -3
total_jobs=$(grep -oE 'There are [0-9]+ jobs' "$LOG" | tail -1 | grep -oE '[0-9]+')
echo "total_jobs=${total_jobs:-0}"

echo "--- starting job lines (first 40)"
grep -n 'Starting job' "$LOG" | head -40

started=$(grep -c 'Starting job' "$LOG")
echo "jobs started: $started"
if [[ -z "${total_jobs:-}" ]] || (( total_jobs < 1 )); then
  fail "the session log records no job queue at all (nothing was installed)"
elif (( started < total_jobs )); then
  fail "only $started of $total_jobs queued jobs started"
else
  ok "all $total_jobs queued jobs started"
fi
# One job per module at minimum: 16 modules in the exec phase of settings.conf.
if (( started < 16 )); then
  fail "$started jobs ran; fewer than the 16 exec modules in settings.conf"
fi
if grep -q 'EMERGENCY JOB' "$LOG"; then
  fail "a job failed and Calamares fell back to the emergency queue"
  grep -n -B4 'EMERGENCY JOB' "$LOG" | head -30
fi

echo
echo "=== partition table on $DISK"
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL,UUID "$DISK"
for part in "${DISK}1" "${DISK}2"; do
  [[ -b "$part" ]] || fail "$part does not exist: the partition module did not run"
done
esp_type=$(blkid -s TYPE -o value "${DISK}1" 2>/dev/null)
root_type=$(blkid -s TYPE -o value "${DISK}2" 2>/dev/null)
echo "${DISK}1 type=${esp_type:-none}  ${DISK}2 type=${root_type:-none}"
[[ "$esp_type" == "vfat" ]] || fail "${DISK}1 is not FAT32 (got '${esp_type:-none}')"
[[ "$root_type" == "btrfs" ]] || fail "${DISK}2 is not Btrfs (got '${root_type:-none}')"

CONF=/etc/calamares/modules
root_subvol=$(awk '
  /^btrfsSubvolumes:/{f=1;next} f&&/^[^[:space:]#]/{f=0}
  f&&/mountPoint:/{line=$0; sub(/^[[:space:]]*-?[[:space:]]*mountPoint:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); mp=line}
  f&&/subvolume:/{line=$0; sub(/^[[:space:]]*subvolume:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); if (mp=="/") print line}
' "$CONF/mount.conf")
root_subvol=${root_subvol:-/@}
echo "root subvolume from mount.conf: $root_subvol"
home_subvol=$(awk '
  /^btrfsSubvolumes:/{f=1;next} f&&/^[^[:space:]#]/{f=0}
  f&&/mountPoint:/{line=$0; sub(/^[[:space:]]*-?[[:space:]]*mountPoint:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); mp=line}
  f&&/subvolume:/{line=$0; sub(/^[[:space:]]*subvolume:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); if (mp=="/home") print line}
' "$CONF/mount.conf")
echo "home subvolume from mount.conf: ${home_subvol:-<none>}"

TARGET=/var/tmp/gui-audit-root
mkdir -p "$TARGET"
if ! mountpoint -q "$TARGET"; then
  mount -o "ro,subvol=$root_subvol" "${DISK}2" "$TARGET" || fail "cannot mount ${DISK}2 subvol $root_subvol read-only"
fi
# The ESP is its own filesystem; without this the audit would look for GRUB in
# an empty /boot/efi directory.
mkdir -p "$TARGET/boot/efi"
mount -o ro "${DISK}1" "$TARGET/boot/efi" || fail "cannot mount the ESP ${DISK}1 read-only"
# /home is its own subvolume, so the created user's home only shows up when it
# is mounted too.
if [[ -n "$home_subvol" ]]; then
  mkdir -p "$TARGET/home"
  mount -o "ro,subvol=$home_subvol" "${DISK}2" "$TARGET/home" || fail "cannot mount subvol $home_subvol at /home"
fi
echo "--- ESP contents"
find "$TARGET/boot/efi" -maxdepth 3 -name '*.efi' -o -maxdepth 3 -name 'grub.cfg' | head -10

echo
echo "=== the installed root (mounted read-only at $TARGET)"
if [[ -x "$TARGET/usr/bin/bash" && -f "$TARGET/etc/os-release" ]]; then
  files=$(find "$TARGET" -xdev | wc -l)
  du_mib=$(du -sxm "$TARGET" | awk '{print $1}')
  ok "unpackfs copied the system: $files paths, ${du_mib} MiB"
  (( files > 1000 )) || fail "only $files paths in the target: unpackfs copied almost nothing"
  (( du_mib > 500 )) || fail "only ${du_mib} MiB in the target: unpackfs copied almost nothing"
else
  fail "$TARGET/usr/bin/bash or /etc/os-release missing: nothing was unpacked"
fi

check_file() { [[ -s "$TARGET/$1" ]] && ok "$1 present" || fail "$1 missing or empty"; }
check_link() { [[ -L "$TARGET/$1" ]] && ok "$1 enabled" || fail "$1 is not an enabled unit symlink"; }

check_file etc/fstab
if [[ -s "$TARGET/etc/fstab" ]]; then
  grep -q 'subvol=' "$TARGET/etc/fstab" && ok "fstab has btrfs subvolume entries" || fail "fstab has no subvol= entries"
  grep -qE '^UUID=[^ ]+[[:space:]]+/boot/efi[[:space:]]+vfat' "$TARGET/etc/fstab" \
    && ok "fstab has the ESP entry" || fail "fstab has no /boot/efi vfat entry"
fi
check_file etc/machine-id
check_file etc/locale.conf
check_file etc/vconsole.conf
check_file etc/adjtime
check_file etc/default/grub
grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$TARGET/etc/default/grub" 2>/dev/null \
  && ok "grubcfg wrote GRUB_CMDLINE_LINUX_DEFAULT" || fail "GRUB_CMDLINE_LINUX_DEFAULT missing from /etc/default/grub"
[[ -s "$TARGET/boot/grub/grub.cfg" ]] && ok "bootloader wrote grub.cfg" || fail "no /boot/grub/grub.cfg in the target"
grep -q 'vmlinuz-linux' "$TARGET/boot/grub/grub.cfg" 2>/dev/null \
  && ok "grub.cfg references vmlinuz-linux" || fail "grub.cfg has no vmlinuz-linux entry"

# The installed-disk boot test selects its entry by index (GRUB_DOWN): 0 is the
# regular kernel and 3 is linux-lts when GRUB_DISABLE_SUBMENU=y and recovery
# entries are on. Assert that layout here so a change in grub.cfg is caught by the
# install test instead of silently booting the wrong kernel.
echo "--- GRUB menu order"
index=0
linux_index=""
lts_index=""
# Only real definitions count: grub.cfg also contains shell lines that merely
# mention "menuentry" (the feature_menuentry_id block).
while IFS= read -r line; do
  title=$(printf '%s\n' "$line" | sed -E "s/^[[:space:]]*menuentry[[:space:]]+['\"]([^'\"]+)['\"].*/\\1/")
  printf '  %d: %s\n' "$index" "$title"
  case "$title" in
    *linux-lts*recovery*) ;;
    *linux-lts*) [[ -z "$lts_index" ]] && lts_index=$index ;;
    *recovery*) ;;
    *) [[ -z "$linux_index" ]] && linux_index=$index ;;
  esac
  index=$(( index + 1 ))
done < <(grep -E "^[[:space:]]*menuentry[[:space:]]+['\"]" "$TARGET/boot/grub/grub.cfg" 2>/dev/null)
echo "grub entry index: linux=${linux_index:-?} linux-lts=${lts_index:-?}"
[[ "$linux_index" == "0" ]] || fail "the first GRUB entry is not the regular linux kernel (index ${linux_index:-none})"
[[ "$lts_index" == "3" ]] || fail "linux-lts is at index ${lts_index:-none}, but the boot test uses 3; set GRUB_LTS_INDEX"
for p in boot/efi/EFI/mahadevanos/grubx64.efi boot/efi/EFI/BOOT/BOOTX64.EFI \
         boot/vmlinuz-linux boot/vmlinuz-linux-lts \
         boot/initramfs-linux.img boot/initramfs-linux-lts.img usr/lib/locale/locale-archive; do
  check_file "$p"
done
umount "$TARGET/home" 2>/dev/null || true
umount "$TARGET/boot/efi" 2>/dev/null || true
for k in boot/vmlinuz-linux boot/vmlinuz-linux-lts boot/initramfs-linux.img boot/initramfs-linux-lts.img; do
  if [[ -s "$TARGET/$k" ]]; then
    size=$(stat -c %s "$TARGET/$k")
    if [[ "$k" == boot/vmlinuz-* ]] && (( size <= 5242880 )); then
      fail "$k is only $size bytes (expected > 5 MiB)"
    fi
    # GRUB 2.16 reads btrfs files block by block and skips the tail extent, so a
    # file that ends mid-block boots with "premature end of file".
    if (( size % 4096 == 0 )); then
      ok "$k is $size bytes (block-aligned for GRUB)"
    else
      fail "$k is $size bytes, $(( size % 4096 )) over a 4096-byte boundary: GRUB would read it short"
    fi
  fi
done
echo "--- GRUB's own reader against the installed disk"
if command -v grub-fstest >/dev/null 2>&1; then
  for k in linux linux-lts; do
    rm -f "/tmp/k-read-$k"
    grub-fstest "${DISK}2" cp "/@/boot/vmlinuz-$k" "/tmp/k-read-$k" >/dev/null 2>&1
    gsize=$(stat -c %s "/tmp/k-read-$k" 2>/dev/null || echo 0)
    dsize=$(stat -c %s "$TARGET/boot/vmlinuz-$k" 2>/dev/null || echo 0)
    if [[ "$gsize" == "$dsize" && "$gsize" != "0" ]]; then
      ok "GRUB reads /@/boot/vmlinuz-$k completely ($gsize bytes)"
    else
      fail "GRUB reads only $gsize of $dsize bytes of /@/boot/vmlinuz-$k; that is the boot-time 'premature end of file'"
    fi
  done
else
  echo "note: grub-fstest is not in the live image; skipping the GRUB-reader check"
fi
check_link etc/systemd/system/display-manager.service
check_link etc/systemd/system/multi-user.target.wants/NetworkManager.service

user_line=$(awk -F: '$3 >= 1000 && $3 < 60000 {print; exit}' "$TARGET/etc/passwd" 2>/dev/null)
if [[ -n "$user_line" ]]; then
  ok "users module created: ${user_line%%:*} (uid $(cut -d: -f3 <<<"$user_line"))"
  home=$(cut -d: -f6 <<<"$user_line")
  echo "--- home directory contents ($home on the @home subvolume)"
  ls -la "$TARGET$home" 2>&1 | head -10
  [[ -d "$TARGET$home" ]] && ok "home directory $home exists" || echo "note: $home is not visible before the installed system mounts it"
else
  fail "no regular user account in the target: the users module did not run"
fi
[[ -d "$TARGET/etc/NetworkManager/system-connections" ]] && ok "networkcfg created the NM connections dir" \
  || fail "no /etc/NetworkManager/system-connections in the target"

echo "--- leftover calamares mounts (umount module)"
leftovers=$(findmnt -rn -o TARGET | grep -E '^/tmp/calamares-root-[^/]+' || true)
if [[ -n "$leftovers" ]]; then
  fail "mounts left behind: $leftovers"
else
  ok "no /tmp/calamares-root-* mounts remain"
fi

echo "--- live-only artefacts must be gone"
for p in etc/calamares usr/bin/calamares usr/local/bin/mahadevanos-installer; do
  [[ -e "$TARGET/$p" ]] && fail "$p is still present in the target" || ok "no $p in the target"
done

echo
if (( rc == 0 )); then
  echo "GUI INSTALL AUDIT: PASSED"
else
  echo "GUI INSTALL AUDIT: FAILED"
fi
echo "GUI-AUDIT-RC:$rc"
exit "$rc"
