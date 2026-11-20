#!/usr/bin/env bash
# Runs inside the target chroot. Configure snapper on / with snap-pac so every
# pacman transaction is bracketed by snapshots, and grub-btrfsd exposes them in GRUB.
set -euo pipefail

export LC_ALL=C

echo ":: [mahadevanos] configuring snapper"

mkdir -p /etc/snapper/configs /etc/default/grub-btrfs

# @snapshots is already mounted at /.snapshots by the installer's fstab, so create
# the configuration only; do not let snapper create a second subvolume.
if [[ ! -f /etc/snapper/configs/root ]]; then
  snapper --no-dbus -c root create-config / || true
fi

if [[ -f /etc/snapper/configs/root ]]; then
  sed -i \
    -e 's|^SUBVOLUME=.*|SUBVOLUME="/"|' \
    -e 's|^ALLOW_USERS=.*|ALLOW_USERS=""|' \
    -e 's|^TIMELINE_CREATE=.*|TIMELINE_CREATE="yes"|' \
    -e 's|^TIMELINE_CLEANUP=.*|TIMELINE_CLEANUP="yes"|' \
    -e 's|^TIMELINE_LIMIT_HOURLY=.*|TIMELINE_LIMIT_HOURLY="5"|' \
    -e 's|^TIMELINE_LIMIT_DAILY=.*|TIMELINE_LIMIT_DAILY="7"|' \
    -e 's|^TIMELINE_LIMIT_WEEKLY=.*|TIMELINE_LIMIT_WEEKLY="2"|' \
    -e 's|^TIMELINE_LIMIT_MONTHLY=.*|TIMELINE_LIMIT_MONTHLY="1"|' \
    -e 's|^TIMELINE_LIMIT_YEARLY=.*|TIMELINE_LIMIT_YEARLY="0"|' \
    -e 's|^NUMBER_LIMIT=.*|NUMBER_LIMIT="10"|' \
    -e 's|^NUMBER_LIMIT_IMPORTANT=.*|NUMBER_LIMIT_IMPORTANT="10"|' \
    /etc/snapper/configs/root
fi

# grub-btrfsd watches these snapper configs and rewrites the GRUB snapshot menu.
cat >/etc/default/grub-btrfs/config <<'EOF'
# Managed by MahaDevan's OS. Read by grub-btrfsd.service.
GRUB_BTRFS_SNAPPER_CONFIGS="root"
GRUB_BTRFS_GRUB_DIRNAME="/boot/grub"
GRUB_BTRFS_OVERRIDE_BOOT_PARTITION_DETECTION="false"
EOF

# snap-pac reads /etc/snap-pac.ini when present; defaults are what we want, but
# keep a file so the behaviour is explicit and reviewable.
cat >/etc/snap-pac.ini <<'EOF'
[paths]
/etc = 1
/boot = 1
/usr = 1
/var/lib/pacman = 1

[options]
cleanup_algorithm = number
EOF

# Root config needs the .snapshots directory present and owned by root.
install -d -m 750 /.snapshots

echo ":: [mahadevanos] snapper configured"
