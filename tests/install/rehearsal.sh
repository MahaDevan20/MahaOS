#!/usr/bin/env bash
# Install rehearsal inside the live ISO, driven over the serial console.
#
# This is NOT the Calamares GUI: it performs the same work the installer's
# partition/mount/unpackfs/shellprocess/bootloader modules perform on /dev/vda,
# which is a qcow2 disk attached to the VM and nothing else. It exists so the
# install pipeline can be tested unattended.
#
# The layout, subvolume list and mount options are READ FROM THE SHIPPED
# CALAMARES CONFIG (/etc/calamares/modules/*.conf), not hardcoded, so a config
# regression such as the 2026-11-21 `fs:`/duplicate-ESP bug fails here:
#   - partitionLayout must contain exactly one entry (the Btrfs root); the ESP
#     is created by Calamares' automatic prepend, sized by efi.recommendedSize
#     - `fs:` must not appear in partition.conf (ignored -> "unformatted" -> the
#     mount module skips the partition and "/" is never mounted)
#   - btrfsSubvolumes must be in mount.conf
#   - shellprocess must use `script:` (3.4.2 ignores `commands:`)
#
# Runs as root inside the live system (invoked with sudo by
# scripts/qemu-serial-run.py).
set -euo pipefail

export LC_ALL=C
DISK=/dev/vda
SFS=/run/archiso/bootmnt/arch/x86_64/airootfs.sfs
CONF=/etc/calamares/modules

step() { printf '\n=== %s ===\n' "$*"; }

step "confirm the only disk is the virtual one"
lsblk -o NAME,SIZE,MODEL,TYPE
[[ -b "$DISK" ]] || { echo "ERROR: $DISK missing"; exit 1; }
[[ -b /dev/sda ]] && { echo "ERROR: unexpected /dev/sda present; aborting"; exit 1; }
[[ -f "$SFS" ]] || { echo "ERROR: $SFS missing (live squashfs not mounted)"; exit 1; }

step "read the shipped Calamares layout (regression guards)"
for f in partition mount shellprocess; do
  [[ -f "$CONF/$f.conf" ]] || { echo "ERROR: $CONF/$f.conf missing"; exit 1; }
done

