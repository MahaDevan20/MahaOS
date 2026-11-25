#!/usr/bin/env bash
# Unattended install test on a throwaway qcow2 disk, then boots of that disk
# without the ISO — once per installed kernel.
#
#   scripts/test-install-auto.sh --install
#   scripts/test-install-auto.sh --boot-installed [--kernel linux|linux-lts|both]
#   scripts/test-install-auto.sh --padboot
#   scripts/test-install-auto.sh --snapshots
#   scripts/test-install-auto.sh --snapshot-boot
#
# --install boots the ISO with build/test-disk.qcow2 attached, logs in on the
# serial console and runs tests/install/rehearsal.sh inside the guest. That script
# runs every module of the shipped settings.conf exec sequence — partition, mount,
# unpackfs, displaymanager, networkcfg, hwclock, services-systemd, the postinstall
# scripts, grubcfg and bootloader — reading each module's configuration from
# /etc/calamares/modules/, and it audits those configs against the Calamares 3.4.2
# schema. It is not the Calamares GUI; see documentation/installation/manual-test.md.
#
# --boot-installed boots the disk without the ISO, picks the GRUB entry over the
# serial console (entry 0 = linux, entry 1 = linux-lts) and runs
# tests/install/verify-installed.sh as the unprivileged account the install
# created: INSTALL_USER/INSTALL_PASS (default tester/test, which is what the
# rehearsal installs; scripts/test-install-gui.sh uses its own values).
#
# --padboot boots the installed disk once, runs tests/install/padboot-check.sh as
# the installed user (which elevates itself with INSTALL_PASS, forwarded into the
# guest through qemu-serial-run.py's REMOTE_ENV) and requires it to report PASSED: it
# unaligns an initramfs, runs `mkinitcpio -P`, reinstalls the linux kernel with
# pacman, and checks that the mkinitcpio post hook and the alpm hook put every
# /boot file back on a 4096-byte boundary. Run it before --boot-installed, so the
# two-kernel boots prove the changed system still boots.
#
# --snapshots runs tests/install/snapshots-check.sh on the installed disk (phase A):
# it upgrades the kernel and installs a test package to prove snap-pac brackets every
# transaction, checks the snapper retention limits and the anchor snapshot, audits the
# GRUB Snapshots submenu and the >= 3s timeout, then deletes /usr/bin/kitty and powers
# off. It prints the GRUB navigation to that snapshot, which this script stores in
# build/snapshot-boot-plan.
#
# --snapshot-boot reads that plan, boots the snapshot from the submenu over the serial
# console and runs tests/install/snapshot-boot-check.sh (phase B): overlay root, the
# snapshot still read-only and intact, then the documented manual rollback
# (@ -> @.broken, @snapshots/<N>/snapshot -> @, chroot, mkinitcpio -P, grub-mkconfig).
# Follow it with --boot-installed --kernel both, which is what proves both kernels
# boot a rolled-back system.
#
# No real disk is reachable: the only block device with a size is the qcow2 file.
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require qemu-system-x86_64 qemu-img python3

DISK="$BUILD_DIR/test-disk.qcow2"
DISK_SIZE="${DISK_SIZE:-40G}"
ISO="$(find "$OUT_DIR" -maxdepth 1 -name 'mahadevanos-*.iso' -type f | sort | tail -1)"
EVIDENCE_DIR="${EVIDENCE_DIR:-$PROJECT_ROOT/tests/evidence/$(date +%Y-%m-%d)}"
mkdir -p "$EVIDENCE_DIR"

OVMF_CODE=""
for p in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
         /usr/share/OVMF/OVMF_CODE.fd; do
  [[ -f "$p" ]] && { OVMF_CODE="$p"; break; }
done
[[ -n "$OVMF_CODE" ]] || die "OVMF firmware not found (pacman -S edk2-ovmf)"
OVMF_VARS_SRC="${OVMF_CODE/CODE/VARS}"

MODE="${1:-}"
KERNELS="both"
PLAN_FILE="$BUILD_DIR/snapshot-boot-plan"
case "$MODE" in
  --install|--boot-installed|--padboot|--snapshots|--snapshot-boot) shift || true ;;
  *) die "usage: $0 --install | --boot-installed [--kernel ...] | --padboot | --snapshots | --snapshot-boot" ;;
esac
while (( $# )); do
  case "$1" in
    --kernel) KERNELS="${2:-}"; shift 2 ;;
    --kernel=*) KERNELS="${1#*=}"; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$KERNELS" in
  linux|linux-lts) ;;
  both) [[ "$MODE" == "--boot-installed" ]] || KERNELS="linux" ;;
  *) die "--kernel must be linux, linux-lts or both" ;;
