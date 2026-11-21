#!/usr/bin/env bash
# Boot the built ISO in a UEFI (OVMF) QEMU VM and capture evidence:
#   tests/evidence/<YYYY-MM-DD>/serial-<entry>.log    serial console, byte for byte
#   tests/evidence/<YYYY-MM-DD>/session-<entry>.txt   decoded probe output (ip a, …)
#   tests/evidence/<YYYY-MM-DD>/installer-<entry>.png framebuffer screenshot (Calamares)
#   tests/evidence/<YYYY-MM-DD>/menu-<entry>.png      boot menu, safe-graphics runs only
#
# The run fails if Calamares does not start by itself: the probe waits for the
# calamares process and the screenshot is read back with tesseract.
#
# Usage: scripts/test-boot.sh [--entry default|safe-graphics] [--disk]
#
# Nothing here touches a real disk: the ISO is read-only. With --disk a blank
# build/test-disk.qcow2 is attached (the Calamares welcome page requires a
# target with at least 20 GiB, so a diskless VM shows "no partitions to install
# on" even though the installer itself is running).
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ENTRY="default"
ATTACH_DISK=0
while (( $# )); do
  case "$1" in
    --entry) ENTRY="${2:-}"; shift 2 ;;
    --entry=*) ENTRY="${1#*=}"; shift ;;
    --disk) ATTACH_DISK=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (use --entry default|safe-graphics [--disk])" ;;
  esac
done
case "$ENTRY" in
  default|safe-graphics) ;;
  *) die "unknown entry '$ENTRY' (use default or safe-graphics)" ;;
esac

require qemu-system-x86_64 python3 tesseract

ISO="$(find "$OUT_DIR" -maxdepth 1 -name 'mahadevanos-*.iso' -type f | sort | tail -1)"
[[ -n "${ISO:-}" ]] || die "no ISO in $OUT_DIR; run scripts/build-iso.sh first"

OVMF_CODE=""
for p in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
         /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.fd; do
  [[ -f "$p" ]] && { OVMF_CODE="$p"; break; }
done
[[ -n "$OVMF_CODE" ]] || die "OVMF firmware not found (pacman -S edk2-ovmf)"
OVMF_VARS_SRC="${OVMF_CODE/CODE/VARS}"
[[ -f "$OVMF_VARS_SRC" ]] || die "OVMF VARS not found next to $OVMF_CODE"

EVIDENCE_DIR="${EVIDENCE_DIR:-$PROJECT_ROOT/tests/evidence/$(date +%Y-%m-%d)}"
mkdir -p "$EVIDENCE_DIR"
LOG="$EVIDENCE_DIR/serial-${ENTRY}.log"
SUMMARY="$EVIDENCE_DIR/session-${ENTRY}.txt"
SHOT="$EVIDENCE_DIR/installer-${ENTRY}.png"
MENU_SHOT="$EVIDENCE_DIR/menu-${ENTRY}.png"

VARS="$BUILD_DIR/OVMF_VARS-${ENTRY}.fd"
MON_SOCK="$BUILD_DIR/qemu-monitor-${ENTRY}.sock"
SER_SOCK="$BUILD_DIR/qemu-serial-${ENTRY}.sock"
PIDFILE="$BUILD_DIR/qemu-boot-${ENTRY}.pid"
TIMEOUT="${BOOT_TIMEOUT:-420}"
installer_missing=0

: >"$LOG"
rm -f "$MON_SOCK" "$SER_SOCK" "$SHOT" "$PIDFILE"
cp "$OVMF_VARS_SRC" "$VARS"