# Exactly one partitionLayout entry, and it is the Btrfs root.
layout_count=$(awk '/^partitionLayout:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/^[[:space:]]*-[[:space:]]*name:/{n++} END{print n+0}' "$CONF/partition.conf")
root_fs=$(awk '/^partitionLayout:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/filesystem:/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CONF/partition.conf")
root_mnt=$(awk '/^partitionLayout:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/mountPoint:/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CONF/partition.conf")
esp_mib=$(awk '/^efi:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/recommendedSize:/{gsub(/[^0-9]/,"",$2); print $2; exit}' "$CONF/partition.conf")
esp_mnt=$(awk '/^efi:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/mountPoint:/{gsub(/["[:space:]]/,"",$2); print $2; exit}' "$CONF/partition.conf")

echo "partitionLayout entries: $layout_count"
echo "root: filesystem=$root_fs mountPoint=$root_mnt"
echo "efi:  mountPoint=$esp_mnt recommendedSize=${esp_mib}MiB"

[[ "$layout_count" == "1" ]] || { echo "FAIL: partitionLayout must have exactly one entry (the ESP is prepended by Calamares; a second ESP entry is the 2026-11-21 bug)"; exit 1; }
[[ "$root_fs" == "btrfs" ]] || { echo "FAIL: root entry filesystem must be btrfs (got '$root_fs'); use the 'filesystem:' key, not 'fs:'"; exit 1; }
[[ "$root_mnt" == "/" ]] || { echo "FAIL: root entry mountPoint must be / (got '$root_mnt')"; exit 1; }
[[ "$esp_mnt" == "/boot/efi" ]] || { echo "FAIL: efi.mountPoint must be /boot/efi (got '$esp_mnt')"; exit 1; }
[[ "$esp_mib" =~ ^[0-9]+$ ]] || { echo "FAIL: efi.recommendedSize not parsed (got '$esp_mib')"; exit 1; }
[[ "$esp_mib" -ge 1024 ]] || { echo "FAIL: efi.recommendedSize must be >= 1024MiB (got ${esp_mib}MiB)"; exit 1; }

# `fs:` is not a partitionLayout key; its presence is the original root cause.
if awk '/^partitionLayout:/{f=1;next} f&&/^[^[:space:]#]/{f=0} f&&/^[[:space:]]*fs:/{found=1} END{exit !found}' "$CONF/partition.conf"; then
  echo "FAIL: partitionLayout uses 'fs:'; Calamares only reads 'filesystem:'"
  exit 1
fi

grep -q '^btrfsSubvolumes:' "$CONF/mount.conf" || { echo "FAIL: btrfsSubvolumes missing from mount.conf"; exit 1; }
grep -q '^extraMounts:' "$CONF/mount.conf" || { echo "FAIL: extraMounts missing from mount.conf"; exit 1; }
grep -q '^script:' "$CONF/shellprocess.conf" || { echo "FAIL: shellprocess.conf must use 'script:' (3.4.2 ignores 'commands:')"; exit 1; }
if grep -q '^commands:' "$CONF/shellprocess.conf"; then
  echo "FAIL: shellprocess.conf still uses the ignored 'commands:' key"
  exit 1
fi
grep -q 'check-root-mount.sh' "$CONF/preflight.conf" || { echo "FAIL: preflight guard not configured"; exit 1; }
[[ -x /usr/share/mahadevanos/calamares/check-root-mount.sh ]] || { echo "FAIL: check-root-mount.sh missing or not executable"; exit 1; }
# The show/exec phase order is what decides whether the install runs at all.
# Calamares keeps the written order of the phases (Settings::interpretSequence ->
# ModuleManager::loadModules) and builds one view step per show entry plus one
# ExecutionViewStep for the exec phase (ViewManager). FinishedViewStep reports
# isAtEnd() == true and isNextEnabled() == false, so a `finished` entry in the
# show list that precedes the exec phase puts "All done. ... has been installed"
# directly after the summary page and makes the exec phase unreachable -- the
# 2026-11-22 hand install that finished in one second and installed nothing.
seq_dump=$(awk '
  /^  - (show|exec):/ {
    action = $2; sub(/:$/, "", action); phase++
    printf "%d|%s|<phase>\n", phase, action
    next
  }
  phase && /^[[:space:]]+-[[:space:]]*[A-Za-z0-9_@-]+[[:space:]]*$/ {
    line = $0
    sub(/^[[:space:]]*-[[:space:]]*/, "", line)
    gsub(/[[:space:]]/, "", line)
    printf "%d|%s|%s\n", phase, action, line
  }
' /etc/calamares/settings.conf)
phase_actions=$(printf '%s\n' "$seq_dump" | awk -F'|' '$3=="<phase>"{printf "%s%s", sep, $2; sep=" "}')
echo "sequence phases: $phase_actions"
[[ "$phase_actions" == "show exec show" ]] || {
  echo "FAIL: settings.conf sequence must be exactly show -> exec -> show(finished) (got: '$phase_actions')"
  exit 1
}
phase_of_finished=$(printf '%s\n' "$seq_dump" | awk -F'|' '$3=="finished"{print $1}')
finished_count=$(printf '%s\n' "$seq_dump" | awk -F'|' '$3=="finished"{n++} END{print n+0}')
echo "finished: $finished_count entry/entries in phase ${phase_of_finished:-none}"
[[ "$finished_count" == "1" ]] || { echo "FAIL: settings.conf must list finished exactly once (got $finished_count)"; exit 1; }
[[ "$phase_of_finished" == "3" ]] || {
  echo "FAIL: finished is in sequence phase $phase_of_finished; it must be the show phase AFTER the exec phase (phase 3)"
  exit 1
}
mapfile -t EXEC_MODULES < <(printf '%s\n' "$seq_dump" | awk -F'|' '$1=="2" && $3!="<phase>"{print $3}')
echo "exec phase: ${#EXEC_MODULES[@]} modules: ${EXEC_MODULES[*]}"
(( ${#EXEC_MODULES[@]} >= 16 )) || {
  echo "FAIL: the exec phase lists ${#EXEC_MODULES[@]} modules; at least 16 are expected, so most of the install would not run"
  exit 1
}
for expected in partition mount shellprocess@preflight unpackfs machineid fstab locale keyboard \
                localecfg users displaymanager networkcfg hwclock services-systemd \
                shellprocess@postinstall grubcfg bootloader umount; do
  printf '%s\n' "${EXEC_MODULES[@]}" | grep -qx -- "$expected" \
    || { echo "FAIL: $expected is missing from the exec phase of settings.conf"; exit 1; }
done
# Instance keys are "module@id"; a bare id is read as a module name and fails to
# load ("Module preflight@preflight not found").
pre_line=$(printf '%s\n' "$seq_dump" | awk -F'|' '$1=="2"{n++; if ($3=="shellprocess@preflight") p=n; if ($3=="unpackfs") u=n} END{print p" "u}')
read -r pre unp <<<"$pre_line"
echo "exec order: preflight=#$pre unpackfs=#$unp"
[[ -n "$pre" && -n "$unp" && "$pre" -lt "$unp" ]] || { echo "FAIL: preflight must run before unpackfs in settings.conf"; exit 1; }
# quit-at-end: ViewManager::updateButtonLabels() calls quit() the moment the last
# step is the finished page, which hides it and leaves the restart button inert.
if grep -qE '^quit-at-end:[[:space:]]*true' /etc/calamares/settings.conf; then
  echo "FAIL: quit-at-end must be false; true exits Calamares as soon as the finished page is shown"
  exit 1
fi
grep -qE '^quit-at-end:[[:space:]]*false' /etc/calamares/settings.conf \
  || { echo "FAIL: settings.conf must set quit-at-end: false"; exit 1; }
# Every exec entry must be exercised by this rehearsal; see the covered[] marks.
declare -A covered=()
cover() {
  local key="$1"
  printf '%s\n' "${EXEC_MODULES[@]}" | grep -qx -- "$key" \
    || { echo "ERROR: rehearsal covers '$key', which is not in the exec phase"; exit 1; }
  covered["$key"]=1
}

step "module configuration audit against Calamares 3.4.2"
# Every name below is a top-level key of src/modules/<module>/<module>.schema.yaml
# in the Calamares 3.4.2 tree, and every one of those schemas declares
# additionalProperties: false. A module silently ignores an unknown key, which is
# exactly how displaymanager.conf's `services:` list stayed invisible while the
# install died at 75%. Checking keys here turns that class of bug into a test
# failure instead of a hand-clicked install failure.
audit_bad=0
fail_audit() { echo "FAIL: $*"; audit_bad=1; }
audit_conf() {
  local module="$1" conf="$2" allowed="$3" key
  if [[ ! -f "$conf" ]]; then
    fail_audit "$conf is missing for module $module"
    return
  fi
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    if [[ " $allowed " != *" $key "* ]]; then
      fail_audit "$conf uses '$key:', which is not a Calamares 3.4.2 $module key"
      echo "      allowed keys: $allowed"
    fi
  done < <(awk '/^---[[:space:]]*$/{next} /^[A-Za-z_][A-Za-z0-9_-]*:/{sub(/:.*/,""); print}' "$conf")
}

audit_conf displaymanager "$CONF/displaymanager.conf" \
  "displaymanagers defaultDesktopEnvironment basicSetup sysconfigSetup greetd lightdm sddm"
audit_conf services-systemd "$CONF/services-systemd.conf" "units"
audit_conf finished "$CONF/finished.conf" \
  "restartNowEnabled restartNowChecked restartNowCommand restartNowMode notifyOnFinished"
audit_conf partition "$CONF/partition.conf" \
  "efiSystemPartition efiSystemPartitionSize efiSystemPartitionName efi lvm userSwapChoices armInstall allowZfsEncryption drawNestedPartitions alwaysShowPartitionLabels defaultFileSystemType availableFileSystemTypes mountpointFilesystemRestrictions luksGeneration enableLuksAutomatedPartitioning preCheckEncryption essentialMounts allowManualPartitioning showNotEncryptedBootMessage partitionLayout initialPartitioningChoice initialSwapChoice requiredStorage"
audit_conf mount "$CONF/mount.conf" "extraMounts btrfsSubvolumes btrfsSwapSubvol mountOptions"
audit_conf unpackfs "$CONF/unpackfs.conf" "unpack"
audit_conf grubcfg "$CONF/grubcfg.conf" \
  "overwrite keep_distributor prefer_grub_d kernel_params defaults always_use_defaults"
audit_conf bootloader "$CONF/bootloader.conf" \
  "efiBootLoaderVar efiBootLoader kernelSearchPath kernelName kernelParams kernelPattern loaderEntries refindKernelList grubInstall grubMkconfig grubCfg grubProbe efiBootMgr efiBootloaderId installEFIFallback installHybridGRUB"
audit_conf shellprocess "$CONF/shellprocess.conf" "dontChroot timeout verbose script i18n"
audit_conf shellprocess "$CONF/preflight.conf" "dontChroot timeout verbose script i18n"
audit_conf fstab "$CONF/fstab.conf" "crypttabOptions tmpOptions"
audit_conf welcome "$CONF/welcome.conf" \
  "showSupportUrl showKnownIssuesUrl showReleaseNotesUrl showDonateUrl requirements geoip"
audit_conf users "$CONF/users.conf" \
  "user defaultGroups autologinGroup sudoersGroup sudoersConfigureWithGroup displayAutologin doAutologin setRootPassword doReusePassword allowWeakPasswords allowWeakPasswordsDefault passwordRequirements hostname allowActiveDirectory presets"
audit_conf keyboard "$CONF/keyboard.conf" \
  "xOrgConfFileName convertedKeymapPath writeEtcDefaultKeyboard useLocale1 guessLayout configure"
audit_conf machineid "$CONF/machineid.conf" \
  "systemd systemd-style dbus dbus-symlink entropy-copy entropy-files symlink entropy"
audit_conf umount "$CONF/umount.conf" "emergency"

# Required keys (schema `required:`), and the two module-specific conditions that
# actually broke installs on 2026-11-21/22.
grep -q '^userSwapChoices:' "$CONF/partition.conf" || fail_audit "partition.conf requires userSwapChoices"
grep -q '^tmpOptions:' "$CONF/fstab.conf" || fail_audit "fstab.conf requires tmpOptions"
grep -q '^defaultGroups:' "$CONF/users.conf" || fail_audit "users.conf requires defaultGroups"
grep -q '^autologinGroup:' "$CONF/users.conf" || fail_audit "users.conf requires autologinGroup"
grep -q '^sudoersGroup:' "$CONF/users.conf" || fail_audit "users.conf requires sudoersGroup"
grep -q '^xOrgConfFileName:' "$CONF/keyboard.conf" || fail_audit "keyboard.conf requires xOrgConfFileName"
grep -q '^convertedKeymapPath:' "$CONF/keyboard.conf" || fail_audit "keyboard.conf requires convertedKeymapPath"
grep -q '^script:' "$CONF/shellprocess.conf" || fail_audit "shellprocess.conf requires script:"
grep -qE '^initialPartitioningChoice:[[:space:]]*"?erase"?[[:space:]]*$' "$CONF/partition.conf" \
  || fail_audit "partition.conf must preselect Erase disk (initialPartitioningChoice: erase)"
if grep -q '^availableChoices:' "$CONF/partition.conf"; then
  fail_audit "partition.conf uses availableChoices:, which does not exist in Calamares 3.4.2 (only initialPartitioningChoice and allowManualPartitioning are read)"
fi

# displaymanager: a non-empty list is what the module needs; an empty or absent
# one is the exact "No display managers selected" install failure.
mapfile -t audit_dms < <(awk '/^displaymanagers:/{f=1;next} f&&/^[^[:space:]#]/{f=0} \
  f&&/^[[:space:]]*-/{sub(/^[[:space:]]*-[[:space:]]*/,"",$0); gsub(/[]["[:space:]]/,"",$0); print}' "$CONF/displaymanager.conf")
if (( ${#audit_dms[@]} == 0 )); then
  fail_audit "No display managers selected for the displaymanager module. The displaymanagers list is empty or undefined in both globalstorage and displaymanager.conf."
fi
printf 'displaymanagers: %s\n' "${audit_dms[*]:-<none>}"

# services-systemd: explicit mandatory: on every unit, so a renamed or missing
# unit can never abort the install by surprise.
if ! awk '/^units:/{f=1;next} f&&/^[^[:space:]#]/{f=0}
          f&&/- name:/{n++} f&&/mandatory:/{m++}
          END{exit !(n > 0 && n == m)}' "$CONF/services-systemd.conf"; then
  fail_audit "every services-systemd unit needs an explicit mandatory: (true or false)"
fi

# The finished page has to be in the show sequence with a restart button.
grep -qE '^[[:space:]]*-[[:space:]]*finished[[:space:]]*$' /etc/calamares/settings.conf \
  || fail_audit "finished is not in the show sequence of settings.conf (no restart button at 100%)"
grep -q '^restartNowEnabled:[[:space:]]*true' "$CONF/finished.conf" \
  || fail_audit "finished.conf must set restartNowEnabled: true"
grep -qE '^restartNowMode:[[:space:]]*"?user-checked"?[[:space:]]*$' "$CONF/finished.conf" \
  || fail_audit "finished.conf must set restartNowMode: user-checked so Done restarts by default"
grep -qE '^restartNowCommand:[[:space:]]*"?(systemctl reboot|reboot|shutdown -r now)"?[[:space:]]*$' "$CONF/finished.conf" \
  || fail_audit "finished.conf restartNowCommand must be a working reboot command (systemctl reboot)"

# Every module that does work must be in the exec sequence.
for expected in partition mount shellprocess@preflight unpackfs machineid fstab \
                localecfg users displaymanager networkcfg hwclock services-systemd \
                shellprocess@postinstall grubcfg bootloader umount; do
  grep -qE "^[[:space:]]*-[[:space:]]*${expected}[[:space:]]*$" /etc/calamares/settings.conf \
    || fail_audit "$expected is missing from the exec sequence in settings.conf"
done

(( audit_bad == 0 )) || { echo "FAIL: the shipped module configuration does not match Calamares 3.4.2"; exit 1; }
echo "ok: every shipped module config is valid for Calamares 3.4.2"

# btrfsSubvolumes as "mountPoint subvolume" pairs, straight from mount.conf.
mapfile -t subvol_pairs < <(awk '
  /^btrfsSubvolumes:/{f=1;next}
  f&&/^[^[:space:]#]/{f=0}
  f&&/mountPoint:/{line=$0; sub(/^[[:space:]]*-?[[:space:]]*mountPoint:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); mp=line}
  f&&/subvolume:/{line=$0; sub(/^[[:space:]]*subvolume:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); print mp" "line}
' "$CONF/mount.conf")
(( ${#subvol_pairs[@]} >= 2 )) || { echo "FAIL: fewer than two btrfs subvolumes parsed from mount.conf"; exit 1; }
printf 'subvolume: %s\n' "${subvol_pairs[@]}"

btrfs_opts=$(awk '
  /^mountOptions:/{f=1;next}
  f&&/^[^[:space:]#]/{f=0}
  f&&/filesystem:[[:space:]]*btrfs[[:space:]]*$/{g=1;next}
  g&&/options:/{line=$0; sub(/^[[:space:]]*options:[[:space:]]*/,"",line); gsub(/[][[:space:]]/,"",line); print line; exit}
' "$CONF/mount.conf")
[[ -n "$btrfs_opts" ]] || { echo "FAIL: no btrfs mountOptions parsed from mount.conf"; exit 1; }
echo "btrfs mount options: $btrfs_opts"

step "partitioning $DISK (one ${esp_mib}MiB ESP from efi.recommendedSize + Btrfs root)"
cover partition
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+"${esp_mib}"M -t 1:ef00 -c 1:boot "$DISK"
sgdisk -n 2:0:0              -t 2:8300 -c 2:root "$DISK"
partprobe "$DISK"
sleep 2
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL "$DISK"

step "filesystems (FAT32 ESP, Btrfs root)"
cover mount
mkfs.fat -F32 "/dev/vda1"
mkfs.btrfs -f -L mahadevanos "/dev/vda2"

step "btrfs subvolumes from mount.conf"
mkdir -p /mnt
mount "/dev/vda2" /mnt
for pair in "${subvol_pairs[@]}"; do
  sv="${pair##* }"
  btrfs subvolume create "/mnt/${sv#/}"
done
umount /mnt

root_sv=$(printf '%s\n' "${subvol_pairs[@]}" | awk '$1=="/"{print $2; exit}')
mount -o "${btrfs_opts},subvol=${root_sv}" "/dev/vda2" /mnt

step "preflight guard: it must reject a target root that is not a mount"
cover shellprocess@preflight
mkdir -p /tmp/not-a-mount
if /usr/share/mahadevanos/calamares/check-root-mount.sh /tmp/not-a-mount; then
  echo "FAIL: preflight guard accepted a tmpfs directory as the target root"
  exit 1
else
  echo "ok: preflight guard rejected /tmp/not-a-mount (exit $?)"
fi

step "unpackfs: unsquashfs $SFS -> /mnt"
cover unpackfs
unsquashfs -q -d /mnt "$SFS"
# A module that "succeeds" without copying the system is the failure this test
# exists to catch: assert real content rather than just the exit status.
for p in /mnt/usr/bin/bash /mnt/etc/os-release /mnt/etc/passwd /mnt/usr/lib/os-release; do
  [[ -e "$p" ]] || { echo "FAIL: unpackfs did not create $p; the root was not populated"; exit 1; }
done
unpacked_files=$(find /mnt -xdev | wc -l)
unpacked_du=$(du -sxm /mnt | awk '{print $1}')
echo "unpackfs: $unpacked_files paths, ${unpacked_du} MiB in /mnt"
(( unpacked_files > 1000 )) || { echo "FAIL: only $unpacked_files paths in the target; unpackfs copied almost nothing"; exit 1; }
(( unpacked_du > 500 )) || { echo "FAIL: only ${unpacked_du} MiB in the target; unpackfs copied almost nothing"; exit 1; }

step "preflight guard: it must accept the real target root"
/usr/share/mahadevanos/calamares/check-root-mount.sh /mnt

step "mount the remaining subvolumes from mount.conf"
mkdir -p /mnt/boot/efi
for pair in "${subvol_pairs[@]}"; do
  mp="${pair%% *}"
  sv="${pair##* }"
  [[ "$mp" == "/" ]] && continue
  mkdir -p "/mnt${mp}"
  mount -o "${btrfs_opts},subvol=${sv}" "/dev/vda2" "/mnt${mp}"
done
mount "/dev/vda1" /mnt/boot/efi

step "fstab (what Calamares' fstab module writes)"
cover fstab
root_uuid=$(blkid -s UUID -o value "/dev/vda2")
esp_uuid=$(blkid -s UUID -o value "/dev/vda1")
fstab_opts="rw,${btrfs_opts//defaults,/}"
{
  echo "# /etc/fstab — installed by the MahaDevan's OS install rehearsal"
  for pair in "${subvol_pairs[@]}"; do
    mp="${pair%% *}"
    sv="${pair##* }"
    printf 'UUID=%s  %-12s btrfs  %s,subvol=%s  0 0\n' "$root_uuid" "$mp" "$fstab_opts" "$sv"
  done
  printf 'UUID=%s  /boot/efi    vfat   umask=0077  0 2\n' "$esp_uuid"
} >/mnt/etc/fstab
cat /mnt/etc/fstab

step "machine-id, hostname, locale"
cover machineid
cover locale
cover keyboard
echo mahadevanos-test >/mnt/etc/hostname
cat >/mnt/etc/hosts <<'EOF'
127.0.0.1 localhost
::1       localhost
127.0.1.1 mahadevanos-test.localdomain mahadevanos-test
EOF
echo "LANG=en_US.UTF-8" >/mnt/etc/locale.conf
echo "en_US.UTF-8 UTF-8" >/mnt/etc/locale.gen
echo "KEYMAP=us" >/mnt/etc/vconsole.conf
rm -f /mnt/etc/machine-id
systemd-machine-id-setup --root=/mnt

step "exec: localecfg module (generate the locales of locale.gen)"
cover localecfg
chroot /mnt /usr/bin/locale-gen
[[ -s /mnt/usr/lib/locale/locale-archive ]] || {
  echo "FAIL: localecfg did not produce /usr/lib/locale/locale-archive"
  exit 1
}
echo "ok: locale archive $(stat -c %s /mnt/usr/lib/locale/locale-archive) bytes"

step "create the real user (what Calamares' users module writes)"
cover users
chroot /mnt /usr/bin/useradd -m -G wheel -s /bin/bash tester
echo 'tester:test' | chroot /mnt /usr/bin/chpasswd

step "chroot: mounts for the postinstall scripts"
# --rbind, not --bind: /sys/firmware/efi/efivars is a separate efivarfs mount
# and grub-install needs it to register the NVRAM boot entry.
mount --rbind /dev /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --rbind /run /mnt/run
cp -L /etc/resolv.conf /mnt/etc/resolv.conf

step "exec: displaymanager module (from displaymanager.conf)"
cover displaymanager
# Module semantics from src/modules/displaymanager/main.py: the list comes from
# the config, DMs that are not installed in the target are dropped, an empty
# result is the 75% install failure, and no autologin is written when the users
# page did not set one.
mapfile -t dms < <(awk '/^displaymanagers:/{f=1;next} f&&/^[^[:space:]#]/{f=0} \
  f&&/^[[:space:]]*-/{sub(/^[[:space:]]*-[[:space:]]*/,"",$0); gsub(/[]["[:space:]]/,"",$0); print}' "$CONF/displaymanager.conf")
if (( ${#dms[@]} == 0 )); then
  echo "FAIL: No display managers selected for the displaymanager module."
  echo "      The displaymanagers list is empty or undefined in both globalstorage and displaymanager.conf."
  exit 1
fi
dm_ok=0
for dm in "${dms[@]}"; do
  if [[ -x "/mnt/usr/bin/$dm" || -x "/mnt/usr/sbin/$dm" ]]; then
    echo "displaymanager: $dm is installed"
    dm_ok=1
    chroot /mnt /usr/bin/systemctl enable "$dm.service"
  else
    echo "displaymanager: $dm selected but not installed"
  fi
done
if (( ! dm_ok )); then
  echo "FAIL: No display managers selected for the displaymanager module. The list is empty after checking for installed display managers."
  exit 1
fi
basic_setup=$(awk '/^basicSetup:/{gsub(/[^a-z]/,"",$2); print $2}' "$CONF/displaymanager.conf")
echo "displaymanager: basicSetup=${basic_setup:-false} (package-owned user/group setup stays untouched)"
# The live autologin drop-in is still in the target here: Calamares runs this
# module before the postinstall shellprocess, and 99-cleanup.sh removes it. The
# absence of autologin is asserted after the postinstall scripts below.

step "exec: networkcfg module"
cover networkcfg
install -d -m 700 /mnt/etc/NetworkManager/system-connections
if compgen -G "/etc/NetworkManager/system-connections/*" >/dev/null; then
  cp -f /etc/NetworkManager/system-connections/* /mnt/etc/NetworkManager/system-connections/ || true
  chmod 600 /mnt/etc/NetworkManager/system-connections/* 2>/dev/null || true
fi
chroot /mnt /usr/bin/systemctl enable NetworkManager.service
chroot /mnt /usr/bin/systemctl disable systemd-networkd.service 2>/dev/null || true
echo "ok: live NetworkManager connections copied, NetworkManager enabled"

step "exec: hwclock module"
cover hwclock
printf '0.0 0 0.0\n0\nUTC\n' >/mnt/etc/adjtime
cat /mnt/etc/adjtime

step "exec: services-systemd module (from services-systemd.conf)"
cover services-systemd
unit_fail=0
unit_count=0
while IFS='|' read -r unit action mandatory; do
  [[ -n "$unit" ]] || continue
  action="${action:-enable}"
  mandatory="${mandatory:-false}"
  unit_count=$((unit_count + 1))
  echo "systemctl $action $unit (mandatory=$mandatory)"
  if ! chroot /mnt /usr/bin/systemctl "$action" "$unit"; then
    if [[ "$mandatory" == "true" ]]; then
      echo "FAIL: Cannot $action systemd unit $unit. systemctl $action call in chroot returned an error code."
      unit_fail=1
    else
      echo "warning: Cannot $action systemd unit $unit (mandatory=false, ignored)"
    fi
  fi
done < <(awk '
  /^units:/{f=1;next}
  f&&/^[^[:space:]#]/{f=0}
  f&&/- name:/{if (name != "") print name "|" action "|" mandatory; line=$0; sub(/^[^:]*:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); name=line; action=""; mandatory=""}
  f&&/^[[:space:]]*action:/{line=$0; sub(/^[^:]*:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); action=line}
  f&&/^[[:space:]]*mandatory:/{line=$0; sub(/^[^:]*:[[:space:]]*/,"",line); gsub(/["[:space:]]/,"",line); mandatory=line}
  END{if (name != "") print name "|" action "|" mandatory}
' "$CONF/services-systemd.conf")
(( unit_count > 0 )) || { echo "FAIL: services-systemd.conf defines no units"; exit 1; }
(( unit_fail == 0 )) || exit 1
echo "ok: $unit_count units processed"

step "chroot: postinstall scripts in Calamares module order"
cover shellprocess@postinstall
for script in 10-mkinitcpio 15-branding 20-keyring 30-mirrors 40-snapshots 50-hardware-detect 99-cleanup; do
  echo "--- $script"
  chroot /mnt "/usr/share/mahadevanos/postinstall/${script}.sh"
done

step "assert the postinstall cleanup left no autologin"
if grep -rqsE '^[[:space:]]*AutoLogin|^[[:space:]]*User[[:space:]]*=' \
  /mnt/etc/sddm.conf /mnt/etc/sddm.conf.d 2>/dev/null; then
  echo "FAIL: SDDM still has an autologin user configured after the postinstall cleanup"
  grep -rnE '^[[:space:]]*AutoLogin|^[[:space:]]*User[[:space:]]*=' /mnt/etc/sddm.conf /mnt/etc/sddm.conf.d 2>/dev/null
  exit 1
fi
echo "ok: no autologin in the installed target"

step "chroot: kernel images and initramfs"
ls -l /mnt/boot/vmlinuz-* /mnt/boot/initramfs-*.img
for kernel in linux linux-lts; do
  [[ -s "/mnt/boot/vmlinuz-$kernel" ]] || { echo "ERROR: no vmlinuz-$kernel after postinstall"; exit 1; }
  size=$(stat -c %s "/mnt/boot/vmlinuz-$kernel")
  (( size > 5242880 )) || { echo "ERROR: /boot/vmlinuz-$kernel is only ${size} bytes (expected > 5 MiB)"; exit 1; }
  # GRUB 2.16 reads btrfs files block by block and skips the tail extent: a file
  # that ends mid-block is read short ("premature end of file"). 10-mkinitcpio.sh
  # pads every /boot file to a 4096-byte multiple.
  (( size % 4096 == 0 )) || {
    echo "ERROR: /boot/vmlinuz-$kernel is ${size} bytes, $(( size % 4096 )) over a 4096-byte boundary; GRUB reads that short"
    exit 1
  }
  echo "ok: /boot/vmlinuz-$kernel ${size} bytes (block-aligned for GRUB)"
done
for img in /mnt/boot/initramfs-linux.img /mnt/boot/initramfs-linux-lts.img; do
  size=$(stat -c %s "$img")
  (( size % 4096 == 0 )) || { echo "ERROR: $img is ${size} bytes, not block-aligned; GRUB reads it short"; exit 1; }
  echo "ok: $img ${size} bytes (block-aligned for GRUB)"
done
[[ -s /mnt/boot/initramfs-linux.img ]] || { echo "ERROR: no initramfs-linux.img after postinstall"; exit 1; }
[[ -s /mnt/boot/initramfs-linux-lts.img ]] || { echo "ERROR: no initramfs-linux-lts.img after postinstall"; exit 1; }

# The 2026-11-22 boot failure was GRUB reading a zstd-compressed kernel off
# btrfs. /boot must be marked NOCOW/no-compression so both kernels are stored
# uncompressed (postinstall/10-mkinitcpio.sh sets this before writing them).
boot_flags=$(lsattr -d /mnt/boot | awk '{print $1}')
echo "/boot attributes: ${boot_flags:-none}"
[[ "$boot_flags" == *C* ]] || { echo "FAIL: /boot lacks the btrfs C flag; GRUB may not be able to read the kernels"; exit 1; }
echo "ok: /boot is uncompressed for GRUB"

step "exec: grubcfg module (from grubcfg.conf)"
cover grubcfg
# Module semantics from src/modules/grubcfg/main.py: kernel_params are merged
# into GRUB_CMDLINE_LINUX_DEFAULT, every other key in /etc/default/grub is kept,
# and on a btrfs root GRUB_SAVEDEFAULT is forced to false. console=ttyS0 and a
# longer timeout are added by this test only, so the installed disk is reachable
# on the serial console the boot test drives.
mapfile -t kernel_params < <(awk '/^kernel_params:/{f=1;next} f&&/^[^[:space:]#]/{f=0} \
  f&&/^[[:space:]]*-/{sub(/^[[:space:]]*-[[:space:]]*/,"",$0); gsub(/[]["[:space:]]/,"",$0); print}' "$CONF/grubcfg.conf")
echo "kernel_params: ${kernel_params[*]:-<none>}"
grub_params="${kernel_params[*]:-quiet} console=ttyS0"
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${grub_params}\"|" /mnt/etc/default/grub
sed -i 's|^GRUB_SAVEDEFAULT=.*|GRUB_SAVEDEFAULT=false|' /mnt/etc/default/grub
sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=10|' /mnt/etc/default/grub
grep -q '^GRUB_TOP_LEVEL="/boot/vmlinuz-linux"' /mnt/etc/default/grub \
  || { echo "FAIL: GRUB_TOP_LEVEL for the linux kernel was lost from /etc/default/grub"; exit 1; }
grep -E '^(GRUB_CMDLINE_LINUX_DEFAULT|GRUB_SAVEDEFAULT|GRUB_TIMEOUT|GRUB_TOP_LEVEL|GRUB_TERMINAL_(IN|OUT)PUT)=' /mnt/etc/default/grub

step "chroot: bootloader (grub-install + grub-mkconfig)"
cover bootloader
# installEFIFallback from bootloader.conf decides the removable-path install.
install_fallback=$(awk '/^installEFIFallback:/{gsub(/[^a-z]/,"",$2); print $2}' "$CONF/bootloader.conf")
bootloader_id=$(awk '/^efiBootloaderId:/{gsub(/["[:space:]]/,"",$2); print $2}' "$CONF/bootloader.conf")
bootloader_id="${bootloader_id:-mahadevanos}"
echo "efiBootloaderId=$bootloader_id installEFIFallback=${install_fallback:-false}"
# Both an NVRAM entry (what Calamares does) and the removable fallback path
# (installEFIFallback: true in bootloader.conf), so the disk boots even if the
# firmware forgets the entry.
chroot /mnt /usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot/efi \
  --bootloader-id="$bootloader_id"
if [[ "${install_fallback:-false}" == "true" ]]; then
  chroot /mnt /usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --removable
fi
chroot /mnt /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg

step "GRUB's own reader against the installed disk (the premature-EOF check)"
# This is the failing component from 2026-11-22:
#   error: loader/efi/linux.c:grub_cmd_linux:700:premature end of file
#   /@/boot/vmlinuz-linux-lts
# grub-fstest runs the same btrfs/zstd code in the installed GRUB, so a short
# read or a size mismatch here is the boot failure, caught before it boots.
grub_fail=0
if command -v grub-fstest >/dev/null 2>&1; then
  grub-fstest "${DISK}2" ls /@/boot || grub_fail=1
  for kernel in linux linux-lts; do
    rm -f "/tmp/grub-read-$kernel"
    if ! grub-fstest "${DISK}2" cp "/@/boot/vmlinuz-$kernel" "/tmp/grub-read-$kernel"; then
      echo "FAIL: grub-fstest could not read /@/boot/vmlinuz-$kernel"
      grub_fail=1
      continue
    fi
    grub_size=$(stat -c %s "/tmp/grub-read-$kernel" 2>/dev/null || echo 0)
    disk_size=$(stat -c %s "/mnt/boot/vmlinuz-$kernel")
    echo "grub reads /@/boot/vmlinuz-$kernel: ${grub_size} bytes (on disk: ${disk_size})"
    if (( grub_size != disk_size )) || (( grub_size < 5242880 )); then
      echo "FAIL: GRUB sees a truncated kernel for $kernel"
      grub_fail=1
    elif ! cmp -s "/tmp/grub-read-$kernel" "/mnt/boot/vmlinuz-$kernel"; then
      echo "FAIL: what GRUB reads from /@/boot/vmlinuz-$kernel differs from the file on disk"
      grub_fail=1
    else
      echo "ok: what GRUB reads from /@/boot/vmlinuz-$kernel is byte-identical"
    fi
  done
else
  echo "FAIL: grub-fstest is missing, GRUB's reader cannot be tested"
  grub_fail=1
fi
(( grub_fail == 0 )) || exit 1

step "assert the first GRUB entry is the regular linux kernel"
first_entry=$(awk '/^[[:space:]]*menuentry /{n++} n==1{print} n==2{exit}' /mnt/boot/grub/grub.cfg)
printf '%s\n' "$first_entry" | head -3
if grep -qE 'vmlinuz-linux([[:space:]]|$)' <<<"$first_entry"; then
  echo "ok: entry 0 boots /@/boot/vmlinuz-linux"
else
  echo "FAIL: entry 0 does not boot the regular linux kernel (GRUB_TOP_LEVEL lost?)"
  exit 1
fi
grep -q 'vmlinuz-linux-lts' /mnt/boot/grub/grub.cfg || { echo "FAIL: no linux-lts fallback entry in grub.cfg"; exit 1; }
echo "ok: linux-lts is present as the fallback entry"

step "chroot: verify the target has no live-only artefacts"
chroot /mnt /bin/bash -c '
  set -u
  rc=0
  id liveuser >/dev/null 2>&1 && { echo "FAIL liveuser exists"; rc=1; } || echo "ok: no liveuser"
  [ -e /home/liveuser ] && { echo "FAIL /home/liveuser exists"; rc=1; } || echo "ok: no /home/liveuser"
  [ -e /etc/sudoers.d/10-liveuser ] && { echo "FAIL live sudo rule"; rc=1; } || echo "ok: no live sudo rule"
  [ -e /usr/bin/calamares ] && { echo "FAIL calamares present"; rc=1; } || echo "ok: no calamares"
  [ -e /usr/local/bin/mahadevanos-installer ] && { echo "FAIL installer wrapper present"; rc=1; } || echo "ok: no installer wrapper"
  [ -e /etc/calamares ] && { echo "FAIL /etc/calamares present"; rc=1; } || echo "ok: no /etc/calamares"
  [ -e /etc/sddm.conf.d/10-live-autologin.conf ] && { echo "FAIL live autologin"; rc=1; } || echo "ok: no live autologin"
  [ -f /etc/xdg/hypr/hyprland.lua ] && echo "ok: installed hyprland.lua present" || { echo "FAIL hyprland.lua missing"; rc=1; }
  grep -rqsE "mahadevanos-installer|calamares" /etc/skel /etc/xdg/hypr && { echo "FAIL skel/xdg references installer"; rc=1; } || echo "ok: no installer reference in skel/xdg"
  exit $rc
'

step "unmount"
cover umount
# The chroot bind mounts keep /mnt busy; lazy unmount after the sync is enough
# for a VM that is about to power off.
sync
for dir in /mnt/run /mnt/sys /mnt/proc /mnt/dev; do umount -l "$dir" 2>/dev/null || true; done
umount -lR /mnt 2>/dev/null || true
findmnt -R /mnt || echo "all target mounts released"

step "assert the disk really carries the installed system"
# "Nothing was installed" is the 2026-11-22 failure mode; check the disk itself.
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL,UUID "$DISK"
for part in "${DISK}1" "${DISK}2"; do
  [[ -b "$part" ]] || { echo "FAIL: $part does not exist on the disk after the install"; exit 1; }
done
esp_fstype=$(blkid -s TYPE -o value "${DISK}1")
root_fstype=$(blkid -s TYPE -o value "${DISK}2")
echo "${DISK}1: ${esp_fstype:-<none>}  ${DISK}2: ${root_fstype:-<none>}"
[[ "$esp_fstype" == "vfat" ]] || { echo "FAIL: ${DISK}1 is not a FAT filesystem (got '${esp_fstype:-none}')"; exit 1; }
[[ "$root_fstype" == "btrfs" ]] || { echo "FAIL: ${DISK}2 is not Btrfs (got '${root_fstype:-none}')"; exit 1; }

step "exec coverage: every module in settings.conf's exec phase ran here"
missing_exec=()
for key in "${EXEC_MODULES[@]}"; do
  [[ -n "${covered[$key]:-}" ]] || missing_exec+=("$key")
done
echo "exec jobs covered: ${#covered[@]}/${#EXEC_MODULES[@]}"
if (( ${#missing_exec[@]} )); then
  echo "FAIL: the rehearsal never ran: ${missing_exec[*]}"
  exit 1
fi
(( ${#covered[@]} == ${#EXEC_MODULES[@]} )) || {
  echo "FAIL: covered ${#covered[@]} of ${#EXEC_MODULES[@]} exec modules"
  exit 1
}
printf 'ok: %d/%d exec modules exercised\n' "${#covered[@]}" "${#EXEC_MODULES[@]}"

step "rehearsal complete"
exit 0
