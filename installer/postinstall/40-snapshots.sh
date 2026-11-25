#!/usr/bin/env bash
# Runs inside the target chroot, before the bootloader module runs grub-mkconfig.
#
# Brings up the M3 snapshot stack on top of the subvolume layout the mount module
# already created (@, @home, @log, @cache, @snapshots mounted at /.snapshots):
#   * snapper config "root" on /, with bounded retention (mahadevanos-settings);
#   * snap-pac, which brackets every pacman transaction with a pre/post pair;
#   * grub-btrfs + grub-btrfsd, which write the GRUB "Snapshots" submenu;
#   * the overlayfs mkinitcpio hook (added to /etc/mkinitcpio.conf by
#     10-mkinitcpio.sh) so a snapshot boots read-only but still writable via tmpfs;
#   * mahadevanos-snapshot-guard, which keeps the newest snapshot marked
#     important so cleanup can never delete the last known-good state;
#   * one "fresh install" snapshot, protected, so the first boot already has
#     something to roll back to.
set -euo pipefail

export LC_ALL=C
CONFIG=root

# Everything here runs inside the target chroot, where /run is the LIVE system's
# (Calamares bind-mounts it) and no snapperd is running for this root. Plain
# `snapper` would ask D-Bus to start the daemon and fail, so every call is made
# with --no-dbus, which runs snapper against the filesystem in front of it.
SNAPPER=(snapper --no-dbus)

echo ":: [mahadevanos] configuring snapper and grub-btrfs"

mkdir -p /etc/snapper/configs /etc/default/grub-btrfs /var/lib/mahadevanos

# The Arch Wiki layout: /.snapshots must be the @snapshots subvolume, created and
# mounted by the installer's mount module (mount.conf btrfsSubvolumes). If it is
# missing, snapper would silently start snapshotting into @ instead, which is
# exactly what a rollback must not do.
if ! btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  echo ":: [mahadevanos] WARNING: /.snapshots is not a btrfs subvolume; snapshots would land inside @" >&2
fi
install -d -m 750 /.snapshots

# @snapshots is already mounted, so only create the configuration; never let
# snapper create a second subvolume over the mounted one.
if [[ ! -f "/etc/snapper/configs/$CONFIG" ]]; then
  "${SNAPPER[@]}" -c "$CONFIG" create-config / || true
fi

# The package ships the tuned config; this keeps a target whose config came from
# `create-config` (a future installer change) on the same retention policy.
if [[ -f "/etc/snapper/configs/$CONFIG" ]]; then
  sed -i \
    -e 's|^SUBVOLUME=.*|SUBVOLUME="/"|' \
    -e 's|^ALLOW_USERS=.*|ALLOW_USERS=""|' \
    -e 's|^TIMELINE_CREATE=.*|TIMELINE_CREATE="yes"|' \
    -e 's|^TIMELINE_CLEANUP=.*|TIMELINE_CLEANUP="yes"|' \
    -e 's|^TIMELINE_MIN_AGE=.*|TIMELINE_MIN_AGE="1800"|' \
    -e 's|^TIMELINE_LIMIT_HOURLY=.*|TIMELINE_LIMIT_HOURLY="5"|' \
    -e 's|^TIMELINE_LIMIT_DAILY=.*|TIMELINE_LIMIT_DAILY="7"|' \
    -e 's|^TIMELINE_LIMIT_WEEKLY=.*|TIMELINE_LIMIT_WEEKLY="2"|' \
    -e 's|^TIMELINE_LIMIT_MONTHLY=.*|TIMELINE_LIMIT_MONTHLY="1"|' \
    -e 's|^TIMELINE_LIMIT_YEARLY=.*|TIMELINE_LIMIT_YEARLY="0"|' \
    -e 's|^NUMBER_CLEANUP=.*|NUMBER_CLEANUP="yes"|' \
    -e 's|^NUMBER_MIN_AGE=.*|NUMBER_MIN_AGE="1800"|' \
    -e 's|^NUMBER_LIMIT=.*|NUMBER_LIMIT="10"|' \
    -e 's|^NUMBER_LIMIT_IMPORTANT=.*|NUMBER_LIMIT_IMPORTANT="5"|' \
    -e 's|^SPACE_LIMIT=.*|SPACE_LIMIT="0.5"|' \
    -e 's|^FREE_LIMIT=.*|FREE_LIMIT="0.2"|' \
    "/etc/snapper/configs/$CONFIG"