accel=()
[[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)

disk_args=()
if (( ATTACH_DISK )); then
  require qemu-img
  TEST_DISK="$BUILD_DIR/test-disk.qcow2"
  [[ -f "$TEST_DISK" ]] || qemu-img create -f qcow2 "$TEST_DISK" "${DISK_SIZE:-40G}" >/dev/null
  disk_args=(-drive "file=$TEST_DISK,if=virtio,format=qcow2")
  log "attaching blank virtual disk $TEST_DISK (qcow2, no host device)"
fi

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

log "booting $ISO (UEFI, entry=$ENTRY, 4 GiB RAM, ${TIMEOUT}s budget)"
qemu-system-x86_64 \
  "${accel[@]}" -smp 4 -m 4096 \
  -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -cdrom "$ISO" -boot d \
  "${disk_args[@]}" \
  -device virtio-vga -display none \
  -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
  -serial "unix:$SER_SOCK,server,nowait" \
  -monitor "unix:$MON_SOCK,server,nowait" \
  -pidfile "$PIDFILE" \
  -daemonize

# The serial driver has to attach before the guest prints, so start it first: it
# retries until QEMU creates the socket (well before the kernel starts talking).
LOGIN_TIMEOUT="$TIMEOUT" python3 "$PROJECT_ROOT/scripts/qemu-serial-login.py" \
  "$SER_SOCK" "$LOG" "$SUMMARY" &
DRIVER_PID=$!

if [[ "$ENTRY" == "safe-graphics" ]]; then
  log "selecting the 'safe graphics' menu entry (systemd-boot timeout is 5s)"
  probe="$BUILD_DIR/menu-probe-${ENTRY}.png"
  selected=""
  deadline=$(( SECONDS + 120 ))
  while (( SECONDS < deadline )); do
    rm -f "$probe"
    monitor "screendump $probe" >/dev/null 2>&1 || true
    if [[ -s "$probe" ]] && tesseract "$probe" - 2>/dev/null | grep -qi 'safe graphics'; then
      cp "$probe" "$MENU_SHOT"
      # The menu is sorted by title, so "safe graphics" sits directly above the
      # default entry: one Up press moves the highlight onto it.
      monitor "sendkey up" >/dev/null
      sleep 0.3
      monitor "sendkey ret" >/dev/null
      selected=1
      break
    fi
    sleep 0.2
  done
  if [[ -n "$selected" ]]; then
    log "menu entry selected from $MENU_SHOT"
  else
    warn "boot menu not recognised within 120s; the default entry will boot"
  fi
fi

driver_status=0
wait "$DRIVER_PID" || driver_status=$?

# The probe waits for the installer process before it returns, so the desktop
# should now show Calamares without any interaction.
sleep 5
monitor "screendump $SHOT" >/dev/null 2>&1 || warn "screendump failed"
[[ -s "$SHOT" ]] || warn "no screenshot written to $SHOT"

# Read the screen: the point of this test is that Calamares appears by itself.
if [[ -s "$SHOT" ]] && command -v tesseract >/dev/null 2>&1; then
  if tesseract "$SHOT" - 2>/dev/null | grep -qiE 'welcome|calamares|instal|next|language'; then
    log "OCR: the installer window is on screen without any interaction"
  else
    warn "OCR found no installer window in $SHOT"
    tesseract "$SHOT" - 2>/dev/null | sed 's/^/    | /' || true
    installer_missing=1
  fi
fi

echo
echo "--- last 30 serial lines ---"
tail -n 30 "$LOG" | tr -d '\r' || true
echo
echo "evidence: $LOG"
echo "          $SUMMARY"
[[ -f "$SHOT" ]] && echo "          $SHOT"
[[ -f "$MENU_SHOT" ]] && echo "          $MENU_SHOT"

if (( driver_status != 0 )); then
  warn "live session probe failed (driver exit $driver_status) — inspect $LOG"
  exit "$driver_status"
fi

if grep -q 'NO-CALAMARES-PROCESS' "$SUMMARY"; then
  warn "the installer never started in the live session"
  installer_missing=1
fi

# The strongest form of the check: Hyprland itself reports a Calamares window.
if ! grep -q 'io\.calamares\.calamares' "$SUMMARY"; then
  warn "Hyprland reports no Calamares window (io.calamares.calamares)"
  installer_missing=1
fi

# The window still appears when a configured module cannot be loaded (Calamares
# shows its error page), so a broken settings.conf must fail this test too.
if grep -qE 'STARTUP: failed modules|not found in module search paths|Invalid instance in \*sequence\*' "$SUMMARY"; then
  warn "Calamares could not load its module sequence — inspect $SUMMARY and $LOG"
  grep -E 'ERROR: Module|failed modules|Invalid instance' "$SUMMARY" | sed 's/^/    | /' || true
  installer_missing=1
fi
if (( ${installer_missing:-0} )); then
  exit 1
fi

# The probe recorded /proc/cmdline, so the entry that actually booted is provable.
if grep -q 'nomodeset' "$SUMMARY"; then
  log "booted command line contains nomodeset (safe-graphics entry confirmed)"
elif [[ "$ENTRY" == "safe-graphics" ]]; then
  warn "nomodeset missing from /proc/cmdline: the default entry booted instead"
fi
