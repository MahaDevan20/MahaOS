# Changelog

All notable changes to MahaDevan's OS. Format loosely follows Keep a Changelog.

## [Unreleased]

### Added
- Repository scaffold per blueprint v2: `iso/`, `installer/`, `packaging/`, `configs/`,
  `profiles/`, `scripts/`, `tests/`, `documentation/`, `branding/`.
- archiso profile `iso/profile/` with label `MAHADEVANOS_YYYYMM`, `os-release`
  (`ID=mahadevanos`, `ID_LIKE=arch`), pinned Arch Linux Archive `pacman.conf`,
  split package lists, live user, SDDM autologin, Calamares autostart, safe-graphics
  boot entry.
- Build scripts: `build-repo.sh`, `build-iso.sh`, `test-boot.sh`, `test-install.sh`,
  `checksum.sh`, `generate-package-list.sh`, `lib.sh`. Checksum + manifest generation
  and a repo-origin check that fails on non-Arch packages.
- Calamares offline installer configuration (`unpackfs` of `airootfs.sfs`), Btrfs
  subvolume layout, GRUB UEFI bootloader ID `mahadevanos`, post-install cleanup,
  mkinitcpio regeneration, keyring populate, mirrorlist, services.
- snapper + snap-pac + grub-btrfs configuration and GRUB defaults for snapshot booting.
- Post-install profiles for gaming, dev, virtualization, ai and the zen kernel.
- Documentation: host check, build, architecture, manual install test, snapshot
  recovery, known issues.

### Fixed (2026-11-22, first hand-clicked install findings)
- `displaymanager.conf`: `services:` is not a Calamares 3.4.2 key; replaced with
  `displaymanagers: [sddm]` and `basicSetup: false`. This was the 75% install
  failure (“No display managers selected for the displaymanager module”).
- Installed `/boot` is zstd-compressed btrfs, which GRUB cannot read reliably
  (“premature end of file /@/boot/vmlinuz-linux-lts”). `/boot` is now marked
  NOCOW/no-compression before the kernels are written, kernels are restored from
  `/usr/lib/modules/<kver>/vmlinuz`, and a kernel under 5 MiB fails the install.
- `linux` is the default GRUB entry (`GRUB_TOP_LEVEL`), `linux-lts` stays as the
  fallback.
- The `finished` module is in the show sequence (`finished.conf`), so the install
  ends with a working restart button instead of a stuck 100% page.
- `initialPartitioningChoice: erase`, a maximized installer window
  (`windowExpanding: fullscreen`) and removal of stale
  `/tmp/calamares-root-*` mounts so “Erase disk” is offered and preselected.
- Module configs corrected against the 3.4.2 schemas: `fstab.conf`
  (`tmpOptions`), `grubcfg.conf` (`kernel_params`), `users.conf` (`user.shell`),
  `welcome.conf` (`requirements`), plus explicit `mandatory:` on every
  `services-systemd` unit.
- Tests: `tests/install/rehearsal.sh` audits every module config against the
  Calamares 3.4.2 schema and runs the full exec sequence; the installed-disk test
  boots both kernels, asserts kernel sizes above 5 MiB and checks that GRUB reads
  them byte-identically.

### Known limitations
- The ISO has not been built in this checkout: the host lacks `archiso`, `devtools`,
  `shellcheck` and `squashfs-tools`.
- `calamares` and `ckbcomp` are not yet present in `repo/`; `build-repo.sh` builds
  them from the AUR in a clean chroot.
- NVIDIA proprietary drivers, LUKS encryption and install-alongside-Windows are
  experimental/deferred (M5 and later).
