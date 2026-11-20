# Security policy

## Reporting a vulnerability

Report privately by email to the maintainer address recorded on the project page.
Do not open a public issue for an unfixed privilege-escalation, installer,
bootloader or disk-handling defect. Expect an acknowledgement within a week.

## Design rules enforced by this repository

- The **live user is passwordless only in the live session** (`liveuser` plus a
  `/etc/sudoers.d/10-liveuser` rule inside `iso/profile/airootfs`). Post-install
  cleanup removes the user, the sudoers rule and SDDM autologin.
- **No broad passwordless sudo** is written to an installed system.
- The firewall (`ufw`) is enabled with deny-incoming and no extra allows.
- Calamares shows the exact target device and requires explicit confirmation;
  this is never weakened.
- AUR packages are built **only** in a clean chroot (`extra-x86_64-build`), never
  as root, and every PKGBUILD is reviewed before it is built.
- Keys, tokens and `.env` files never enter git (`.gitignore` covers
  `keys/`, `.env`, `*.gpg`, `*.key`).
- ISO builds pin the Arch Linux Archive date for repeatability. The **installed**
  system uses normal mirrors, and `pacman-key --populate archlinux` runs
  post-install so the live keyring state is never reused.

## Secure Boot

Not supported in v1. The ISO and installed system boot with Secure Boot disabled.
Enabling it means signing the kernel and GRUB with your own keys; that is a
post-beta task.

## Scope

Security issues in upstream Arch packages, GRUB, Calamares or Hyprland should go
to those projects. Report here if this repository's configuration makes an
upstream issue worse or enables it by default.
