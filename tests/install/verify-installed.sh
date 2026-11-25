#!/usr/bin/env bash
# Runs as the ordinary installed user (tester, not root) on the installed disk.
# Everything here must work without privileges, which is itself part of the test:
# no passwordless sudo may exist.
set -uo pipefail

rc=0
fail() { echo "FAIL $*"; rc=1; }
ok()   { echo "ok: $*"; }

echo "--- identity"
id
id liveuser >/dev/null 2>&1 && fail "liveuser exists on the installed system" || ok "no liveuser"
[ "$(grep -c '^liveuser:' /etc/passwd)" = 0 ] && ok "no liveuser passwd entry" || fail "liveuser in /etc/passwd"
[ ! -e /home/liveuser ] && ok "no /home/liveuser" || fail "/home/liveuser exists"

echo "--- installer removed"
[ ! -e /usr/bin/calamares ] && ok "calamares binary absent" || fail "calamares binary present"
[ ! -e /usr/local/bin/mahadevanos-installer ] && ok "installer wrapper absent" || fail "installer wrapper present"
[ ! -e /etc/calamares ] && ok "/etc/calamares absent" || fail "/etc/calamares present"
pacman -Q calamares >/dev/null 2>&1 && fail "calamares package installed" || ok "calamares package not installed"

