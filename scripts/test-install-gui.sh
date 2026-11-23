#!/usr/bin/env bash
# Drive the REAL Calamares GUI on a throwaway qcow2 disk and audit the result.
#
#   scripts/test-install-gui.sh
#
# This is the test the 2026-11-22 hand install needed. Calamares' own sequence
# decides whether the exec phase runs at all, and a config-driven rehearsal
# cannot see that: with `finished` in the show list before the exec phase,
# Calamares showed "All done" one second after the summary page, the disk stayed
# empty, and every module-level test still passed because the modules themselves
# were fine.
#
# The pages are the ones a person clicks -- language, location, keyboard,
# Erase disk, users, summary, install -- operated through the QEMU monitor
# (sendkey) and read back with tesseract OCR, so each step is confirmed against
# what is actually on the screen. Nothing but the qcow2 disk and the ISO is
# touched; the only block device with a size inside the guest is /dev/vda.
set -uo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require qemu-system-x86_64 qemu-img python3 tesseract

DISK="$BUILD_DIR/test-disk.qcow2"
DISK_SIZE="${DISK_SIZE:-40G}"
ISO="${ISO:-$(find "$OUT_DIR" -maxdepth 1 -name 'mahadevanos-*.iso' -type f | sort | tail -1)}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$PROJECT_ROOT/tests/evidence/$(date +%Y-%m-%d)}"
mkdir -p "$EVIDENCE_DIR"
[[ -n "$ISO" ]] || die "no ISO in $OUT_DIR; run scripts/build-iso.sh first"

# The account the GUI creates; the installed-disk boot test logs in with it.
INSTALL_USER="${INSTALL_USER:-tester}"
INSTALL_PASS="${INSTALL_PASS:-mahadevan12}"

GUI="$PROJECT_ROOT/scripts/qemu-gui.py"
MON="$BUILD_DIR/gui-mon.sock"
SER="$BUILD_DIR/gui-ser.sock"
VARS="$BUILD_DIR/OVMF_VARS-gui.fd"
PIDFILE="$BUILD_DIR/qemu-gui.pid"
LOG="$EVIDENCE_DIR/gui-install.log"
SHOTS="$EVIDENCE_DIR/gui-shots"
mkdir -p "$SHOTS"

OVMF_CODE=""
for p in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
         /usr/share/OVMF/OVMF_CODE.fd; do
  [[ -f "$p" ]] && { OVMF_CODE="$p"; break; }
done
[[ -n "$OVMF_CODE" ]] || die "OVMF firmware not found (pacman -S edk2-ovmf)"
OVMF_VARS_SRC="${OVMF_CODE/CODE/VARS}"

gui() { python3 "$GUI" "$MON" "$@"; }
shot() { printf '%s/gui-%s.png' "$SHOTS" "$1"; }
text_of() { gui text "$(shot "$1")" 2>/dev/null || true; }

say() { printf '%s\n' "$*" | tee -a "$LOG" >&2; }

stop_vm() {
  gui quit >/dev/null 2>&1 || true
  if [[ -f "$PIDFILE" ]]; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; fi
  sleep 1
}
trap stop_vm EXIT INT TERM

step_ok() { say "PASS $*"; }
step_fail() { say "FAIL $*"; exit 1; }

# expect NAME REGEX TIMEOUT  -- capture the screen and require the text
expect() {
  local name="$1" regex="$2" timeout="${3:-180}"
  if gui wait "$(shot "$name")" "$regex" "$timeout" >/dev/null 2>>"$LOG"; then
    step_ok "page '${name}': saw /${regex}/"
  else
    say "--- screen text at failure:"
    text_of "$name" | head -30 | tee -a "$LOG" >&2
    step_fail "page '${name}': never saw /${regex}/ within ${timeout}s"
  fi
}

