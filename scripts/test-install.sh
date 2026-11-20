#!/usr/bin/env bash
# Install-test harness. Disk work happens ONLY on build/test-disk.qcow2.
#
#   scripts/test-install.sh --prepare          create/refresh the virtual disk and boot the ISO
#   scripts/test-install.sh --boot-installed   boot the existing disk WITHOUT the ISO
#
# The Calamares walkthrough is a human step (documentation/installation/manual-test.md);
# this script prepares the VM and records evidence of the installed-disk boot.
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require qemu-system-x86_64 qemu-img

DISK="$BUILD_DIR/test-disk.qcow2"
DISK_SIZE="${DISK_SIZE:-40G}"
ISO="$(find "$OUT_DIR" -maxdepth 1 -name 'mahadevanos-*.iso' -type f | sort | tail -1)"

OVMF_CODE=""
for p in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
         /usr/share/OVMF/OVMF_CODE.fd; do
  [[ -f "$p" ]] && { OVMF_CODE="$p"; break; }
done
[[ -n "$OVMF_CODE" ]] || die "OVMF firmware not found (pacman -S edk2-ovmf)"
OVMF_VARS_SRC="${OVMF_CODE/CODE/VARS}"

case "${1:-}" in
  --prepare)
    [[ -n "$ISO" ]] || die "no ISO in $OUT_DIR; run scripts/build-iso.sh first"
    if [[ -f "$DISK" ]]; then
      warn "$DISK already exists; keeping it (delete it yourself to start fresh)"
    else
      log "creating $DISK ($DISK_SIZE, qcow2, virtual only)"
      qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"
    fi
    [[ -f "$BUILD_DIR/OVMF_VARS.fd" ]] || cp "$OVMF_VARS_SRC" "$BUILD_DIR/OVMF_VARS.fd"

    log "booting the ISO with the virtual disk attached"
    cat <<EOF

Inside the VM:
  1. Click "Install MahaDevan's OS".
  2. Choose "Erase disk" (the only disk is a 40 GiB virtio disk — your real disks
     are not attached to this VM).
  3. Complete the installer, then power off.

Then run:  scripts/test-install.sh --boot-installed

EOF
    exec qemu-system-x86_64 \
      ${KVM:+-enable-kvm} -smp 4 -m 6144 -machine q35 \
      -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
      -drive if=pflash,format=raw,file="$BUILD_DIR/OVMF_VARS.fd" \
      -drive file="$DISK",if=virtio \
      -cdrom "$ISO" -boot d \
      -device virtio-vga-gl -display gtk,gl=on \
      -device virtio-net-pci,netdev=n0 -netdev user,id=n0
    ;;
  --boot-installed)
    [[ -f "$DISK" ]] || die "$DISK does not exist; run --prepare and install first"
    log "booting the installed disk without the ISO (evidence: out/test-install.log)"
    : >"$OUT_DIR/test-install.log"
    exec qemu-system-x86_64 \
      ${KVM:+-enable-kvm} -smp 4 -m 6144 -machine q35 \
      -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
      -drive if=pflash,format=raw,file="$BUILD_DIR/OVMF_VARS.fd" \
      -drive file="$DISK",if=virtio \
      -device virtio-vga-gl -display gtk,gl=on \
      -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
      -serial "file:$OUT_DIR/test-install.log"
    ;;
  *)
    die "usage: $0 --prepare | --boot-installed"
    ;;
esac
