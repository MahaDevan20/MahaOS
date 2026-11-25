#!/usr/bin/env bash
# M3 phase A: prove the Btrfs snapshot stack on a REAL installed system.
#
#   tests/install/snapshots-check.sh        (as the installed user, elevates itself)
#
# Run on an installed disk (scripts/test-install-auto.sh --snapshots). It is not a
# read-only inspection: it changes the system on purpose, then leaves it broken so
# the next phase can boot a snapshot and roll back.
#
#   1. the Arch Wiki layout: @ @home @log @cache @snapshots and their mount points;
#   2. snapper root config, snap-pac, grub-btrfs(+d), the overlayfs initramfs hook,
#      btrfs-assistant, and the units that enforce retention;
#   3. a kernel upgrade and a test package install each create a pre/post pair;
#   4. mahadevanos-snapshot-guard marks the newest snapshot important=yes (so
#      cleanup cannot delete the last known-good state) and is idempotent;
#   5. GRUB gets a Snapshots submenu that contains that snapshot, `linux` stays
#      entry 0, `linux-lts` entry 3, and the menu timeout is >= 3 seconds;
#   6. /boot is still 4096-aligned inside the live tree AND inside the snapshot
#      (the padboot hooks and the snapshot boot have to agree);
#   7. /usr/bin/kitty is deleted to break the system;
#   8. the GRUB navigation plan for the snapshot containing the good state is
#      printed for phase B (tests/install/snapshot-boot-check.sh).
set -uo pipefail

rc=0
fail() { echo "FAIL $*"; rc=1; }
ok()   { echo "ok: $*"; }

SUDO=""
if [[ $(id -u) -ne 0 ]]; then
  if [[ -z "${INSTALL_PASS:-}" ]]; then
    fail "not root and INSTALL_PASS is not set"
    echo "SNAPSHOTS RESULT: FAILED"
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

echo "=== layout: @ @home @log @cache @snapshots"
[[ "$(findmnt -no FSTYPE / 2>/dev/null)" == "btrfs" ]] && ok "/ is btrfs" || fail "/ is not btrfs"
for pair in "/:@:/" "/home:@home:/home" "/var/log:@log:/var/log" "/var/cache:@cache:/var/cache" "/.snapshots:@snapshots:/.snapshots"; do
  mp="${pair%%:*}"; rest="${pair#*:}"; sv="${rest%%:*}"
  opts="$(findmnt -no OPTIONS "$mp" 2>/dev/null)"
  case "$opts" in
    *"subvol=/$sv"*|*"subvol=$sv"*) ok "$mp is the $sv subvolume" ;;
    *) fail "$mp is not mounted from $sv (options: ${opts:-not a mount point})" ;;
  esac
done
subvols="$(run_root btrfs subvolume list / 2>/dev/null)"
for sv in @ @home @log @cache @snapshots; do
  if grep -qE "path $sv\$" <<<"$subvols"; then ok "subvolume $sv exists"; else fail "subvolume $sv is missing"; fi
done
if run_root btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  ok "/.snapshots is a btrfs subvolume (snapshots do not live inside @)"
else
  fail "/.snapshots is not a btrfs subvolume; a rollback of @ would delete the snapshots"
fi

echo "=== packages and units"
for pkg in snapper snap-pac grub-btrfs btrfs-progs btrfs-assistant; do
  if pacman -Q "$pkg" >/dev/null 2>&1; then ok "package $(pacman -Q "$pkg")"; else fail "$pkg is not installed"; fi
done
for unit in grub-btrfsd.service snapper-timeline.timer snapper-cleanup.timer \
            snapper-boot.timer mahadevanos-snapshot-guard.timer; do
  state="$(systemctl is-enabled "$unit" 2>/dev/null)"
  if [[ "$state" == "enabled" ]]; then ok "$unit is enabled"; else fail "$unit is not enabled (state: ${state:-none})"; fi
done
[[ -x /usr/bin/mahadevanos-snapshot-guard ]] && ok "mahadevanos-snapshot-guard present" \
  || fail "mahadevanos-snapshot-guard missing"
