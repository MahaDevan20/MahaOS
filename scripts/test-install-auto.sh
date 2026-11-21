#!/usr/bin/env bash
# Unattended install test on a throwaway qcow2 disk, then a boot of that disk
# without the ISO.
#
#   scripts/test-install-auto.sh --install         fresh disk + rehearsal install
#   scripts/test-install-auto.sh --boot-installed  boot the installed disk only
#
# What --install does: boots the ISO with build/test-disk.qcow2 attached, logs in
# on the serial console and runs tests/install/rehearsal.sh inside the guest. That
# script does what Calamares' partition, mount, unpackfs, shellprocess and
# bootloader modules do (Btrfs subvolumes, unsquashfs, every postinstall script,
# grub-install) on /dev/vda. It is NOT the Calamares GUI — see
# documentation/installation/manual-test.md for the human walkthrough.
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
case "$MODE" in
  --install|--boot-installed) ;;
  *) die "usage: $0 --install | --boot-installed" ;;
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

cleanup() {
  monitor "quit" >/dev/null 2>&1 || true
  [[ -f "$PIDFILE" ]] && kill "$(cat "$PIDFILE")" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

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

    log "booting the ISO with $DISK attached (rehearsal install, no GUI)"
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
    log "rehearsal exit status: $STATUS (evidence: $LOG)"
    exit "$STATUS"
    ;;

  --boot-installed)
    [[ -f "$DISK" ]] || die "$DISK does not exist; run --install first"

    log "booting $DISK without the ISO"
    start_vm

    LOG="$EVIDENCE_DIR/installed-boot.log"
    SUMMARY="$EVIDENCE_DIR/installed-boot.txt"
    : >"$LOG"
    STATUS=0
    LIVE_USER=tester LIVE_PASS=test USE_SUDO=0 LOGIN_TIMEOUT=300 RUN_TIMEOUT=600 \
      python3 "$PROJECT_ROOT/scripts/qemu-serial-run.py" \
      "$SER_SOCK" "$LOG" "$PROJECT_ROOT/tests/install/verify-installed.sh" "$SUMMARY" || STATUS=$?
    log "installed-system verification exit status: $STATUS"
    exit "$STATUS"
    ;;
esac
