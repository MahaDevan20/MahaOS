#!/usr/bin/env bash
# Virtualization profile: KVM/QEMU with libvirt and virt-manager.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

install_profile "virtualization (QEMU/KVM, libvirt, virt-manager)" \
  qemu-full libvirt virt-manager virt-viewer edk2-ovmf swtpm dnsmasq iptables-nft

log "enabling libvirtd"
systemctl enable --now libvirtd.service || warn "could not enable libvirtd.service"

target_user="${SUDO_USER:-}"
if [[ -n "$target_user" ]]; then
  usermod -aG libvirt "$target_user" || warn "could not add $target_user to the libvirt group"
  log "added $target_user to the libvirt group (re-login required)"
else
  warn "no SUDO_USER; add your account to the libvirt group manually"
fi

cat <<'EOF'

Networking note: libvirt's default NAT network uses iptables-nft here. If the
default network is not active, run:
    sudo virsh net-start default && sudo virsh net-autostart default
EOF
