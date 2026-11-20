#!/usr/bin/env bash
# Optional Zen kernel. `linux` stays the default; `linux-lts` stays the fallback.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

install_profile "zen kernel (keeps linux and linux-lts installed)" \
  linux-zen linux-zen-headers

log "regenerating initramfs for the zen kernel"
mkinitcpio -P

log "regenerating the GRUB menu (zen entry appears; linux remains the default)"
grub-mkconfig -o /boot/grub/grub.cfg