printf 'grub-btrfsd: %s\n' "$(systemctl is-active grub-btrfsd.service 2>/dev/null)"
systemctl --no-pager --no-legend 'list-timers' 'snapper*' 'mahadevanos*' 2>/dev/null | head -10

echo "=== snapper configuration and retention limits"
cfg=/etc/snapper/configs/root
if run_root test -f "$cfg"; then
  ok "snapper config $cfg exists"
  run_root grep -E '^(SUBVOLUME|NUMBER_CLEANUP|NUMBER_MIN_AGE|NUMBER_LIMIT|NUMBER_LIMIT_IMPORTANT|TIMELINE_CLEANUP|TIMELINE_LIMIT_(HOURLY|DAILY|WEEKLY|MONTHLY)|SPACE_LIMIT|FREE_LIMIT)=' "$cfg" \
    | while IFS= read -r line; do printf '     %s\n' "$line"; done
  run_root grep -q '^SUBVOLUME="/"' "$cfg" && ok 'SUBVOLUME="/"' || fail "SUBVOLUME is not /"
  for key in NUMBER_CLEANUP NUMBER_LIMIT NUMBER_LIMIT_IMPORTANT TIMELINE_CLEANUP SPACE_LIMIT FREE_LIMIT; do
    run_root grep -qE "^$key=" "$cfg" || fail "$key is missing from the snapper config"
  done
  limit="$(run_root sed -n 's/^NUMBER_LIMIT="\{0,1\}\([0-9-]*\).*/\1/p' "$cfg" | head -1)"
  if [[ -n "$limit" ]] && (( ${limit%%-*} <= 50 )); then
    ok "NUMBER_LIMIT=$limit bounds the number snapshots"
  else
    fail "NUMBER_LIMIT is not a small number (got '${limit:-none}')"
  fi
else
  fail "no snapper config at $cfg"
fi
if run_root snapper -c root list -t all >/dev/null 2>&1; then ok "snapper -c root list works"; else fail "snapper -c root list failed"; fi

echo "=== the snapper configuration list the rest of the stack reads"
# snap-pac reads /etc/snapper/snapper and crashes (aborting the pacman
# transaction, AbortOnFail) when it is missing; systemd-helper reads
# /etc/conf.d/snapper, and with the package default SNAPPER_CONFIGS="" the
# timeline and cleanup timers silently do nothing.
for conf in /etc/snapper/snapper /etc/conf.d/snapper; do
  if run_root grep -qE '^SNAPPER_CONFIGS="[^"]*root' "$conf" 2>/dev/null; then
    ok "$conf lists root"
  else
    fail "$conf does not list the root configuration"
  fi
done

# The enforcer of the retention policy: systemd-helper --cleanup is what actually
# deletes old snapshots, so prove it is wired to the timer and can run.
if run_root systemctl show -p ExecStart snapper-cleanup.service 2>/dev/null | grep -q 'systemd-helper --cleanup'; then
  ok "snapper-cleanup.service runs systemd-helper --cleanup"
else
  fail "snapper-cleanup.service is not wired to systemd-helper"
fi
run_root systemctl is-active snapper-timeline.timer snapper-cleanup.timer 2>/dev/null | tr '\n' ' '
printf '\n'
for t in snapper-timeline.timer snapper-cleanup.timer; do
  if [[ "$(run_root systemctl is-active "$t" 2>/dev/null)" == "active" ]]; then
    ok "$t is active"
  else
    fail "$t is not active"
  fi
done

# A real cleanup pass must run and keep the anchor: NUMBER_CLEANUP is what deletes
# old snapshots, and a failure here would mean the disk can fill up.
if run_root snapper -c root cleanup number >/tmp/snapper-cleanup.log 2>&1; then
  ok "snapper -c root cleanup number runs"
else
  fail "snapper -c root cleanup number failed"
  tail -5 /tmp/snapper-cleanup.log
fi

 echo "=== grub-btrfs configuration"
