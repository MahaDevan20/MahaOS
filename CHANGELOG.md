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

### Fixed (2026-11-22, second hand-clicked install: nothing was installed)
- `settings.conf` put `finished` at the end of the summary *show* list, so it sat
  between the summary page and the exec phase. Calamares keeps the phase order it
  is given and `FinishedViewStep` is `isAtEnd() == true` with `isNextEnabled() ==
  false`, so clicking Install jumped straight to "All done ... has been installed"
  and the exec phase was unreachable: no partitioning, no unpackfs, no bootloader,
  and the firmware then said `BdsDxe: No bootable option or device was found`.
  The sequence is now `show(welcome..summary)` -> `exec(...)` -> `show(finished)`.
- `quit-at-end` is now `false`. With `true`, `ViewManager::updateButtonLabels()`
  quits Calamares the instant the finished page is the last step, which hid the
  page and left its restart control inert.
- `finished.conf`: `restartNowMode: user-checked` and
  `restartNowCommand: "systemctl reboot"`, so Done really restarts into the
  installed system (it previously only closed the installer).
- `configs/grub/grub-defaults`: `GRUB_DISABLE_SUBMENU=y`, so `linux-lts` is a
  top-level fallback entry instead of being hidden in "Advanced options".
- **`error: loader/efi/linux.c:grub_cmd_linux:700:premature end of file`**: GRUB
  2.16 reads btrfs files block by block and skips the final partial block, so a
  kernel whose size is not a multiple of 4096 is always read short (measured with
  `grub-fstest`: 17,244,160 of 17,244,672 bytes, for both compressed and
  `chattr +C` copies). `installer/postinstall/10-mkinitcpio.sh` now pads every
  `/boot` file (both kernels, both initramfs) to a 4096-byte multiple after
  `mkinitcpio -P` and fails the install if one is unaligned. `grub-fstest` then
  reads both kernels completely and both boot.
- `grubcfg.conf`: the installed command line is
  `quiet nowatchdog zswap.enabled=0 console=tty0 console=ttyS0,115200`, so the
  installed system has a login prompt on a serial console (GRUB already used
  serial, and systemd's getty generator follows `console=`).
- New `scripts/test-install-gui.sh` (+ `scripts/qemu-gui.py`): drives the real
  Calamares pages in QEMU through the monitor's `sendkey`/`screendump`, reads
  them back with tesseract, then audits the install from inside the live system
  (`tests/install/gui-install-audit.sh`): every queued job must start, both
  partitions must exist, the unpacked root must be populated, each module's
  effect must be on disk, and the restart control must reboot the machine.
- `tests/install/rehearsal.sh`: requires the sequence to be exactly
  show -> exec -> show(finished) with `quit-at-end: false`, at least 16 exec
  entries, coverage of every one of them, real content after unpackfs, and both
  partitions on the disk at the end.
- `scripts/qemu-serial-run.py`: nudges a getty that printed its prompt before the
  client connected, and reuses a shell a previous run left open.

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