esac

VARS="$BUILD_DIR/OVMF_VARS-install.fd"
MON_SOCK="$BUILD_DIR/qemu-monitor-install.sock"
SER_SOCK="$BUILD_DIR/qemu-serial-install.sock"
PIDFILE="$BUILD_DIR/qemu-install.pid"

monitor() {
  python3 - "$MON_SOCK" "$1" <<'PY'
import socket, sys, time
path, cmd = sys.argv[1], sys.argv[2]
for _ in range(40):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(path)
        break
    except OSError:
        time.sleep(0.25)
else:
    sys.exit("monitor socket unavailable")
s.settimeout(5)
time.sleep(0.2)
s.sendall(f"{cmd}\n".encode())
time.sleep(0.4)
try:
    print(s.recv(65536).decode(errors="replace"))
except TimeoutError:
    pass
s.close()
PY
}

stop_vm() {
  monitor "quit" >/dev/null 2>&1 || true
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
  sleep 1
}

# The snapshot phases power the guest off on purpose (a clean btrfs shutdown before
# the next phase reads or rewrites the disk), a few seconds after their payload
# exits. Wait for the VM to go away instead of pulling the virtual plug.
wait_guest_poweroff() {
  local pid timeout="${1:-180}" waited=0
  [[ -f "$PIDFILE" ]] || return 0
  pid="$(cat "$PIDFILE")"
  while (( waited < timeout )) && kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$(( waited + 1 ))
  done
  if kill -0 "$pid" 2>/dev/null; then
    warn "the guest did not power off within ${timeout}s; stopping the VM"
    stop_vm
  else
    rm -f "$PIDFILE"
    log "guest powered off cleanly after ${waited}s"
  fi
}
trap stop_vm EXIT INT TERM