gcfg=/etc/default/grub-btrfs/config
if run_root test -f "$gcfg"; then
  run_root grep -E '^(GRUB_BTRFS_SUBMENUNAME|GRUB_BTRFS_LIMIT|GRUB_BTRFS_OVERRIDE_BOOT_PARTITION_DETECTION|GRUB_BTRFS_GRUB_DIRNAME)=' "$gcfg" \
    | while IFS= read -r line; do printf '     %s\n' "$line"; done
  run_root grep -q '^GRUB_BTRFS_SUBMENUNAME="Snapshots"' "$gcfg" \
    && ok 'the GRUB submenu is named "Snapshots"' || fail "the GRUB submenu is not named Snapshots"
else
  fail "$gcfg is missing"
fi

echo "=== overlayfs initramfs hook (read-only snapshot boot)"
if run_root grep -q 'grub-btrfs-overlayfs' /etc/mkinitcpio.conf; then
  ok "/etc/mkinitcpio.conf lists the grub-btrfs-overlayfs hook"
else
  fail "grub-btrfs-overlayfs is missing from /etc/mkinitcpio.conf"
fi
for img in /boot/initramfs-linux.img /boot/initramfs-linux-lts.img; do
  [[ -f "$img" ]] || continue
  if run_root lsinitcpio "$img" 2>/dev/null | grep -q 'grub-btrfs-overlayfs'; then
    ok "$(basename "$img") contains the overlayfs hook"
  else
    fail "$(basename "$img") has no overlayfs hook: a snapshot boot would be read-only and unusable"
  fi
done

echo "=== snapshots before this run"
run_root snapper -c root list -t all 2>/dev/null | tail -12
# Parsed from the plain table, whose first column is the snapshot number. 0 is
# snapper's pseudo-entry for the live filesystem, not a snapshot.
snap_table() { run_root snapper -c root list -t all 2>/dev/null; }
snapshot_numbers() {
  snap_table | sed -e 's/[│|].*//' -e 's/[^0-9]//g' | grep -E '^[1-9][0-9]*$'
}
count_snapshots() { snapshot_numbers | wc -l | tr -d ' '; }
before="$(count_snapshots)"
printf 'snapshot count before: %s\n' "$before"

network_up() { timeout 30 ping -c1 -W2 archlinux.org >/dev/null 2>&1 || timeout 30 ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; }
if ! network_up; then
  fail "no network in the guest: pacman cannot create the snapshots this test needs"
  echo "SNAPSHOTS RESULT: FAILED"
  exit 1
fi
if [[ -e /var/lib/pacman/db.lck ]] && ! pgrep -x pacman >/dev/null 2>&1; then
  run_root rm -f /var/lib/pacman/db.lck
  ok "removed a stale pacman lock left by an earlier run"
fi

# A kernel upgrade is the interesting case: the snapshot must carry a kernel AND
# its modules, or a rollback leaves the system unable to boot.
echo "=== a kernel upgrade creates a pre/post pair"
# Refresh the sync database first: the ISO ships a local snapshot of the
# repositories, and the kernel in it may already be a version behind Arch. With
# the database refreshed, `pacman -S linux` is a real upgrade whenever one is
# available (it prints a note when the installed version is already current).
if printf '%s\n' "$INSTALL_PASS" | $SUDO pacman -Sy >/dev/null 2>&1; then
  ok "pacman -Sy refreshed the sync database"
else
  fail "pacman -Sy failed"
fi
kbefore="$(pacman -Q linux 2>/dev/null)"
printf 'linux before: %s\n' "$kbefore"
klog=$(mktemp)
if printf '%s\n' "$INSTALL_PASS" | $SUDO pacman -S --noconfirm linux >"$klog" 2>&1; then
  ok "pacman -S linux succeeded"
  ok "linux after:  $(pacman -Q linux 2>/dev/null)"
else
  fail "pacman -S linux failed"
  tail -15 "$klog"
fi
after_kernel="$(count_snapshots)"
if (( after_kernel >= before + 2 )); then
  ok "the kernel transaction added $(( after_kernel - before )) snapshots (pre + post)"
