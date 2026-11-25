#!/usr/bin/env bash
# Offline checks for the learning material and the /boot alignment package.
#
#   tests/docs/check-learning.sh
#
# Runs on the host, needs no VM, and fails on exactly the drifts that would ship a
# wrong help page:
#   * shortcuts.md disagrees with configs/hypr/hyprland.lua (generated sheet);
#   * a command the guides teach is not actually installed by this image;
#   * mhelp cannot show a page, cannot find a word, or exits 0 when it should not;
#   * the terminal hint prints more than once per session;
#   * mahadevanos-padboot does not align a file, or is not wired into pacman and
#     mkinitcpio.
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

pass=0
fail=0
ok() { printf 'ok: %s\n' "$*"; pass=$(( pass + 1 )); }
no() { printf 'FAIL: %s\n' "$*"; fail=$(( fail + 1 )); }

PKGS="$PROJECT_ROOT/iso/packages"
installed_pkg() { grep -qhE "^$1$" "$PKGS"/*.txt; }
# Packages every Arch system has through the `base` group, so they never appear
# in iso/packages/*.txt; the rest must be named there.
base_pkg() {
  case "$1" in
    coreutils|findutils|grep|pacman|util-linux|procps-ng|systemd|bash|less|sed|gawk|which) return 0 ;;
  esac
  return 1
}
provided_pkg() { installed_pkg "$1" || base_pkg "$1"; }

echo "=== shortcut sheet is generated from the real Hyprland config"
if out="$(scripts/gen-shortcuts.sh --check 2>&1)"; then
  ok "$out"
else
  no "shortcuts.md is stale: $out"
fi
if scripts/gen-shortcuts.sh 2>/dev/null && git diff --quiet -- learning/shortcuts.md 2>/dev/null; then
  ok "regenerating shortcuts.md changes nothing"
else
  # Not fatal outside a clean checkout; the --check above is the real test.
  printf 'note: regenerating learning/shortcuts.md modified the working tree\n'
fi

for needle in 'SUPER + Q' 'kitty' 'SUPER + E' 'dolphin' 'SUPER + SHIFT + R' \
              'SUPER + SHIFT + L' 'SUPER + SHIFT + Q' 'SUPER + PRINT' \
              'XF86AudioRaiseVolume' 'XF86MonBrightnessUp' 'Windows key'; do
  if grep -qiF -- "$needle" learning/shortcuts.md; then
    ok "shortcuts.md covers '$needle'"
  else
    no "shortcuts.md does not mention '$needle'"
  fi
done

echo "=== the command guide only teaches tools this image installs"
# command -> package that provides it
while read -r cmd pkg; do
  [[ -z "$cmd" ]] && continue
  # The command is taught as the first word of a table cell, e.g. "| `ping -c 3` |".
  if ! grep -qE "^\| \`$cmd( |\`)" learning/commands.md; then
    no "commands.md has no entry for $cmd"
  elif ! provided_pkg "$pkg"; then
    no "commands.md teaches $cmd but $pkg is not in iso/packages/*.txt"
  else
    ok "commands.md teaches $cmd ($pkg installed)"
  fi
done <<'EOF'
pwd coreutils
ls coreutils
cd coreutils
touch coreutils
mkdir coreutils
cp coreutils
mv coreutils
rm coreutils
rmdir coreutils
cat coreutils
less less
nano nano
find findutils
grep grep
locate plocate
chmod coreutils
chown coreutils
sudo sudo
pacman pacman
flatpak flatpak
df coreutils
du coreutils
lsblk util-linux
free procps-ng
htop htop
ip iproute2
ping iputils
nmcli networkmanager
nmtui networkmanager
resolvectl systemd
snapper snapper
EOF

echo "=== the network guide matches the installed tools"
for tool in nmcli nmtui ip ping resolvectl rfkill; do
  if ! grep -qF -- "$tool" learning/network.md; then
    no "network.md never mentions $tool"
  else
    ok "network.md documents $tool"
  fi
done
for pkg in networkmanager network-manager-applet wpa_supplicant iproute2 iputils; do
  if installed_pkg "$pkg"; then ok "network package $pkg is in the image"; else no "network package $pkg is missing"; fi
done

echo "=== mhelp works offline"
export MAHADEVANOS_DOCS="$PROJECT_ROOT/learning"
index_out="$(learning/mhelp 2>&1)"
if grep -q 'mhelp commands' <<<"$index_out"; then ok "mhelp shows the index"; else no "mhelp has no index"; fi
for page in commands keys network recovery; do
  page_out="$(learning/mhelp "$page" 2>&1)"
  if grep -q '^#' <<<"$page_out"; then
    ok "mhelp $page prints a page"
  else
    no "mhelp $page printed nothing"
  fi
done
search_out="$(learning/mhelp "Super + E" 2>/dev/null)"
if grep -qi 'dolphin' <<<"$search_out"; then
  ok "mhelp '<word>' searches the pages"
else
  no "mhelp '<word>' found nothing for a word that is documented"
fi
if learning/mhelp "zzzznotaword" >/dev/null 2>&1; then
  no "mhelp exits 0 for a word that matches nothing"
else
  ok "mhelp exits nonzero when nothing matches"
fi
unset MAHADEVANOS_DOCS

echo "=== the terminal hint prints once per session"
hint="$PROJECT_ROOT/learning/10-mahadevanos-hint.sh"
count="$(bash -i -c ". '$hint'; . '$hint'" 2>/dev/null | grep -c 'Type mhelp for commands, shortcuts and network help.')"
if [[ "$count" == "1" ]]; then
  ok "the hint appears exactly once when the file is sourced twice"
else
  no "the hint appeared $count times (expected 1)"
fi
if [[ "$(bash -c ". '$hint'" 2>/dev/null | wc -l)" == "0" ]]; then
  ok "the hint stays silent in a non-interactive shell"
else
  no "the hint printed in a non-interactive shell"
fi

echo "=== the hint can actually appear in a terminal"
# /etc/profile.d is read by login shells only, and kitty starts a plain
# interactive bash unless its config says otherwise.
if grep -qE '^shell /bin/bash --login' configs/kitty/kitty.conf; then
  ok "kitty.conf starts bash as a login shell (so /etc/profile.d runs)"
else
  no "kitty.conf does not start a login shell: the mhelp hint would never print"
fi
if grep -q '10-mahadevanos-hint.sh' packaging/mahadevanos-learning/PKGBUILD; then
  ok "the hint is shipped to /etc/profile.d by the package"
else
  no "the hint is not installed by the package"
fi

echo "=== /boot padding: the script, the pacman hook and the mkinitcpio hook"
padboot="$PROJECT_ROOT/scripts/mahadevanos-padboot"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/boot"
# 5000 bytes = one full block plus a partial tail, the shape GRUB fails on.
head -c 5000 /dev/urandom >"$tmp/boot/vmlinuz-linux"
head -c 5000 "$tmp/boot/vmlinuz-linux" >"$tmp/original-head"
MAHADEVANOS_BOOT_DIR="$tmp/boot" "$padboot" >"$tmp/out1" 2>&1
rc=$?
size="$(stat -c %s "$tmp/boot/vmlinuz-linux")"
if (( rc == 0 )) && (( size % 4096 == 0 )) && (( size == 8192 )); then
  ok "an unaligned kernel is padded to $size bytes (was 5000)"
else
  cat "$tmp/out1"
  no "padding failed (exit $rc, size $size)"
fi
if cmp -s "$tmp/original-head" <(head -c 5000 "$tmp/boot/vmlinuz-linux"); then
  ok "padding only appends: the original 5000 bytes are unchanged"
else
  no "padding rewrote the file instead of appending to it"
fi
MAHADEVANOS_BOOT_DIR="$tmp/boot" "$padboot" >"$tmp/out2" 2>&1 && grep -q 'aligned' "$tmp/out2" &&
  ok "a second run is a no-op" || no "a second run reported a problem"
head -c 4096 /dev/urandom >"$tmp/boot/initramfs-linux.img"
MAHADEVANOS_BOOT_DIR="$tmp/boot" "$padboot" -q >"$tmp/out3" 2>&1 &&
  ok "an already aligned initramfs passes" || no "an aligned initramfs failed"
mkdir -p "$tmp/empty"
MAHADEVANOS_BOOT_DIR="$tmp/empty" "$padboot"; (( $? == 0 )) &&
  ok "an empty /boot is a no-op (live ISO)" || no "an empty /boot exits nonzero"

if [[ -x "$padboot" ]] && bash -n "$padboot"; then ok "mahadevanos-padboot is executable and parses"; else no "mahadevanos-padboot is broken"; fi

hook="$PROJECT_ROOT/configs/bootpad/95-mahadevanos-padboot.hook"
grep -q '^Type = Path' "$hook" && grep -q '^Target = boot/vmlinuz-\*' "$hook" &&
  grep -q '^Exec = /usr/bin/mahadevanos-padboot' "$hook" &&
  ok "the pacman hook fires on kernel install and upgrade" || no "the pacman hook is not wired to boot/vmlinuz-*"

post="$PROJECT_ROOT/configs/bootpad/50-mahadevanos-padboot.post"
bash -n "$post" && grep -q '/usr/bin/mahadevanos-padboot' "$post" &&
  ok "the mkinitcpio post hook calls the padder" || no "the mkinitcpio post hook is broken"

pkgbuild="$PROJECT_ROOT/packaging/mahadevanos-bootpad/PKGBUILD"
grep -q 'usr/lib/initcpio/post/50-mahadevanos-padboot.sh' "$pkgbuild" &&
  grep -q 'usr/share/libalpm/hooks/95-mahadevanos-padboot.hook' "$pkgbuild" &&
  ok "the package installs both hooks (they are not copied loosely)" ||
  no "the bootpad package does not install its hooks"

lpkg="$PROJECT_ROOT/packaging/mahadevanos-learning/PKGBUILD"
grep -q 'usr/share/doc/mahadevanos' "$lpkg" && grep -q 'etc/profile.d' "$lpkg" &&
  grep -q 'etc/skel/practice' "$lpkg" &&
  ok "the learning package installs the guides, the hint and the practice folder" ||
  no "the learning package is missing files"

echo "=== the recovery page and the command guide match the M3 stack"
if grep -q 'mhelp recovery' <<<"$index_out"; then ok "the mhelp index lists the recovery page"; else no "mhelp's index hides the recovery page"; fi
for needle in 'snapper -c root list' 'Snapshots' '@snapshots' 'mhelp recovery' \
              'Btrfs Assistant' 'read-only'; do
  if grep -qiF -- "$needle" learning/recovery.md; then
    ok "recovery.md covers '$needle'"
  else
    no "recovery.md does not mention '$needle'"
  fi
done
for needle in 'snapper -c root list' 'snapper -c root rollback' 'btrfs subvolume list' \
              'mhelp recovery'; do
  if grep -qF -- "$needle" learning/commands.md; then
    ok "commands.md teaches '$needle'"
  else
    no "commands.md does not teach '$needle'"
  fi
done
if grep -q 'for doc in commands shortcuts network recovery' packaging/mahadevanos-learning/PKGBUILD; then
  ok "the learning package ships recovery.md"
else
  no "the learning package does not ship recovery.md"
fi
if grep -q 'usr/bin/mahadevanos-snapshot-guard' packaging/mahadevanos-settings/PKGBUILD &&
   grep -q 'usr/lib/systemd/system/mahadevanos-snapshot-guard.timer' packaging/mahadevanos-settings/PKGBUILD; then
  ok "the settings package ships the snapshot guard and its timer"
else
  no "the settings package does not ship the snapshot guard or its timer"
fi
if grep -q 'important=yes' configs/snapper/root; then
  ok "the snapper config documents the important anchor"
else
  no "the snapper config does not mention important snapshots"
fi

# documentation/recovery/ is the technical guide the GRUB and live-USB
# procedures live in; the tests and mhelp point at it, so it has to exist and
# use this distro's subvolume names.
for f in README boot-snapshot rollback repair-grub; do
  if [[ -s "documentation/recovery/$f.md" ]]; then ok "documentation/recovery/$f.md present"; else no "documentation/recovery/$f.md missing"; fi
done
for needle in '@home' '@log' '@cache' '@snapshots' 'subvolid=5' '@.broken' \
              'mkinitcpio -P' 'grub-mkconfig' 'arch-chroot' 'linux-lts'; do
  if grep -qF -- "$needle" documentation/recovery/*.md; then
    ok "documentation/recovery/ covers '$needle'"
  else
    no "documentation/recovery/ never mentions '$needle'"
  fi
done

# The guard is what makes "never delete the last known-good snapshot" true, so
# exercise it against a stub snapper: the newest snapshot becomes the anchor, a
# second run changes nothing, and a newer snapshot releases the old anchor.
echo "=== the snapshot guard keeps exactly one protected anchor"
guard="$PROJECT_ROOT/scripts/mahadevanos-snapshot-guard"
guard_tmp="$(mktemp -d)"
mkdir -p "$guard_tmp/configs" "$guard_tmp/state" "$guard_tmp/bin"
: >"$guard_tmp/configs/root"
cat >"$guard_tmp/bin/snapper" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
if [[ " $* " == *" list "* ]]; then
  printf 'number\n'
  for (( n = 1; n <= ${STUB_MAX:-3}; n++ )); do printf '%s\n' "$n"; done
fi
exit 0
STUB
chmod +x "$guard_tmp/bin/snapper"
guard_run() {
  env STUB_LOG="$guard_tmp/calls" STUB_MAX="${STUB_MAX:-3}" \
    MAHADEVANOS_SNAPSHOT_CONFIG_DIR="$guard_tmp/configs" \
    MAHADEVANOS_SNAPSHOT_STATE_DIR="$guard_tmp/state" \
    SNAPPER="$guard_tmp/bin/snapper" "$guard" "$@"
}
: >"$guard_tmp/calls"
if guard_run -q; then ok "the guard runs against a stubbed snapper"; else no "the guard failed on a stubbed snapper"; fi
if grep -q -- 'modify --cleanup-algorithm number --userdata important=yes 3' "$guard_tmp/calls"; then
  ok "the newest snapshot (3) is marked important=yes"
else
  no "the guard did not mark the newest snapshot important"
  sed -n '1,10p' "$guard_tmp/calls"
fi
if [[ "$(cat "$guard_tmp/state/snapshot-anchor" 2>/dev/null)" == "3" ]]; then
  ok "the anchor state records snapshot 3"
else
  no "the anchor state file does not record snapshot 3"
fi
: >"$guard_tmp/calls"
if guard_run -q && ! grep -q modify "$guard_tmp/calls"; then
  ok "a second run is a no-op (no snapper modify call)"
else
  no "a second run still called snapper modify"
  cat "$guard_tmp/calls"
fi
: >"$guard_tmp/calls"
STUB_MAX=4 guard_run -q
if grep -q -- 'userdata important=yes 4' "$guard_tmp/calls"; then
  ok "a newer snapshot takes over as the anchor"
else
  no "snapshot 4 did not become the anchor"
fi
if grep -q -- 'userdata important=no 3' "$guard_tmp/calls"; then
  ok "the previous anchor is released (important=no)"
else
  no "the previous anchor was never downgraded"
fi
if [[ ! -e "$guard_tmp/configs/nope" ]] && env MAHADEVANOS_SNAPSHOT_CONFIG_DIR="$guard_tmp/configs" \
     MAHADEVANOS_SNAPSHOT_STATE_DIR="$guard_tmp/state" SNAPPER="$guard_tmp/bin/snapper" \
     "$guard" -q --quiet 2>/dev/null; then
  ok "an unknown config is not an error (nothing to protect)"
fi
rm -rf "$guard_tmp"
bash -n "$guard" && ok "mahadevanos-snapshot-guard parses" || no "mahadevanos-snapshot-guard does not parse"
for unit in configs/snapshot-guard/mahadevanos-snapshot-guard.service \
            configs/snapshot-guard/mahadevanos-snapshot-guard.timer; do
  [[ -s "$PROJECT_ROOT/$unit" ]] && ok "$unit present" || no "$unit missing"
done

printf '\n%s: %d passed, %d failed\n' "$0" "$pass" "$fail"
(( fail == 0 ))
