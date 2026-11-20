#!/usr/bin/env bash
# Boot the built ISO in a UEFI (OVMF) QEMU VM, headless, and capture evidence:
#   out/test-boot.log   serial console
#   out/test-boot.png   framebuffer screenshot taken through the QEMU monitor
#
# Nothing here touches a real disk: the ISO is read-only and no disk is attached.
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require qemu-system-x86_64 python3

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

LOG="$OUT_DIR/test-boot.log"
SHOT="$OUT_DIR/test-boot.png"
VARS="$BUILD_DIR/OVMF_VARS-test.fd"
SOCK="$BUILD_DIR/qemu-monitor.sock"
TIMEOUT="${BOOT_TIMEOUT:-300}"

: >"$LOG"
cp "$OVMF_VARS_SRC" "$VARS"
rm -f "$SOCK" "$SHOT"

accel=()
[[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)

log "booting $ISO (UEFI, ${TIMEOUT}s budget)"
qemu-system-x86_64 \
  "${accel[@]}" -smp 4 -m 4096 \
  -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -cdrom "$ISO" -boot d \
  -device virtio-vga -display none \
  -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
  -serial "file:$LOG" \
  -monitor "unix:$SOCK,server,nowait" \
  -pidfile "$BUILD_DIR/qemu-boot.pid" \
  -daemonize

monitor() {
  python3 - "$SOCK" "$1" <<'PY'
import socket, sys, time
path, cmd = sys.argv[1], sys.argv[2]
for attempt in range(40):
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
  [[ -f "$BUILD_DIR/qemu-boot.pid" ]] && kill "$(cat "$BUILD_DIR/qemu-boot.pid")" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

log "waiting for the live session (serial log: $LOG)"
found=""
deadline=$(( SECONDS + TIMEOUT ))
while (( SECONDS < deadline )); do
  if grep -qiE 'login:|Hyprland|sddm|liveuser|Reached target graphical|Reached target Multi-User' "$LOG" 2>/dev/null; then
    found="$(grep -iE -m1 'login:|Hyprland|sddm|liveuser|Reached target graphical|Reached target Multi-User' "$LOG" || true)"
    break
  fi
  sleep 3
done

sleep 5
monitor "screendump $SHOT" >/dev/null 2>&1 || warn "screendump failed"

if [[ -n "$found" ]]; then
  log "boot evidence found: ${found:0:120}"
else
  warn "no login/session marker within ${TIMEOUT}s — inspect $LOG"
fi

echo
echo "--- last 40 serial lines ---"
tail -n 40 "$LOG" || true
[[ -f "$SHOT" ]] && echo "screenshot: $SHOT"

grep -qiE 'login:|Hyprland|sddm|liveuser|Reached target graphical|Reached target Multi-User' "$LOG"
