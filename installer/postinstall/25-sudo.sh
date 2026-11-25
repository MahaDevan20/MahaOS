#!/usr/bin/env bash
# Runs inside the target chroot, after the users module created the account.
#
# Calamares' users module creates the account with the groups from users.conf
# (defaultGroups includes wheel), but Arch's `sudo` package ships the wheel rule
# COMMENTED OUT in /etc/sudoers. Without a rule, sudo answers "user is not in the
# sudoers file" and every documented recovery step (documentation/recovery/,
# `mhelp recovery`, `snapper`, `mkinitcpio`) is impossible for the one account
# this system has.
#
# The rule added here requires a password: 99-cleanup.sh still fails the install
# whenever a NOPASSWD rule exists, live or not.
set -euo pipefail

export LC_ALL=C

echo ":: [mahadevanos] enabling sudo for the wheel group"

# A drop-in rather than an edit of /etc/sudoers, so a sudo package update cannot
# conflict with it and its contents are obvious. Only this file is checked: some
# other drop-in may also grant wheel, and a duplicate rule is harmless, while a
# missing file is not.
if [[ -f /etc/sudoers.d/10-wheel ]] &&
   grep -qE '^[[:space:]]*%wheel[[:space:]]+ALL' /etc/sudoers.d/10-wheel; then
  echo ":: [mahadevanos] /etc/sudoers.d/10-wheel already grants wheel"
else
  printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/10-wheel
  chmod 440 /etc/sudoers.d/10-wheel
  echo ":: [mahadevanos] wrote /etc/sudoers.d/10-wheel (%wheel ALL=(ALL:ALL) ALL)"
fi

# users.conf already asks for wheel; make it true instead of assuming it.
if getent group wheel >/dev/null 2>&1; then
  while IFS=: read -r name _ uid _; do
    [[ "$uid" =~ ^[0-9]+$ ]] || continue
    (( uid >= 1000 && uid < 60000 )) || continue
    [[ "$name" == "nobody" ]] && continue
    if id -nG "$name" 2>/dev/null | tr ' ' '\n' | grep -qx wheel; then
      echo ":: [mahadevanos] $name is in wheel"
    else
      usermod -aG wheel "$name"
      echo ":: [mahadevanos] added $name to wheel"
    fi
  done </etc/passwd
else
  echo ":: [mahadevanos] WARNING: there is no wheel group; sudo stays unavailable" >&2
fi

# A broken sudoers must fail the install here, not at the user's first recovery
# attempt. visudo -c parses /etc/sudoers and every drop-in it includes.
if ! visudo -c -q >/dev/null 2>&1; then
  echo ":: [mahadevanos] ERROR: the sudoers configuration is invalid" >&2
  visudo -c 2>&1 | tail -5 >&2 || true
  exit 1
fi

echo ":: [mahadevanos] sudo configuration verified"
