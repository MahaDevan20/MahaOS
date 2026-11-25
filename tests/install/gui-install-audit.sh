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
# Snapshots live in their own subvolume mounted at /.snapshots; without this the
# audit would inspect an empty directory and never see the initial snapshot.
snapshots_subvol=/.snapshots
snapshots_subvol=$(awk '
  /^btrfsSubvolumes:/{f=1;next} f&&/^[^[:space:]#]/{f=0}
  f&&/mountPoint:/{line=$0; sub(/^[[:space:]]*-?[[:space:]]*mountPoint:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); mp=line}
  f&&/subvolume:/{line=$0; sub(/^[[:space:]]*subvolume:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); if (mp=="/.snapshots") print line}
' "$CONF/mount.conf")
snapshots_subvol=${snapshots_subvol:-/@snapshots}
echo "snapshots subvolume from mount.conf: $snapshots_subvol"
mkdir -p "$TARGET/.snapshots"
mount -o "ro,subvol=$snapshots_subvol" "${DISK}2" "$TARGET/.snapshots" \
  || fail "cannot mount subvol $snapshots_subvol at /.snapshots"
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

echo "--- snapshots and recovery (M3)"
snap_conf="$TARGET/etc/snapper/configs/root"
if [[ -s "$snap_conf" ]]; then
  ok "snapper config installed at /etc/snapper/configs/root"
  for key in 'SUBVOLUME="/"' 'NUMBER_CLEANUP="yes"' 'NUMBER_LIMIT="10"' \
             'NUMBER_LIMIT_IMPORTANT="5"' 'TIMELINE_CLEANUP="yes"' \
             'SPACE_LIMIT="0.5"' 'FREE_LIMIT="0.2"'; do
    grep -qF -- "$key" "$snap_conf" && ok "snapper $key" || fail "snapper config lacks $key"
  done
else
  fail "no snapper config in the target: postinstall 40-snapshots.sh did not run"
fi
# snap-pac (AbortOnFail) reads SNAPPER_CONFIGS from /etc/snapper/snapper and
# snapper-timeline/cleanup read it from /etc/conf.d/snapper; the snapper package
# ships neither file.
for conf in etc/snapper/snapper etc/conf.d/snapper; do
  if grep -qE '^SNAPPER_CONFIGS="[^"]*root' "$TARGET/$conf" 2>/dev/null; then
    ok "$conf lists the root configuration"
  else
    fail "$conf does not list the root snapper configuration"
  fi
done
if [[ -s "$TARGET/etc/default/grub-btrfs/config" ]]; then
  grep -q '^GRUB_BTRFS_SUBMENUNAME="Snapshots"' "$TARGET/etc/default/grub-btrfs/config" \
    && ok "grub-btrfs names the submenu Snapshots" || fail "the grub-btrfs submenu is not named Snapshots"
else
  fail "no /etc/default/grub-btrfs/config in the target"
fi
# snap-pac treats every section here as a snapper config and its hook is
# AbortOnFail, so only [root] may appear; the live-image placeholder must have
# been replaced by postinstall/40-snapshots.sh.
if [[ -s "$TARGET/etc/snap-pac.ini" ]] && grep -qx 'snapshot = True' "$TARGET/etc/snap-pac.ini"; then
  ok "/etc/snap-pac.ini snapshots [root]"
else
  fail "/etc/snap-pac.ini is missing or does not enable snapshots ([root] snapshot = True)"
fi
if grep -E '^\[' "$TARGET/etc/snap-pac.ini" 2>/dev/null | grep -qvE '^\[root\]$'; then
  fail "/etc/snap-pac.ini names a section that is not a snapper config; pacman would abort"
else
  ok "/etc/snap-pac.ini only names the root configuration"
fi
check_file boot/grub/grub-btrfs.cfg
if grep -q "submenu 'Snapshots'" "$TARGET/boot/grub/grub.cfg" 2>/dev/null; then
  ok "the first grub.cfg has the Snapshots submenu (created before grub-mkconfig)"
else
  fail "grub.cfg has no Snapshots submenu"
fi
# grub-mkconfig indents the timeout inside `if [ x$feature_timeout_style = xy ]`.
grub_timeout=$(sed -n 's/^[[:space:]]*set timeout=\([0-9-]*\).*/\1/p' "$TARGET/boot/grub/grub.cfg" 2>/dev/null | head -1)
if [[ -n "$grub_timeout" ]] && (( grub_timeout >= 3 )); then
  ok "the GRUB menu is visible for ${grub_timeout}s (>= 3)"
else
  fail "the GRUB menu timeout is '${grub_timeout:-unset}', needs >= 3 seconds"
fi
if grep -q '/@snapshots/1/snapshot' "$TARGET/boot/grub/grub-btrfs.cfg" 2>/dev/null; then
  ok "grub-btrfs.cfg boots the fresh-install snapshot"
else
  fail "grub-btrfs.cfg has no entry for /.snapshots/1/snapshot"
  head -20 "$TARGET/boot/grub/grub-btrfs.cfg" 2>/dev/null
fi
if [[ -x "$TARGET/.snapshots/1/snapshot/usr/bin/kitty" ]]; then
  ok "the fresh-install snapshot /.snapshots/1/snapshot is populated"
else
  fail "/.snapshots/1/snapshot is missing or empty: nothing to roll back to"
fi
for f in vmlinuz-linux vmlinuz-linux-lts initramfs-linux.img initramfs-linux-lts.img; do
  size=$(stat -c %s "$TARGET/.snapshots/1/snapshot/boot/$f" 2>/dev/null || echo 0)
  if (( size > 0 && size % 4096 == 0 )); then
    ok "snapshot $f is $size bytes (aligned for GRUB)"
  else
    fail "snapshot $f is $size bytes: a rollback to it would not boot"
  fi
done
if lsinitcpio "$TARGET/.snapshots/1/snapshot/boot/initramfs-linux.img" 2>/dev/null | grep -q 'grub-btrfs-overlayfs'; then
  ok "the snapshot's initramfs carries the overlayfs hook"
else
  fail "the snapshot's initramfs has no overlayfs hook"
fi
grep -q 'grub-btrfs-overlayfs' "$TARGET/etc/mkinitcpio.conf" \
  && ok "/etc/mkinitcpio.conf lists the overlayfs hook" || fail "/etc/mkinitcpio.conf lacks the overlayfs hook"
for unit in multi-user.target.wants/grub-btrfsd.service \
            timers.target.wants/snapper-timeline.timer \
            timers.target.wants/snapper-cleanup.timer \
            timers.target.wants/snapper-boot.timer \
            timers.target.wants/mahadevanos-snapshot-guard.timer; do
  check_link "etc/systemd/system/$unit"
done
check_file usr/bin/mahadevanos-snapshot-guard
check_file usr/bin/btrfs-assistant
check_file usr/share/applications/btrfs-assistant.desktop
check_file usr/share/doc/mahadevanos/recovery.md
if recovery_out="$(chroot "$TARGET" /usr/bin/mhelp recovery 2>&1)"; then
  grep -q 'snapper' <<<"$recovery_out" && ok "mhelp recovery works in the target" \
    || fail "mhelp recovery printed nothing"
else
  fail "mhelp recovery failed in the target"
fi
umount "$TARGET/.snapshots" 2>/dev/null || true
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
# postinstall/25-sudo.sh: Arch ships the wheel rule commented out, so without a
# drop-in the only account on this system cannot run any recovery command.
sudo_rule_file="$(grep -rlE '^[[:space:]]*%wheel[[:space:]]+ALL' \
  "$TARGET/etc/sudoers" "$TARGET/etc/sudoers.d" 2>/dev/null | head -1)"
if [[ -n "$sudo_rule_file" ]]; then
  ok "target sudoers allows wheel ($sudo_rule_file)"
else
  fail "the target has no wheel sudo rule: the installed user cannot use sudo"
  ls -la "$TARGET/etc/sudoers.d" 2>/dev/null | head -5
fi
if grep -rqsE '^[^#]*NOPASSWD' "$TARGET/etc/sudoers" "$TARGET/etc/sudoers.d" 2>/dev/null; then
  fail "a NOPASSWD rule reached the target"
else
  ok "the target's sudoers has no NOPASSWD rule"
fi
if [[ -n "${user_line:-}" ]]; then
  graded_user="${user_line%%:*}"
  wheel_members="$(awk -F: '$1 == "wheel" {print $4}' "$TARGET/etc/group" 2>/dev/null)"
  if tr ',' '\n' <<<"$wheel_members" | grep -qx "$graded_user"; then
    ok "$graded_user is in wheel (sudo works with a password)"
  else
    fail "$graded_user is not in wheel (got 'wheel:$wheel_members')"
  fi
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

echo "--- learning material in the installed target (packages, not loose files)"
for doc in commands shortcuts network; do
  f="$TARGET/usr/share/doc/mahadevanos/$doc.md"
  if [[ -s "$f" ]]; then ok "target has $(basename "$f") ($(wc -c <"$f") bytes)"; else fail "target lacks /usr/share/doc/mahadevanos/$doc.md"; fi
done
[[ -x "$TARGET/usr/bin/mhelp" ]] && ok "target has /usr/bin/mhelp" || fail "target lacks mhelp"
[[ -s "$TARGET/etc/skel/practice/README.md" ]] && ok "target has /etc/skel/practice" || fail "target lacks /etc/skel/practice"
[[ -f "$TARGET/etc/profile.d/10-mahadevanos-hint.sh" ]] && ok "target has the terminal hint" || fail "target lacks the terminal hint"
for entry in mahadevanos-shortcuts mahadevanos-help; do
  [[ -f "$TARGET/usr/share/applications/$entry.desktop" ]] \
    && ok "target has $entry.desktop" || fail "target lacks $entry.desktop"
done
# The config composes binds from `local mod = "SUPER"`, so the file carries
# `mod .. " + Q"`, not the literal text "SUPER + Q".
if grep -qE '\+ Q".*exec_cmd' "$TARGET/etc/xdg/hypr/hyprland.lua" 2>/dev/null \
   && grep -qE 'local mod[[:space:]]*=[[:space:]]*"SUPER"' "$TARGET/etc/xdg/hypr/hyprland.lua"; then
  ok "target hyprland.lua binds Super + Q to a terminal"
else
  fail "target hyprland.lua has no Super + Q bind"
fi
if [[ -x "$TARGET/usr/bin/dolphin" ]]; then ok "dolphin is still installed in the target"; else fail "dolphin is missing from the target"; fi
for hook in usr/share/libalpm/hooks/95-mahadevanos-padboot.hook \
            usr/lib/initcpio/post/50-mahadevanos-padboot.sh; do
  [[ -e "$TARGET/$hook" ]] && ok "target has $hook" || fail "target lacks $hook"
done
# mhelp and man must work inside the installed system, with no network at all.
if mhelp_out="$(chroot "$TARGET" /usr/bin/mhelp network 2>&1)"; then
  if grep -q 'nmcli device wifi connect' <<<"$mhelp_out"; then
    ok "mhelp network runs inside the target (offline)"
  else
    fail "mhelp network ran in the target but printed no guide"
  fi
else
  fail "mhelp fails inside the target"
fi
if man_out="$(chroot "$TARGET" man -w ls 2>&1)"; then
  ok "man pages work inside the target ($man_out)"
else
  fail "man does not work inside the target ($man_out)"
fi

echo "--- Hyprland read the shipped config, not an autogenerated one (issue 27)"
hyp_log=""
for candidate in /run/user/1000/hypr/*/hyprland.log /home/liveuser/.local/share/hyprland/*.log; do
  [[ -s "$candidate" ]] && { hyp_log="$candidate"; break; }
done
if [[ -z "$hyp_log" ]]; then
  hyp_log="$(find /run/user/1000 /home/liveuser -maxdepth 5 -name 'hyprland*.log' -size +0 2>/dev/null | head -1)"
fi
if [[ -n "$hyp_log" ]]; then
  echo "hyprland log: $hyp_log"
  if grep -qi 'autogenerated' "$hyp_log"; then
    fail "Hyprland used an autogenerated config (the banner was on screen)"
    grep -in 'autogenerated' "$hyp_log" | head -3
  else
    ok "no autogenerated-config warning in the Hyprland log"
  fi
  if grep -qi 'hyprland\.lua' "$hyp_log"; then
    ok "Hyprland loaded hyprland.lua"
    grep -in 'hyprland\.lua' "$hyp_log" | head -3
  else
    fail "the Hyprland log never mentions hyprland.lua"
  fi
else
  fail "no Hyprland log found; cannot prove the shipped config was read"
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