echo "--- no autologin, no passwordless sudo"
cat /etc/sddm.conf.d/*.conf 2>/dev/null
grep -rqsE '^[^#]*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null && fail "NOPASSWD rule present" || ok "no NOPASSWD rule"
if sudo -n true 2>/dev/null; then fail "sudo works without a password"; else ok "sudo requires a password"; fi

echo "--- desktop config"
[ -f /etc/xdg/hypr/hyprland.lua ] && ok "/etc/xdg/hypr/hyprland.lua present" || fail "hyprland.lua missing"
[ -f "$HOME/.config/hypr/hyprland.lua" ] && ok "user hyprland.lua from skel present" || fail "user hyprland.lua missing"
grep -rqsE 'mahadevanos-installer|calamares' /etc/skel /etc/xdg/hypr "$HOME/.config" 2>/dev/null \
  && fail "a desktop config still references the installer" || ok "no installer reference in desktop config"

echo "--- no live-only unit"
ls /etc/systemd/system/mahadevanos-liveuser.service 2>/dev/null && fail "live-only unit present" || ok "no live-only unit"
[ ! -e /etc/mahadevanos-live ] && ok "no live-session marker" || fail "/etc/mahadevanos-live present"
systemctl --failed --no-legend --no-pager | grep -q mahadevanos && fail "a mahadevanos unit failed" || ok "no failed mahadevanos unit"

echo "--- sudo works for this account (recovery needs it)"
if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx wheel; then
  ok "$(id -un) is in wheel"
else
  fail "$(id -un) is not in wheel: sudo, and every documented recovery step, is unusable"
fi
# The real proof: the account's own password elevates. /etc/sudoers is root-only,
# so its contents cannot be read from here; running sudo can.
if [[ -n "${INSTALL_PASS:-}" ]]; then
  if printf '%s\n' "$INSTALL_PASS" | sudo -S -k true 2>/dev/null; then
    ok "sudo works with this account's password (wheel rule is live)"
  else
    fail "sudo refuses this account's password: no wheel rule, or the account is not in wheel"
  fi
fi
if sudo -n true 2>/dev/null; then
  fail "sudo succeeds without a password"
else
  ok "sudo needs a password (not a passwordless rule)"
fi

 echo "--- kernel and initramfs on disk"
ls -l /boot/vmlinuz-* /boot/initramfs-*.img 2>/dev/null || fail "kernel or initramfs missing in /boot"

# 2026-11-22: GRUB failed on the installed disk with
#   error: loader/efi/linux.c:grub_cmd_linux:700:premature end of file
#   /@/boot/vmlinuz-linux-lts
# The kernel file was complete after unpackfs; GRUB could not read it because
# /boot inherited btrfs compress=zstd:1. Both kernels must be present, larger
# than 5 MiB, and stored without btrfs compression (the `C` flag from
# `chattr +C /boot`, which postinstall/10-mkinitcpio.sh sets).
echo "--- kernels present, complete and uncompressed"
for kernel in linux linux-lts; do
  file="/boot/vmlinuz-$kernel"
  if [[ -s "$file" ]]; then
    size=$(stat -c %s "$file")
    if (( size > 5242880 )); then
      ok "$file is ${size} bytes (> 5 MiB)"
    else
      fail "$file is only ${size} bytes (expected more than 5 MiB)"
    fi
  else
    fail "$file is missing or empty"
  fi
done
boot_flags=$(lsattr -d /boot 2>/dev/null | awk '{print $1}')
if [[ "$boot_flags" == *C* ]]; then
  ok "/boot is marked NOCOW/no-compression (GRUB can read uncompressed kernels)"
else
  fail "/boot lacks the btrfs C flag (flags: ${boot_flags:-unreadable}); kernels may be zstd-compressed and unreadable by GRUB"
fi

# The disk is only known to boot if both kernels reach the login prompt; this
# script records which one it is running on so the host-side test can assert it.
echo "--- running kernel"
printf 'kernel release: %s\n' "$(uname -r)"
uname -v

# /boot/grub/grub.cfg is root-only (grub-mkconfig writes it 0600), and this
# script must run unprivileged. The entry order is therefore asserted where root
# is available: tests/install/rehearsal.sh (entry 0 must be vmlinuz-linux) and
# this boot test itself, which selects entry 0 and requires the regular linux
# release and entry 1 and requires the -lts release.
echo "--- GRUB configuration"
if [[ -e /boot/grub/grub.cfg ]]; then
  ok "grub.cfg present (root-only; entry order is proven by the boot selection)"
else
  fail "/boot/grub/grub.cfg is missing"
fi
# The ESP is mounted with umask=0077, so its contents are root-only and this
# script must stay unprivileged. tests/install/gui-install-audit.sh (root) checks
# EFI/mahadevanos/grubx64.efi and EFI/BOOT/BOOTX64.EFI; here the mount is what
# matters.
if findmnt -rn -o TARGET /boot/efi >/dev/null 2>&1; then
  ok "ESP mounted at /boot/efi (contents are root-only)"
else
  fail "/boot/efi is not a mount point"
fi

echo "--- learning material, offline (mahadevanos-learning)"
for doc in commands shortcuts network recovery; do
  f="/usr/share/doc/mahadevanos/$doc.md"
  if [[ -s "$f" ]]; then ok "$f ($(wc -c <"$f") bytes)"; else fail "$f is missing"; fi
done
if [[ -x /usr/bin/mhelp ]]; then
  mhelp_commands="$(mhelp commands 2>&1)"
  grep -q 'Linux commands for beginners' <<<"$mhelp_commands" \
    && ok "mhelp commands prints the guide" || fail "mhelp commands printed nothing"
  mhelp_keys="$(mhelp keys 2>&1)"
  grep -q 'Super is the Windows key' <<<"$mhelp_keys" \
    && ok "mhelp keys prints the shortcut sheet" || fail "mhelp keys printed nothing"
  grep -qi 'SUPER + Q' <<<"$mhelp_keys" \
    && ok "the shortcut sheet documents Super + Q" || fail "Super + Q missing from the sheet"
  mhelp_net="$(mhelp network 2>&1)"
  grep -q 'nmcli device wifi connect' <<<"$mhelp_net" \
    && ok "mhelp network prints the network guide" || fail "mhelp network printed nothing"
  mhelp_hit="$(mhelp 'pacman' 2>&1)"
  grep -q 'pacman -Syu' <<<"$mhelp_hit" && ok "mhelp <word> searches all pages" || fail "mhelp search found nothing"
  if mhelp zzzznotaword >/dev/null 2>&1; then fail "mhelp exits 0 when nothing matches"; else ok "mhelp reports a miss"; fi
else
  fail "/usr/bin/mhelp is missing"
fi
for entry in mahadevanos-shortcuts mahadevanos-help; do
  [[ -f "/usr/share/applications/$entry.desktop" ]] \
    && ok "$entry.desktop installed" || fail "$entry.desktop missing"
done

echo "--- practice folder for this account (from /etc/skel)"
if [[ -d "$HOME/practice" ]]; then
  ok "$HOME/practice exists"
  for f in README.md notes.txt todo.txt contacts.csv; do
    [[ -s "$HOME/practice/$f" ]] && ok "practice/$f present" || fail "practice/$f missing"
  done
else
  fail "$HOME/practice is missing: /etc/skel/practice did not reach a new account"
fi
[[ -s /etc/skel/practice/README.md ]] && ok "/etc/skel/practice/README.md present" || fail "/etc/skel/practice missing"

echo "--- terminal hint and man pages"
[[ -f /etc/profile.d/10-mahadevanos-hint.sh ]] && ok "hint installed in /etc/profile.d" || fail "hint missing"
if man -w ls >/dev/null 2>&1; then ok "man page for ls found ($(man -w ls))"; else fail "man-db/man-pages not working"; fi
grep -q 'Type mhelp for commands, shortcuts and network help.' /etc/profile.d/10-mahadevanos-hint.sh \
  && ok "hint text is the expected one-liner" || fail "hint text changed"

echo "--- Dolphin stays the file manager"
if command -v dolphin >/dev/null 2>&1; then ok "dolphin binary present"; else fail "dolphin is missing"; fi
pacman -Q dolphin >/dev/null 2>&1 && ok "dolphin package installed" || fail "dolphin package not installed"
[[ -f /usr/share/applications/org.kde.dolphin.desktop ]] && ok "dolphin launcher entry present" \
  || echo "note: org.kde.dolphin.desktop not found under /usr/share/applications"

echo "--- /boot alignment package"
[[ -x /usr/bin/mahadevanos-padboot ]] && ok "mahadevanos-padboot installed" || fail "mahadevanos-padboot missing"
[[ -f /usr/share/libalpm/hooks/95-mahadevanos-padboot.hook ]] \
  && ok "pacman hook installed" || fail "pacman hook missing"
[[ -x /usr/lib/initcpio/post/50-mahadevanos-padboot.sh ]] \
  && ok "mkinitcpio post hook installed" || fail "mkinitcpio post hook missing"
for f in /boot/vmlinuz-* /boot/initramfs-*.img; do
  [[ -f "$f" ]] || continue
  fs=$(stat -c %s "$f")
  if (( fs % 4096 == 0 )); then ok "$(basename "$f") is $fs bytes (aligned)"; else fail "$(basename "$f") is $fs bytes, not 4096-aligned"; fi
done

# M3: Btrfs snapshots and recovery. Everything here is checked without
# privileges; the root-only details (the snapper config, /.snapshots, grub.cfg)
# are asserted by tests/install/gui-install-audit.sh and the snapshot phases.
echo "--- snapshots and recovery"
for pkg in snapper snap-pac grub-btrfs btrfs-assistant kitty; do
  if pacman -Q "$pkg" >/dev/null 2>&1; then ok "package $(pacman -Q "$pkg")"; else fail "$pkg is not installed"; fi
done
for unit in grub-btrfsd.service snapper-timeline.timer snapper-cleanup.timer \
            snapper-boot.timer mahadevanos-snapshot-guard.timer; do
  state="$(systemctl is-enabled "$unit" 2>/dev/null)"
  if [[ "$state" == "enabled" ]]; then ok "$unit is enabled"; else fail "$unit is not enabled (state: ${state:-none})"; fi
done
[[ -x /usr/bin/mahadevanos-snapshot-guard ]] && ok "mahadevanos-snapshot-guard installed" \
  || fail "mahadevanos-snapshot-guard is missing"
[[ -f /usr/lib/systemd/system/mahadevanos-snapshot-guard.service ]] \
  && ok "the guard service unit is installed" || fail "the guard service unit is missing"
[[ -x /usr/bin/btrfs-assistant ]] && ok "btrfs-assistant installed" || fail "btrfs-assistant is missing"
[[ -f /usr/share/applications/btrfs-assistant.desktop ]] \
  && ok "btrfs-assistant has a launcher entry" || fail "btrfs-assistant.desktop is missing"
[[ -d /.snapshots ]] && ok "/.snapshots exists" || fail "/.snapshots is missing"
# snap-pac reads the first file and its hook is AbortOnFail (a missing file would
# abort every pacman transaction); systemd-helper reads the second, and without it
# the timeline/cleanup timers are no-ops and the retention limits never apply.
for conf in /etc/snapper/snapper /etc/conf.d/snapper; do
  if grep -qE '^SNAPPER_CONFIGS="[^"]*root' "$conf" 2>/dev/null; then
    ok "$conf lists the root snapper configuration"
  else
    fail "$conf does not list the root snapper configuration"
  fi
done
if grep -q 'grub-btrfs-overlayfs' /etc/mkinitcpio.conf; then
  ok "/etc/mkinitcpio.conf lists the grub-btrfs-overlayfs hook"
else
  fail "grub-btrfs-overlayfs is missing from /etc/mkinitcpio.conf"
fi
for img in /boot/initramfs-linux.img /boot/initramfs-linux-lts.img; do
  [[ -f "$img" ]] || { fail "$img is missing"; continue; }
  # mkinitcpio writes the images 0600, so this unprivileged run cannot read
  # them. tests/install/gui-install-audit.sh (root) and the snapshot boot itself
  # check the contents; here the mkinitcpio.conf hook above is the evidence.
  if [[ ! -r "$img" ]]; then
    echo "note: $(basename "$img") is root-only; its contents are checked by the GUI audit and the snapshot boot"
    continue
  fi
  if lsinitcpio "$img" 2>/dev/null | grep -q 'grub-btrfs-overlayfs'; then
    ok "$(basename "$img") carries the overlayfs hook (snapshots boot writable)"
  else
    fail "$(basename "$img") has no overlayfs hook: a snapshot boot would be read-only"
  fi
done
if [[ -s /usr/share/doc/mahadevanos/recovery.md ]]; then
  ok "recovery.md is installed ($(wc -c < /usr/share/doc/mahadevanos/recovery.md) bytes)"
else
  fail "recovery.md is missing from /usr/share/doc/mahadevanos"
fi
if [[ -x /usr/bin/mhelp ]]; then
  mhelp_recovery="$(mhelp recovery 2>&1)"
  if grep -q 'snapper' <<<"$mhelp_recovery"; then
    ok "mhelp recovery prints the recovery page"
  else
    fail "mhelp recovery printed nothing useful"
  fi
fi
# The whole M3 stack is useless if a normal user cannot even read the
# documentation about it, so the tests exercise it unprivileged from here.
snapper_list_out="$(snapper -c root list 2>&1)" || true
printf 'snapper -c root list (unprivileged): %s\n' "$(head -2 <<<"$snapper_list_out" | tr '\n' ' ')"

# No live-only leftovers from the installer, either.
[ ! -e /usr/lib/mahadevanos ] && ok "no /usr/lib/mahadevanos kernel stash" || fail "kernel stash left behind"

 echo "--- installed system identity and filesystems"
grep -E '^(ID|PRETTY_NAME)=' /etc/os-release
findmnt -no FSTYPE,OPTIONS / | head -1
findmnt -no FSTYPE /boot/efi
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS | grep -E 'vda|NAME'

# The 2026-11-21 defect produced three partitions (two ESPs) and an unformatted
# root. Exactly two partitions must exist, and they must be mounted.
echo "--- disk layout: one ESP + one Btrfs root"
mapfile -t parts < <(lsblk -ln -o NAME,TYPE /dev/vda | awk '$2 == "part" { print $1 }')
if (( ${#parts[@]} == 2 )); then
  ok "exactly 2 partitions on /dev/vda (${parts[*]})"
else
  fail "expected exactly 2 partitions on /dev/vda, found ${#parts[@]}: ${parts[*]:-none}"
fi
[ "$(lsblk -no FSTYPE /dev/vda1 2>/dev/null)" = "vfat" ] && ok "vda1 is vfat" || fail "vda1 is not vfat"
[ "$(lsblk -no FSTYPE /dev/vda2 2>/dev/null)" = "btrfs" ] && ok "vda2 is btrfs" || fail "vda2 is not btrfs"
[ "$(findmnt -no TARGET /dev/vda1 2>/dev/null)" = "/boot/efi" ] && ok "vda1 mounted at /boot/efi" || fail "vda1 not mounted at /boot/efi"
case "$(findmnt -no SOURCE / 2>/dev/null)" in
  /dev/vda2*) ok "root (/) is on vda2" ;;
  *) fail "root (/) is not on vda2" ;;
esac
size_mib=$(($(lsblk -bno SIZE /dev/vda1 2>/dev/null || echo 0) / 1048576))
if (( size_mib >= 1000 && size_mib <= 1040 )); then
  ok "ESP is ${size_mib}MiB"
else
  fail "ESP is ${size_mib}MiB, expected 1024MiB"
fi

echo "--- services"
systemctl is-enabled sddm.service 2>/dev/null
systemctl --failed --no-legend --no-pager

if (( rc )); then
  echo "VERIFY RESULT: FAILED"
else
  echo "VERIFY RESULT: PASSED"
fi
exit $rc