accel=()
[[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)

rm -f "$MON_SOCK" "$SER_SOCK" "$PIDFILE"
cp "$OVMF_VARS_SRC" "$VARS"

start_vm() {
  qemu-system-x86_64 \
    "${accel[@]}" -smp 4 -m 6144 \
    -machine q35 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$VARS" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    "$@" \
    -device virtio-vga -display none \
    -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
    -serial "unix:$SER_SOCK,server,nowait" \
    -monitor "unix:$MON_SOCK,server,nowait" \
    -pidfile "$PIDFILE" \
    -daemonize
}

case "$MODE" in
  --install)
    [[ -n "$ISO" ]] || die "no ISO in $OUT_DIR; run scripts/build-iso.sh first"
    if [[ -f "$DISK" ]]; then
      log "recreating $DISK ($DISK_SIZE, qcow2, virtual only)"
      rm -f "$DISK"
    fi
    qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null

    log "booting the ISO with $DISK attached (scripted install, no GUI)"
    start_vm -cdrom "$ISO" -boot d

    LOG="$EVIDENCE_DIR/install-rehearsal.log"
    SUMMARY="$EVIDENCE_DIR/install-rehearsal.txt"
    # qemu-serial-run.py appends; start each run with a clean log so the
    # evidence file contains only this run.
    : >"$LOG"
    STATUS=0
    LOGIN_TIMEOUT=300 RUN_TIMEOUT="${INSTALL_TIMEOUT:-3600}" \
      python3 "$PROJECT_ROOT/scripts/qemu-serial-run.py" \
      "$SER_SOCK" "$LOG" "$PROJECT_ROOT/tests/install/rehearsal.sh" "$SUMMARY" || STATUS=$?
    log "install exit status: $STATUS (evidence: $LOG)"
    exit "$STATUS"
    ;;

  --padboot)
    [[ -f "$DISK" ]] || die "$DISK does not exist; run --install or the GUI test first"
    log "booting $DISK without the ISO to exercise the /boot alignment hooks"
    rm -f "$MON_SOCK" "$SER_SOCK" "$PIDFILE"
    start_vm

    PAD_LOG="$EVIDENCE_DIR/padboot-check-$(date +%Y%m%d-%H%M%S).log"
    PAD_SUMMARY="${PAD_LOG%.log}.txt"
    : >"$PAD_LOG"
    pad_status=0
    pass="${INSTALL_PASS:-test}"
    GRUB_DOWN=0 LIVE_USER="${INSTALL_USER:-tester}" LIVE_PASS="$pass" \
      USE_SUDO=0 REMOTE_ENV="INSTALL_PASS='$pass'" \
      LOGIN_TIMEOUT=300 RUN_TIMEOUT=1800 \
      python3 "$PROJECT_ROOT/scripts/qemu-serial-run.py" \
      "$SER_SOCK" "$PAD_LOG" "$PROJECT_ROOT/tests/install/padboot-check.sh" "$PAD_SUMMARY" \
      || pad_status=$?
    stop_vm

    if [[ -f "$PAD_SUMMARY" ]]; then
      sed -n '1,200p' "$PAD_SUMMARY" | tee -a "$PAD_LOG" >&2
    fi
    if (( pad_status != 0 )) || ! grep -q 'PADBOOT RESULT: PASSED' "$PAD_SUMMARY" 2>/dev/null; then
      warn "the /boot alignment check failed (evidence: $PAD_LOG)"
      exit 1
    fi
    log "the /boot alignment hooks work on the installed system (evidence: $PAD_LOG)"
    exit 0
    ;;

  --snapshots)
    [[ -f "$DISK" ]] || die "$DISK does not exist; run --install or the GUI test first"
    [[ -n "$ISO" ]] || warn "no ISO in $OUT_DIR (only needed for --install)"
    log "booting $DISK to exercise the snapshot stack (phase A)"
    rm -f "$MON_SOCK" "$SER_SOCK" "$PIDFILE"
    start_vm

    SNAP_LOG="$EVIDENCE_DIR/snapshots-check.log"
    SNAP_SUMMARY="$EVIDENCE_DIR/snapshots-check.txt"
    : >"$SNAP_LOG"
    snap_status=0
    pass="${INSTALL_PASS:-test}"
    GRUB_DOWN=0 LIVE_USER="${INSTALL_USER:-tester}" LIVE_PASS="$pass" \
      USE_SUDO=0 REMOTE_ENV="INSTALL_PASS='$pass'" \
      LOGIN_TIMEOUT=300 RUN_TIMEOUT="${SNAPSHOT_TIMEOUT:-2400}" \
      python3 "$PROJECT_ROOT/scripts/qemu-serial-run.py" \
      "$SER_SOCK" "$SNAP_LOG" "$PROJECT_ROOT/tests/install/snapshots-check.sh" "$SNAP_SUMMARY" \
      || snap_status=$?
    wait_guest_poweroff 240
    stop_vm

    if [[ -f "$SNAP_SUMMARY" ]]; then
      sed -n '1,400p' "$SNAP_SUMMARY" | tee -a "$SNAP_LOG" >&2
    fi
    if (( snap_status != 0 )) || ! grep -q 'SNAPSHOTS RESULT: PASSED' "$SNAP_SUMMARY" 2>/dev/null; then
      warn "the snapshot stack check failed (evidence: $SNAP_LOG)"
      exit 1
    fi
    plan="$(sed -n 's/^SNAPSHOT BOOT PLAN: //p' "$SNAP_SUMMARY" | head -1)"
    if [[ -z "$plan" ]]; then
      warn "phase A printed no snapshot boot plan (evidence: $SNAP_SUMMARY)"
      exit 1
    fi
    printf '%s\n' "$plan" >"$PLAN_FILE"
    log "snapshots created, protected and listed in GRUB; boot plan: $plan"
    exit 0
    ;;

  --snapshot-boot)
    [[ -f "$DISK" ]] || die "$DISK does not exist; run --install first"
    [[ -f "$PLAN_FILE" ]] || die "no $PLAN_FILE; run --snapshots first"
    read -r plan <"$PLAN_FILE"
    # "down <N> right <R> subdown <M>" from tests/install/snapshots-check.sh.
    grub_down="" grub_right=0 grub_sub_down=0
    read -r _ grub_down _ grub_right _ grub_sub_down <<<"$plan"
    [[ "$grub_down" =~ ^[0-9]+$ ]] || die "unreadable boot plan '$plan' in $PLAN_FILE"
    log "booting the snapshot: GRUB plan '$plan' (down $grub_down, right $grub_right, subdown $grub_sub_down)"
    rm -f "$MON_SOCK" "$SER_SOCK" "$PIDFILE"
    start_vm

    SNAPBOOT_LOG="$EVIDENCE_DIR/snapshot-boot.log"
    SNAPBOOT_SUMMARY="$EVIDENCE_DIR/snapshot-boot.txt"
    : >"$SNAPBOOT_LOG"
    snapboot_status=0
    pass="${INSTALL_PASS:-test}"
    GRUB_DOWN="$grub_down" GRUB_RIGHT="$grub_right" GRUB_SUB_DOWN="$grub_sub_down" \
      LIVE_USER="${INSTALL_USER:-tester}" LIVE_PASS="$pass" \
      USE_SUDO=0 REMOTE_ENV="INSTALL_PASS='$pass'" \
      LOGIN_TIMEOUT=300 RUN_TIMEOUT="${SNAPSHOT_TIMEOUT:-2400}" \
      python3 "$PROJECT_ROOT/scripts/qemu-serial-run.py" \
      "$SER_SOCK" "$SNAPBOOT_LOG" "$PROJECT_ROOT/tests/install/snapshot-boot-check.sh" "$SNAPBOOT_SUMMARY" \
      || snapboot_status=$?
    wait_guest_poweroff 240
    stop_vm

    if [[ -f "$SNAPBOOT_SUMMARY" ]]; then
      sed -n '1,400p' "$SNAPBOOT_SUMMARY" | tee -a "$SNAPBOOT_LOG" >&2
    fi
    if (( snapboot_status != 0 )) || ! grep -q 'SNAPSHOT BOOT RESULT: PASSED' "$SNAPBOOT_SUMMARY" 2>/dev/null; then
      warn "the snapshot boot or the rollback failed (evidence: $SNAPBOOT_LOG)"
      exit 1
    fi
    log "booted snapshot $plan, verified the overlay, rolled back; now run --boot-installed --kernel both"
    exit 0
    ;;

  --boot-installed)
    [[ -f "$DISK" ]] || die "$DISK does not exist; run --install first"
    [[ -n "${ISO:-}" ]] || warn "no ISO in $OUT_DIR (only needed for --install)"

    status=0
    for kernel in $([[ "$KERNELS" == "both" ]] && echo "linux linux-lts" || echo "$KERNELS"); do
      case "$kernel" in
        # GRUB_DISABLE_SUBMENU=y gives every kernel three entries: 0..2 are
        # linux (default, fallback initramfs, recovery) and 3..5 are linux-lts.
        # tests/install/gui-install-audit.sh asserts that layout on the installed
        # grub.cfg, and the release check below catches a wrong entry.
        linux)     GRUB_INDEX=0; EXPECT='arch1'; tag="linux" ;;
        linux-lts) GRUB_INDEX=${GRUB_LTS_INDEX:-3}; EXPECT='-lts'; tag="lts" ;;
      esac

      log "booting $DISK without the ISO, GRUB entry $GRUB_INDEX ($kernel)"
      rm -f "$MON_SOCK" "$SER_SOCK" "$PIDFILE"
      start_vm

      LOG="$EVIDENCE_DIR/installed-boot-${tag}.log"
      SUMMARY="$EVIDENCE_DIR/installed-boot-${tag}.txt"
      : >"$LOG"
      run_status=0
      # INSTALL_PASS lets verify-installed.sh prove that `sudo` really elevates
      # for this account (the wheel rule), which is needed by every recovery step.
      GRUB_DOWN="$GRUB_INDEX" LIVE_USER="${INSTALL_USER:-tester}" LIVE_PASS="${INSTALL_PASS:-test}" USE_SUDO=0 \
        REMOTE_ENV="INSTALL_PASS='${INSTALL_PASS:-test}'" \
        LOGIN_TIMEOUT=300 RUN_TIMEOUT=900 \
        python3 "$PROJECT_ROOT/scripts/qemu-serial-run.py" \
        "$SER_SOCK" "$LOG" "$PROJECT_ROOT/tests/install/verify-installed.sh" "$SUMMARY" \
        || run_status=$?

      release="$(sed -n 's/^kernel release: //p' "$SUMMARY" 2>/dev/null | head -1)"
      if (( run_status != 0 )); then
        warn "installed-system verification failed on $kernel (driver exit $run_status)"
        status=1
      elif [[ -z "$release" ]]; then
        warn "no 'kernel release:' line in $SUMMARY (did the serial login work?)"
        status=1
      elif [[ "$kernel" == "linux" && "$release" != *"$EXPECT"* ]]; then
        warn "expected the regular linux kernel, but the system is running $release"
        status=1
      elif [[ "$kernel" == "linux-lts" && "$release" != *"$EXPECT" ]]; then
        warn "expected the linux-lts kernel, but the system is running $release"
        status=1
      elif ! grep -q 'VERIFY RESULT: PASSED' "$SUMMARY"; then
        warn "verify-installed.sh did not report PASSED on $kernel"
        status=1
      else
        log "$kernel: booted to the login prompt and verified, running $release"
      fi
      stop_vm
    done
    exit "$status"
    ;;
esac
