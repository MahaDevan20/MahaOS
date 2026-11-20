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

### Known limitations
- The ISO has not been built in this checkout: the host lacks `archiso`, `devtools`,
  `shellcheck` and `squashfs-tools`.
- `calamares` and `ckbcomp` are not yet present in `repo/`; `build-repo.sh` builds
  them from the AUR in a clean chroot.
- NVIDIA proprietary drivers, LUKS encryption and install-alongside-Windows are
  experimental/deferred (M5 and later).
