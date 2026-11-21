#!/usr/bin/env bash
# shellcheck disable=SC2034
# archiso profile definition for MahaDevan's OS (see OS_BLUEPRINT.md §3, §5 M1).
# Every variable below is consumed by mkarchiso, so "unused" is expected.

iso_name="mahadevanos"
iso_label="MAHADEVANOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="MahaDevan <https://github.com/mahadevan>"
iso_application="MahaDevan's OS Live ISO"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
# UEFI only for v1. systemd-boot is the *live* loader; installed systems use GRUB.
bootmodes=('uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd: good ratio, fast enough decompression that an offline install stays quick.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')

file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-liveuser"]="0:0:440"
  ["/root"]="0:0:750"
  ["/usr/local/bin"]="0:0:755"
  ["/usr/local/bin/mahadevanos-installer"]="0:0:755"
  # Live autostart of the installer lives in liveuser's own Hyprland config.
  ["/home/liveuser/.config/hypr/hyprland.lua"]="1000:1000:644"
)
