# MahaDevan's OS

**Display name:** MahaDevan's OS — **technical slug:** `mahadevanos`
**Base:** Arch Linux, x86_64, UEFI-first — **Build host:** Arch-based (CachyOS/Garuda)

An Arch-based distribution with a Garuda-style offline install: boot the USB, get a
working Hyprland desktop, click **Install MahaDevan's OS**, answer a few questions,
reboot into a finished Btrfs + GRUB + snapper system. Nothing is downloaded during
the install.

This repository is driven by [`OS_BLUEPRINT.md`](OS_BLUEPRINT.md). If the blueprint
and this README disagree, the blueprint wins.

---

## Status

Honest labels only: `TESTED`, `IMPLEMENTED (untested)`, `EXPERIMENTAL`, `PLANNED`.

| Milestone | Scope | Status |
|---|---|---|
| M0 | Host check and repository scaffold | `TESTED` for the scaffold; host is missing `archiso`, `devtools`, `shellcheck`, `squashfs-tools` (see `documentation/development/host-check.md`) |
| M1 | Bootable minimal live ISO | `TESTED` — `out/mahadevanos-2026.11.21-x86_64.iso` boots under UEFI QEMU (OVMF, 4 GiB) to SDDM → Hyprland as `liveuser`, and the **safe graphics** entry boots too; evidence in `tests/evidence/2026-11-21/` |
| M2 | Calamares offline installer + minimal desktop | `TESTED` for live autostart, the offline install pipeline (one 1024 MiB ESP + one Btrfs root, `@`/`@home`/`@log`/`@cache`/`@snapshots`, pre-unpackfs root-mount guard) and the installed-system boot (`scripts/test-boot.sh --disk`, `scripts/test-install-auto.sh`); the hand-clicked Calamares GUI walkthrough is still `IMPLEMENTED (untested)` |
| M3 | Btrfs snapshots and recovery | `IMPLEMENTED (untested)` |
| M4 | Desktop experience and branding | `PLANNED` (Hyprland config stub only) |
| M5 | Hardware detection, profiles, optional LUKS | `EXPERIMENTAL` (`profiles/`, `installer/postinstall/60-hardware-detect.sh`) |

The installer is verified by `scripts/test-install-auto.sh --install`, which now
runs the modules of the shipped `settings.conf` exec sequence (including
`displaymanager`, `services-systemd` and `grubcfg`), audits every module config
against the Calamares 3.4.2 schema, and fails on any key Calamares would ignore;
`--boot-installed --kernel both` then boots the installed disk on `linux` **and**
`linux-lts` and requires the login prompt on both. See
`tests/install/README.md` and `documentation/known-issues.md`.

An ISO is built at `out/mahadevanos-2026.11.21-x86_64.iso` (2.6 GiB, 718 packages, pinned 2026/11/01).
The claim that it boots is backed by `tests/evidence/2026-11-21/` (serial logs, probe output,
framebuffer screenshots for the default and safe-graphics entries). The install pipeline and
the boot of the installed disk are backed by `tests/evidence/2026-11-21/install-rehearsal.*`
and `installed-boot.*`; that harness mirrors the Calamares modules rather than clicking through
the GUI, so the hand-clicked Calamares walkthrough itself is still untested.

---

## Quick start

```bash
# 0. Host tools (Arch-based host). These are the M0 requirements:
sudo pacman -S --needed archiso devtools qemu-full edk2-ovmf git base-devel \
  squashfs-tools libisoburn mtools shellcheck

# 1. Build calamares + ckbcomp into the local repo (clean chroot, no root builds)
./scripts/build-repo.sh

# 2. Concatenate iso/packages/*.txt and build the ISO
./scripts/build-iso.sh

# 3. Boot it under UEFI QEMU and capture evidence
./scripts/test-boot.sh
```

Output lands in `out/`:

```
out/mahadevanos-<date>-x86_64.iso
out/mahadevanos-<date>-x86_64.iso.sha256
out/mahadevanos-<date>-x86_64.iso.manifest.txt
out/build.log
out/test-boot.log
out/test-boot.png
```

Verify a download with `sha256sum -c out/*.sha256`.

---

## Layout

```text
branding/      logos, wallpapers, GRUB theme, Calamares branding, Plymouth
iso/profile/   archiso profile (profiledef.sh, pacman.conf, airootfs/, efiboot/)
iso/packages/  split package lists: base.txt desktop.txt live-only.txt firmware.txt
iso/checks/    repo-origin and manifest checks
installer/     Calamares settings/modules/branding + post-install shellprocess scripts
packaging/     PKGBUILDs for mahadevanos-branding, calamares-config, mahadevanos-settings
repo/          local pacman repo (binaries gitignored, PKGBUILDs tracked)
configs/       hyprland, kitty, dolphin, sddm, snapper, grub, ufw, quickshell
profiles/      post-install profiles: gaming, dev, virtualization, ai
scripts/       build-repo.sh, build-iso.sh, test-boot.sh, test-install.sh, checksum.sh
tests/         automation + evidence/
documentation/ build, install, recovery, architecture, known issues
```

## Rules that matter

- Installer is **offline** (`unpackfs` of the live squashfs). No `pacstrap`, no downloads.
- Reuse mature components. No homemade kernel, compositor, package manager or installer.
- All scripts are `bash` with `set -euo pipefail`.
- Never touch real disks from automation. Disk tests use `build/test-disk.qcow2`.
- No AUR builds as root; review every PKGBUILD.
- Never claim a boot test passed without a saved log.

## Documentation

- [Build](documentation/development/build.md)
- [Host check](documentation/development/host-check.md)
- [Architecture](documentation/architecture.md)
- [Manual install test](documentation/installation/manual-test.md)
- [Snapshot rollback and GRUB repair](documentation/recovery/snapshot-rollback.md)
- [Known issues](documentation/known-issues.md)

## License

MIT — see [LICENSE](LICENSE). Upstream components keep their own licenses.