fi

# Two sysconfig files tell the rest of the stack which snapper configurations
# exist. Neither is created by the snapper package, and both matter:
#   * /etc/snapper/snapper - read by snap-pac (SNAPPER_CONFIGS). When the file is
#     missing snap-pac raises FileNotFoundError, its pacman hook is AbortOnFail,
#     and every pacman transaction in the installed system would abort.
#   * /etc/conf.d/snapper - read by /usr/lib/snapper/systemd-helper, which is what
#     snapper-timeline.timer and snapper-cleanup.timer run. With the package's
#     default SNAPPER_CONFIGS="" those timers do nothing, so the retention limits
#     below would never be enforced.
add_snapper_config() { # add_snapper_config <file>
  local file="$1" current="" tmp
  if [[ -f "$file" ]]; then
    current="$(sed -n 's/^SNAPPER_CONFIGS="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$file" | head -1)"
  fi
  case " $current " in
    *" $CONFIG "*) return 0 ;;
  esac
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    grep -vE '^[[:space:]]*#?[[:space:]]*SNAPPER_CONFIGS=' "$file" >"$tmp" || true
  fi
  printf 'SNAPPER_CONFIGS="%s"\n' "$(echo $current $CONFIG)" >>"$tmp"
  install -m 644 "$tmp" "$file"
  rm -f "$tmp"
}
add_snapper_config /etc/snapper/snapper
add_snapper_config /etc/conf.d/snapper
grep -H '^SNAPPER_CONFIGS=' /etc/snapper/snapper /etc/conf.d/snapper

# grub-btrfs reads this file from both /etc/grub.d/41_snapshots-btrfs and
# grub-btrfsd.service (EnvironmentFile). It replaces the package's commented
# template, so the defaults that matter here are all written out.
cat >/etc/default/grub-btrfs/config <<'EOF'
# Managed by MahaDevan's OS (installer/postinstall/40-snapshots.sh).
#
# Kernels live inside the Btrfs root (@/boot), so /boot is NOT a separate
# partition: grub-btrfs must read the kernels from the snapshot itself, which is
# what reproving boot-partition detection would break.
GRUB_BTRFS_OVERRIDE_BOOT_PARTITION_DETECTION="false"
GRUB_BTRFS_GRUB_DIRNAME="/boot/grub"
GRUB_BTRFS_BOOT_DIRNAME="/boot"

# The submenu name the GRUB menu shows. documentation/recovery/ and the tests
# depend on this exact name.
GRUB_BTRFS_SUBMENUNAME="Snapshots"
# Newest snapshots first, so entry 0 of the submenu is the most recent state.
GRUB_BTRFS_SUBVOLUME_SORT="-rootid"
# Bounded: every entry is a full menuentry and GRUB loads the whole submenu.
GRUB_BTRFS_LIMIT="20"
GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND="true"

# Never list the live root or container storage subvolumes as snapshots.
GRUB_BTRFS_IGNORE_SPECIFIC_PATH=("@")
GRUB_BTRFS_IGNORE_PREFIX_PATH=("var/lib/docker" "@var/lib/docker" "@/var/lib/docker" "var/lib/containers" "@var/lib/containers" "@/var/lib/containers")
EOF

# snap-pac reads /etc/snap-pac.ini when present, and every section name is a
# SNAPPER CONFIGURATION to snapshot (snap-pac(8)): [root] is the one that exists
# here. A section that is not a snapper config makes the pre-transaction hook
# fail, and the hook is AbortOnFail, so pacman would refuse every transaction.
# That is why this file names [root] and nothing else.
#
# Snapshotting stays OFF until the install is finished: snap-pac calls plain
# `snapper`, which cannot reach a daemon from this chroot, and its hook would
# abort the pacman transaction 99-cleanup.sh uses to remove the installer. The
# last postinstall script turns it on again for the installed system.
cat >/etc/snap-pac.ini <<'EOF'
# Managed by MahaDevan's OS (installer/postinstall/40-snapshots.sh).
# One section per snapper configuration, named exactly like the configuration.
# [root] is snapshotted around every pacman transaction, with snap-pac's default
# descriptions (the command that ran, then the packages it changed).
#
# snapshot = False is switched to True by 99-cleanup.sh, the last postinstall
# script, once the installer has removed its own packages from the target.
[root]
snapshot = False
cleanup_algorithm = number
EOF