else
  fail "the kernel transaction added only $(( after_kernel - before )) snapshots"
fi

echo "=== a test package install creates a pre/post pair"
before_pkg="$(count_snapshots)"
plog=$(mktemp)
if printf '%s\n' "$INSTALL_PASS" | $SUDO pacman -S --noconfirm tree >"$plog" 2>&1; then
  ok "pacman -S tree succeeded"
  pacman -Q tree 2>/dev/null
else
  fail "pacman -S tree failed"
  tail -15 "$plog"
fi
after_pkg="$(count_snapshots)"
if (( after_pkg >= before_pkg + 2 )); then
  ok "the package transaction added $(( after_pkg - before_pkg )) snapshots (pre + post)"
else
  fail "the package transaction added only $(( after_pkg - before_pkg )) snapshots"
fi

echo "=== the newest transaction is a pre/post pair"
mapfile -t tail_types < <(snap_table | awk -F'[│|]' 'NF>1 {t=$2; gsub(/[^a-z]/,"",t); if (t != "") print t}' | tail -2)
printf '     last two snapshot types: %s\n' "${tail_types[*]:-none}"
if [[ "${tail_types[0]:-}" == "pre" && "${tail_types[1]:-}" == "post" ]]; then
  ok "the newest snapshots are a pre/post pair, in order"
else
  fail "the newest snapshots are not a pre/post pair: ${tail_types[*]:-none}"
fi

echo "=== the last known-good snapshot is protected"
if run_root /usr/bin/mahadevanos-snapshot-guard; then ok "mahadevanos-snapshot-guard ran"; else fail "mahadevanos-snapshot-guard failed"; fi
if run_root /usr/bin/mahadevanos-snapshot-guard -q; then ok "a second run is a no-op"; else fail "the guard is not idempotent"; fi
newest="$(snapshot_numbers | sort -n | tail -1)"
printf 'newest snapshot: %s\n' "${newest:-none}"
if [[ -n "$newest" ]]; then
  udata="$(snap_table | grep -E "^[[:space:]]*$newest[[:space:]]*[│|]" || true)"
  printf '     %s\n' "${udata:-<no row>}"
  if grep -q 'important=yes' <<<"$udata"; then
    ok "snapshot $newest is marked important=yes (cleanup cannot delete it)"
  else
    fail "snapshot $newest is not marked important: a cleanup run could delete the last known-good state"
  fi
  if run_root cat /var/lib/mahadevanos/snapshot-anchor 2>/dev/null | grep -qx "$newest"; then
    ok "the anchor state file records snapshot $newest"
  else
    fail "the anchor state file does not record snapshot $newest"
  fi
else
  fail "could not determine the newest snapshot"
fi

echo "=== GRUB: Snapshots submenu, kernel order and the timeout"
if run_root /etc/grub.d/41_snapshots-btrfs >/tmp/grub-btrfs.log 2>&1; then ok "41_snapshots-btrfs ran"; else fail "41_snapshots-btrfs failed"; fi
tail -5 /tmp/grub-btrfs.log
if run_root grub-mkconfig -o /boot/grub/grub.cfg >/tmp/grub-mkconfig.log 2>&1; then
  ok "grub-mkconfig regenerated grub.cfg"
else
  fail "grub-mkconfig failed"
  tail -15 /tmp/grub-mkconfig.log
fi
run_root cp /boot/grub/grub.cfg /tmp/grub.cfg.audit 2>/dev/null || true
run_root cp /boot/grub/grub-btrfs.cfg /tmp/grub-btrfs.cfg.audit 2>/dev/null || true
run_root chmod a+r /tmp/grub.cfg.audit /tmp/grub-btrfs.cfg.audit 2>/dev/null || true

if grep -q "submenu 'Snapshots'" /tmp/grub.cfg.audit; then
  ok "grub.cfg contains a Snapshots submenu"
else
  fail "grub.cfg has no Snapshots submenu"