accel=()
[[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)

rm -f "$MON" "$SER" "$PIDFILE"
[[ -f "$DISK" ]] && { log "recreating $DISK ($DISK_SIZE, qcow2, virtual only)"; rm -f "$DISK"; }
qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
cp "$OVMF_VARS_SRC" "$VARS"

: >"$LOG"
say "==> ISO: $ISO"
say "==> disk: $DISK ($DISK_SIZE)"
say "==> booting the ISO and driving the Calamares GUI"

qemu-system-x86_64 \
  "${accel[@]}" -smp 4 -m 6144 -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -cdrom "$ISO" -boot d \
  -device virtio-vga -display none \
  -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
  -serial "unix:$SER,server,nowait" \
  -monitor "unix:$MON,server,nowait" \
  -pidfile "$PIDFILE" -daemonize || die "QEMU failed to start"

# ---------------------------------------------------------------------------
# The pages of the real installer
# ---------------------------------------------------------------------------
expect welcome 'Welcome to the .*installer' 420
gui key alt-n
expect location 'Region:' 120
gui key alt-n
expect keyboard 'Keyboard model' 120
gui key alt-n
expect partition 'Erase disk' 180
say "--- partition page text (Erase disk is preselected by partition.conf)"
text_of partition | sed -n '1,12p' | tee -a "$LOG" >&2
gui key alt-n
expect users 'What is your name' 120

# "What is your name?" already has focus; the next three fields are the login
# name, the computer name and the password, then the repeat-password field. The
# login name is set explicitly so the boot test knows which account to use.
gui type "Tester"
gui key tab          # login name (derived from the full name)
gui key ctrl-a; gui key backspace
gui type "$INSTALL_USER"
gui key tab          # computer name (kept as Calamares derived it)
gui key tab          # password
gui type "$INSTALL_PASS"
gui key tab          # repeat password
gui type "$INSTALL_PASS"
gui dump "$(shot users-filled)" >/dev/null 2>&1
if text_of users-filled | grep -qi 'do not match'; then
  text_of users-filled | tee -a "$LOG" >&2
  step_fail "the users page reports 'Your passwords do not match'"
fi
step_ok "users page filled in (name, login, computer name, password)"

gui key alt-n
expect summary 'Erase disk' 120
say "--- summary page text"
text_of summary | sed -n '1,25p' | tee -a "$LOG" >&2
if ! text_of summary | grep -qiE 'install .*on new btrfs'; then
  step_fail "summary does not describe the Btrfs install; the partition page choice was not 'Erase disk'"
fi
step_ok "summary shows the erase-disk install plan"

# The next step is the exec phase, so this button is "Install" (&Install).
gui key alt-i
sleep 3
if ! text_of progress | grep -qiE 'install|extract|partition|job|progress'; then
  say "alt-i did not start the install; trying alt-n"
  gui key alt-n
fi
expect progress 'Install|Extract|Partition|Job:|%' 120

say "==> waiting for the GUI install to finish (unpackfs of the whole iso takes minutes)"
if ! gui wait "$(shot finished)" 'All done|Installation Failed' 2400 >/dev/null 2>>"$LOG"; then
  text_of finished | head -30 | tee -a "$LOG" >&2
  step_fail "the install never reached the finished page"
fi
text_of finished | sed -n '1,12p' | tee -a "$LOG" >&2
if text_of finished | grep -qi 'Installation Failed'; then
  step_fail "Calamares reports Installation Failed"
fi
step_ok "finished page reached: 'All done' is shown after the exec phase"
if ! text_of finished | grep -qi 'Restart now'; then
  step_fail "the finished page has no restart control"
fi
step_ok "finished page offers 'Restart now'"

# ---------------------------------------------------------------------------
# Audit the install from inside the live system (root, session log + disk)
# ---------------------------------------------------------------------------
say "==> auditing the installed disk from the live system"
AUDIT="$EVIDENCE_DIR/gui-install-audit.txt"
AUDIT_RC=0
LOGIN_TIMEOUT=180 RUN_TIMEOUT=300 USE_SUDO=1 \
  python3 "$PROJECT_ROOT/scripts/qemu-serial-run.py" \
  "$SER" "$EVIDENCE_DIR/gui-audit-serial.log" \
  "$PROJECT_ROOT/tests/install/gui-install-audit.sh" "$AUDIT" >>"$LOG" 2>&1 || AUDIT_RC=$?

# The payload prints the log lines that matter; keep them visible.
if [[ -f "$AUDIT" ]]; then
  sed -n '1,200p' "$AUDIT" | tee -a "$LOG" >&2
fi
if (( AUDIT_RC != 0 )) || ! grep -q 'GUI INSTALL AUDIT: PASSED' "$AUDIT" 2>/dev/null; then
  step_fail "the GUI install audit failed (see $AUDIT)"
fi
step_ok "GUI install audit passed: jobs started, partitions exist, root populated"

# ---------------------------------------------------------------------------
# The restart control must really restart the machine
# ---------------------------------------------------------------------------
say "==> pressing Done with 'Restart now' checked; the VM must reboot"
REBOOT_LOG="$EVIDENCE_DIR/gui-reboot-serial.log"
: >"$REBOOT_LOG"
python3 - "$SER" "$REBOOT_LOG" <<'PY' &
import socket, sys, time
path, out = sys.argv[1], sys.argv[2]
for _ in range(60):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(path)
        break
    except OSError:
        time.sleep(0.25)
else:
    raise SystemExit(1)
sock.settimeout(1.0)
end = time.time() + 240
with open(out, "ab", buffering=0) as fh:
    while time.time() < end:
        try:
            data = sock.recv(65536)
        except (TimeoutError, socket.timeout):
            continue
        if data:
            fh.write(data)
PY
READER=$!
sleep 2
gui key alt-d
sleep 8
if text_of finished | grep -qi 'All done'; then
  gui key alt-c   # fallback: the quit button is labelled Cancel before the fix
fi
rebooted=0
for _ in $(seq 1 60); do
  if grep -aqiE 'reboot: Restarting system|reboot: Power down|Calling reboot|systemd-shutdown' "$REBOOT_LOG"; then
    rebooted=1
    break
  fi
  sleep 3
done
kill "$READER" 2>/dev/null || true
if (( rebooted )); then
  tr -d '\r' <"$REBOOT_LOG" | grep -aiE 'reboot:|systemd-shutdown' | tail -5 | tee -a "$LOG" >&2
  step_ok "the restart control rebooted the machine"
else
  tr -d '\r' <"$REBOOT_LOG" | tail -20 | tee -a "$LOG" >&2
  gui dump "$(shot after-done)" >/dev/null 2>&1 || true
  step_fail "no reboot happened after clicking Done with 'Restart now' checked"
fi

say "==> GUI install test PASSED"
