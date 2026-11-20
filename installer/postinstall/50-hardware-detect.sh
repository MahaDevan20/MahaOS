#!/usr/bin/env bash
# Runs inside the target chroot (M5, EXPERIMENTAL).
# Detect the GPU and hypervisor, log what was found, and install matching drivers
# ONLY from the offline repository on the ISO. Never fails the installation:
# a wrong guess must not cost the user a working system.
set -euo pipefail

export LC_ALL=C

LOG_DIR=/var/log/mahadevanos
OFFLINE_REPO=/opt/mahadevanos-offline
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/hardware.log"

{
  echo "=== MahaDevan's OS hardware detection: $(date -u +%FT%TZ) ==="
  echo "--- VGA/3D controllers ---"
  lspci -nnk 2>/dev/null | grep -A3 -Ei 'vga|3d controller|display controller' || true
  echo "--- Hypervisor ---"
  systemd-detect-virt || true
  echo "--- CPU ---"
  grep -m1 'model name' /proc/cpuinfo || true
} >"$LOG"

install_offline() {
  local pkg="$1"
  if [[ -d "$OFFLINE_REPO" ]] && compgen -G "$OFFLINE_REPO/${pkg}-*.pkg.tar.*" >/dev/null; then
    echo "installing $pkg from the offline repo" >>"$LOG"
    pacman -U --noconfirm "$OFFLINE_REPO/${pkg}"-*.pkg.tar.* >>"$LOG" 2>&1 || \
      echo "FAILED to install $pkg offline" >>"$LOG"
  else
    echo "no offline package for $pkg; skipped (install it manually later)" >>"$LOG"
  fi
}

gpu_log="$(lspci -nn 2>/dev/null || true)"

if grep -qiE 'nvidia' <<<"$gpu_log"; then
  echo "NVIDIA GPU detected. Proprietary drivers are NOT installed automatically." >>"$LOG"
  echo "See documentation/known-issues.md (NVIDIA is unsupported until tested on real hardware)." >>"$LOG"
  # Placeholder for M5: nvidia-open from $OFFLINE_REPO, only after real-hardware tests.
elif grep -qiE 'advanced micro devices.*(vga|display)|ati technologies' <<<"$gpu_log"; then
  echo "AMD GPU detected: mesa + vulkan-radeon already installed, nothing to do." >>"$LOG"
elif grep -qiE 'intel.*(graphics|display)' <<<"$gpu_log"; then
  echo "Intel GPU detected: mesa + vulkan-intel already installed, nothing to do." >>"$LOG"
else
  echo "No known GPU pattern matched; mesa is installed and should cover it." >>"$LOG"
fi

case "$(systemd-detect-virt 2>/dev/null || echo none)" in
  qemu|kvm)
    install_offline qemu-guest-agent
    install_offline spice-vdagent
    ;;
  oracle)
    install_offline virtualbox-guest-utils
    ;;
  vmware)
    install_offline open-vm-tools
    ;;
  microsoft)
    echo "Hyper-V detected; kernel modules ship with linux, nothing to install." >>"$LOG"
    ;;
  *)
    echo "Bare metal (or unknown hypervisor): no guest tools needed." >>"$LOG"
    ;;
esac

# Firewall defaults: deny incoming, allow outgoing, nothing else.
if command -v ufw >/dev/null 2>&1; then
  sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf 2>/dev/null || true
  sed -i 's/^DEFAULT_INPUT_POLICY=.*/DEFAULT_INPUT_POLICY="DROP"/' /etc/default/ufw 2>/dev/null || true
  sed -i 's/^DEFAULT_OUTPUT_POLICY=.*/DEFAULT_OUTPUT_POLICY="ACCEPT"/' /etc/default/ufw 2>/dev/null || true
fi

echo ":: [mahadevanos] hardware detection finished, see $LOG"