fi
if grep -q 'grub-btrfs.cfg' /tmp/grub.cfg.audit; then ok "grub.cfg sources grub-btrfs.cfg"; else fail "grub.cfg does not source grub-btrfs.cfg"; fi
# grub-mkconfig indents the timeout inside `if [ x$feature_timeout_style = xy ]`.
timeout_value="$(sed -n 's/^[[:space:]]*set timeout=\([0-9-]*\).*/\1/p' /tmp/grub.cfg.audit | head -1)"
printf 'grub.cfg set timeout=%s\n' "${timeout_value:-none}"
if [[ -n "$timeout_value" ]] && (( timeout_value >= 3 )); then
  ok "the GRUB menu is visible for ${timeout_value}s (>= 3)"
else
  fail "the GRUB timeout is '${timeout_value:-unset}', needs >= 3 seconds"
fi
default_timeout="$(sed -n 's/^GRUB_TIMEOUT=//p' /etc/default/grub | tr -dc '0-9' | head -1)"
printf '/etc/default/grub GRUB_TIMEOUT=%s\n' "${default_timeout:-none}"
if [[ -n "$default_timeout" ]] && (( default_timeout >= 3 )); then
  ok "/etc/default/grub keeps the menu visible for ${default_timeout}s"
else
  fail "/etc/default/grub GRUB_TIMEOUT is not >= 3"
fi

