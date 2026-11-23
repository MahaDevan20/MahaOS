#!/usr/bin/env bash
# Prove the /boot alignment package works on a REAL installed system.
#
#   tests/install/padboot-check.sh
#
# Run on an installed disk (as the ordinary user; it elevates itself with the
# password in $INSTALL_PASS) after the GUI or scripted install. It changes the
# system on purpose -- that is the point: the padding used to happen only during
# the install, so a kernel upgrade could leave a GRUB-unreadable file behind.
#
#   1. record the alignment of every /boot file;
#   2. make one initramfs unaligned by truncating it;
#   3. run `mkinitcpio -P` and require the mkinitcpio post hook to have run and
#      every /boot file to be a 4096 multiple again;
#   4. reinstall the `linux` kernel package with pacman (network), which is the
#      path a real upgrade takes, and require the alpm hook to have run and the
#      files to be aligned;
#   5. print PASS/FAIL lines; the host test boots the disk on both kernels
#      afterwards, which is what proves the result still boots.
set -uo pipefail

rc=0
fail() { echo "FAIL $*"; rc=1; }
ok()   { echo "ok: $*"; }

SUDO=""
if [[ $(id -u) -ne 0 ]]; then
  if [[ -z "${INSTALL_PASS:-}" ]]; then
    fail "not root and INSTALL_PASS is not set; cannot run mkinitcpio/pacman"
    echo "PADBOOT RESULT: FAILED"
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

aligned_report() {
  local f size bad=0
  for f in /boot/vmlinuz-* /boot/initramfs-*.img; do
    [[ -f "$f" ]] || continue
    size=$(stat -c %s "$f")
    if (( size % 4096 == 0 )); then
      ok "$(basename "$f") $size bytes (aligned)"
    else
      fail "$(basename "$f") $size bytes is not a 4096 multiple"
      bad=1
    fi
  done
  return $bad
}

echo "=== the alignment package is installed"
[[ -x /usr/bin/mahadevanos-padboot ]] && ok "mahadevanos-padboot present" || fail "mahadevanos-padboot missing"
[[ -f /usr/share/libalpm/hooks/95-mahadevanos-padboot.hook ]] && ok "pacman hook present" || fail "pacman hook missing"
[[ -x /usr/lib/initcpio/post/50-mahadevanos-padboot.sh ]] && ok "mkinitcpio post hook present" || fail "mkinitcpio post hook missing"
if pacman -Q mahadevanos-bootpad >/dev/null 2>&1; then
  ok "package: $(pacman -Q mahadevanos-bootpad)"
else
  fail "mahadevanos-bootpad is not installed"
fi

echo "=== before"
aligned_report

echo "=== step 1: make the initramfs unaligned, then run mkinitcpio -P"
img=/boot/initramfs-linux.img
if [[ -f "$img" ]]; then
  before=$(stat -c %s "$img")
  # Truncating is safe here: mkinitcpio regenerates the file in the next step.
  run_root truncate -s $(( before - 300 )) "$img"
  after=$(stat -c %s "$img")
  if (( after % 4096 != 0 )); then
    ok "$(basename "$img") forced to $after bytes (not aligned)"
  else
    fail "could not make $img unaligned ($after bytes)"
  fi
else
  fail "$img is missing"
fi

mklog=$(mktemp)
if run_root mkinitcpio -P >"$mklog" 2>&1; then
  ok "mkinitcpio -P succeeded"
else
  fail "mkinitcpio -P failed"
  tail -20 "$mklog"
fi
if grep -q '50-mahadevanos-padboot.sh' "$mklog"; then
  ok "mkinitcpio ran the post hook: $(grep -m1 'Running post hook' "$mklog")"
else
  fail "the mkinitcpio post hook never ran"
  grep -i 'post hook' "$mklog" | head -5
fi
grep -E 'padded|aligned' "$mklog" | head -8
aligned_report || true

echo "=== step 2: reinstall a kernel package with pacman (the upgrade path)"
if command -v pacman >/dev/null 2>&1; then
  if ! timeout 30 ping -c1 -W2 archlinux.org >/dev/null 2>&1 &&
     ! timeout 30 ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
    fail "no network in the guest: pacman cannot reinstall linux (the mkinitcpio path above still proved the padding)"
  else
    # An earlier run whose VM was stopped mid-transaction leaves db.lck behind;
    # nothing else writes there on a freshly booted test system.
    if [[ -e /var/lib/pacman/db.lck ]] && ! pgrep -x pacman >/dev/null 2>&1; then
      run_root rm -f /var/lib/pacman/db.lck
      ok "removed a stale pacman lock left by an earlier run"
    fi
    paclog=$(mktemp)
    # --overwrite is not needed; a reinstall of the same version is a normal
    # Upgrade operation for alpm, which is what the hook triggers on.
    if printf '%s\n' "${INSTALL_PASS:-}" | $SUDO pacman -S --noconfirm linux >"$paclog" 2>&1; then
      ok "pacman reinstalled the linux kernel package"
    else
      fail "pacman -S linux failed"
      tail -15 "$paclog"
    fi
    # pacman does not print hook descriptions, so look for what the padder
    # itself writes for the kernel it just installed: "padded vmlinuz-linux by
    # N bytes" or "ok: vmlinuz-linux N bytes (aligned)".
    if grep -qE '(padded|ok:) vmlinuz-[^ ]+ ' "$paclog"; then
      ok "pacman ran the alpm hook: $(grep -m1 -E '(padded|ok:) vmlinuz-' "$paclog")"
    else
      fail "the alpm hook did not run"
      grep -i 'hook' "$paclog" | head -5
    fi
    grep -iE 'padded|aligned' "$paclog" | head -8
    if pacman -Q linux >/dev/null 2>&1; then ok "package after: $(pacman -Q linux)"; fi
    aligned_report || true
  fi
else
  fail "pacman is missing"
fi

echo "=== step 3: a manual run of the padder is a no-op"
if run_root /usr/bin/mahadevanos-padboot -q; then
  ok "mahadevanos-padboot -q exits 0 on an aligned /boot"
else
  fail "mahadevanos-padboot -q failed on an aligned /boot"
fi

echo "=== /boot flags and sizes"
lsattr -d /boot 2>/dev/null
ls -l /boot/vmlinuz-* /boot/initramfs-*.img 2>/dev/null

echo
if (( rc == 0 )); then
  echo "PADBOOT RESULT: PASSED"
else
  echo "PADBOOT RESULT: FAILED"
fi
exit "$rc"
