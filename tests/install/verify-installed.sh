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
for doc in commands shortcuts network; do
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