# Entry 0 must be `linux` and entry 3 `linux-lts`, with the snapshots submenu
# after every kernel entry (that is what scripts/test-install-auto.sh relies on).
mapfile -t entry_kernels < <(awk '
  /^menuentry / { idx++; want=1; next }
  want && /vmlinuz-/ {
    line=$0; sub(/.*vmlinuz-/, "vmlinuz-", line); sub(/[ \t].*/, "", line)
    print idx-1, line; want=0
  }
' /tmp/grub.cfg.audit)
printf '     entry %s\n' "${entry_kernels[@]}"
if [[ "${entry_kernels[0]}" == "0 vmlinuz-linux" ]]; then
  ok "GRUB entry 0 is the regular linux kernel"
else
  fail "GRUB entry 0 is '${entry_kernels[0]:-none}', not vmlinuz-linux"
fi
if printf '%s\n' "${entry_kernels[@]}" | grep -qx '3 vmlinuz-linux-lts'; then
  ok "GRUB entry 3 is the linux-lts fallback"
else
  fail "linux-lts is not entry 3 (see the list above)"
fi
submenu_line="$(grep -n "submenu 'Snapshots'" /tmp/grub.cfg.audit | head -1 | cut -d: -f1)"
last_entry_line="$(grep -n '^menuentry ' /tmp/grub.cfg.audit | tail -1 | cut -d: -f1)"
if [[ -n "$submenu_line" && -n "$last_entry_line" ]] && (( submenu_line > last_entry_line )); then
  ok "the Snapshots submenu comes after all kernel entries"
else
  fail "the Snapshots submenu is not after the kernel entries"
fi

echo "=== the snapshot is bootable: grub-btrfs.cfg lists it"
run_root grep -cE '^[[:space:]]*menuentry ' /tmp/grub-btrfs.cfg.audit 2>/dev/null |
  while IFS= read -r n; do printf '     grub-btrfs.cfg menuentries: %s\n' "$n"; done
if grep -q "/@snapshots/$newest/snapshot" /tmp/grub-btrfs.cfg.audit 2>/dev/null; then
  ok "grub-btrfs.cfg boots /@snapshots/$newest/snapshot"
else
  fail "grub-btrfs.cfg has no entry for snapshot $newest"
  grep -o 'subvol=/@snapshots/[0-9]*/snapshot' /tmp/grub-btrfs.cfg.audit 2>/dev/null | sort -u | head -5
fi
# The kernel line has to name the snapshot as a subvolume; grub-btrfs quotes the
# value and the leading slash varies by version, so look at the line itself.
snapshot_line="$(grep -m1 '/@snapshots/' /tmp/grub-btrfs.cfg.audit 2>/dev/null || true)"
if grep -q 'subvol=' <<<"$snapshot_line"; then
  ok "grub-btrfs.cfg points the kernel at the snapshot subvolume"
else
  fail "grub-btrfs.cfg's snapshot line has no subvol=: ${snapshot_line:-<no line>}"
fi

echo "=== /boot alignment survives into the snapshot (padboot compatibility)"
align_report() {
  local f size bad=0
  for f in /boot/vmlinuz-* /boot/initramfs-*.img; do
    [[ -f "$f" ]] || continue
    size=$(stat -c %s "$f")
    if (( size % 4096 == 0 )); then ok "$(basename "$f") $size bytes (aligned)"; else fail "$(basename "$f") $size bytes is not aligned"; bad=1; fi
  done
  return $bad
}
align_report || true
if [[ -n "$newest" ]]; then
  snap_boot="/.snapshots/$newest/snapshot/boot"
  if run_root test -d "$snap_boot"; then
    ok "the snapshot contains its own /boot"
    for f in vmlinuz-linux vmlinuz-linux-lts initramfs-linux.img initramfs-linux-lts.img; do
      size="$(run_root stat -c %s "$snap_boot/$f" 2>/dev/null)"
      if [[ -n "$size" ]] && (( size % 4096 == 0 )); then
        ok "snapshot $f is $size bytes (aligned)"
      else
        fail "snapshot $f is '${size:-missing}' bytes; GRUB would read it short"
      fi
    done
    if run_root lsinitcpio "$snap_boot/initramfs-linux.img" 2>/dev/null | grep -q 'grub-btrfs-overlayfs'; then
      ok "the snapshot's initramfs has the overlayfs hook"
    else
      fail "the snapshot's initramfs has no overlayfs hook: it cannot boot read-only"
    fi
  else
    fail "snapshot $newest has no /boot directory"
  fi
fi

echo "=== breaking the system on purpose"
run_root rm -f /usr/bin/kitty
run_root sh -c 'printf "%s\n" "deliberately broken by tests/install/snapshots-check.sh" >/etc/mahadevanos-snapshot-broken'
if command -v kitty >/dev/null 2>&1; then
  fail "kitty is still runnable; the system is not broken and the rollback proves nothing"
else
  ok "/usr/bin/kitty deleted (the snapshot still has it)"
fi
if [[ -e /etc/mahadevanos-snapshot-broken ]]; then
  ok "the break marker /etc/mahadevanos-snapshot-broken exists"
else
  fail "could not write the break marker"
fi

echo "=== GRUB plan for phase B (boot snapshot $newest)"
top_entries="$(grep -c '^menuentry ' /tmp/grub.cfg.audit)"
sub_idx="$(awk -v want="/@snapshots/$newest/snapshot" '
  /^[[:space:]]*menuentry / { idx++ }
  idx && index($0, want) { print idx-1; exit }
' /tmp/grub-btrfs.cfg.audit 2>/dev/null)"
printf 'top-level menuentries: %s\n' "${top_entries:-0}"
if [[ -z "$sub_idx" ]]; then
  fail "could not find snapshot $newest inside the Snapshots submenu"
  sub_idx=0
else
  ok "snapshot $newest is submenu entry $sub_idx"
fi
printf 'SNAPSHOT TO BOOT: %s\n' "${newest:-none}"
printf 'SNAPSHOT BOOT PLAN: down %s right 1 subdown %s\n' "${top_entries:-0}" "$sub_idx"

echo
if (( rc == 0 )); then
  echo "SNAPSHOTS RESULT: PASSED"
else
  echo "SNAPSHOTS RESULT: FAILED"
fi
# Phase B needs a cleanly shut down disk, but the caller's line after this
# payload is `echo PAYLOAD-EXIT:$?`: a poweroff here would silence it. Shut down
# a few seconds later instead, and let the host wait for the VM to exit.
run_root sh -c 'nohup sh -c "sleep 4; systemctl poweroff" >/dev/null 2>&1 &' || true
exit "$rc"