# Enable the units that make the stack work on the installed system:
#   * grub-btrfsd watches /.snapshots and rewrites /boot/grub/grub-btrfs.cfg, so a
#     snapshot taken by an update appears in GRUB without a manual grub-mkconfig;
#   * snapper-timeline/cleanup are what enforce the retention limits (without the
#     timers nothing is ever deleted, and the disk fills with timeline snapshots);
#   * snapper-boot takes the boot snapshot the timeline policy expects;
#   * mahadevanos-snapshot-guard protects the newest snapshot before cleanup runs.
for unit in grub-btrfsd.service snapper-timeline.timer snapper-cleanup.timer \
            snapper-boot.timer mahadevanos-snapshot-guard.timer; do
  # --root=/ keeps systemctl offline: without it, systemctl in this chroot talks
  # to the LIVE system's PID 1 over the bind-mounted /run and enables the unit in
  # the wrong system (it fails for some units, e.g. snapper-cleanup.timer).
  if out=$(systemctl --root=/ enable "$unit" 2>&1); then
    echo ":: [mahadevanos] enabled $unit"
  else
    # stdout, not stderr: Calamares shows only the command's stdout in its error
    # dialog, and this is the line that explains the failure.
    echo ":: [mahadevanos] ERROR: could not enable $unit: $out"
    exit 1
  fi
done

# A freshly installed system must already have a snapshot to go back to. It is
# created here, before the bootloader module runs grub-mkconfig, so the very first
# GRUB menu already contains the Snapshots submenu with an entry in it.
if ! list_out=$("${SNAPPER[@]}" -c "$CONFIG" list -t all 2>&1); then
  echo ":: [mahadevanos] ERROR: snapper -c $CONFIG list failed: $list_out"
  exit 1
fi
# Snapshot numbers come from the plain table: column 1 is always the number, and
# 0 is snapper's pseudo-entry for the live filesystem, not a snapshot.
snapshot_numbers() {
  "${SNAPPER[@]}" -c "$CONFIG" list -t all 2>/dev/null |
    sed -e 's/[│|].*//' -e 's/[^0-9]//g' | grep -E '^[1-9][0-9]*$'
}
if [[ -z "$(snapshot_numbers)" ]]; then
  if create_out=$("${SNAPPER[@]}" -c "$CONFIG" create --description "fresh install" \
       --cleanup-algorithm number --userdata "important=yes" 2>&1); then
    echo ":: [mahadevanos] created the initial snapshot"
  else
    echo ":: [mahadevanos] ERROR: could not create the initial snapshot: $create_out"
    exit 1
  fi
fi

# Record it as the protected anchor and make sure a re-run of the install keeps
# exactly one. The guard does this on every boot on the installed system; here
# the same steps are taken directly, because snapper's list inside a chroot does
# not always report a snapshot in the second it was created in.
newest="$(snapshot_numbers | sort -n | tail -1 || true)"
if [[ -n "$newest" ]]; then
  "${SNAPPER[@]}" -c "$CONFIG" modify --cleanup-algorithm number \
    --userdata important=yes "$newest" >/dev/null \
    || echo ":: [mahadevanos] WARNING: could not mark snapshot $newest important"
  install -d -m 755 /var/lib/mahadevanos
  printf '%s\n' "$newest" >/var/lib/mahadevanos/snapshot-anchor
  echo ":: [mahadevanos] snapshot $newest is the protected anchor (important=yes)"
else
  echo ":: [mahadevanos] WARNING: no snapshot number found after creating the initial snapshot"
fi

echo ":: [mahadevanos] snapshot stack configured:"
"${SNAPPER[@]}" -c "$CONFIG" list -t all || true

echo ":: [mahadevanos] snapper and grub-btrfs configured"
