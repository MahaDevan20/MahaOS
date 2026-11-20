# Building MahaDevan's OS

## Prerequisites

Build host: Arch-based (CachyOS, Garuda, Arch), x86_64, ~30 GiB free, KVM for testing.

```bash
sudo pacman -S --needed archiso devtools squashfs-tools shellcheck libisoburn mtools \
  qemu-full edk2-ovmf base-devel git
```

The host's own repositories are irrelevant to the artifact: the ISO builds from
the pinned Arch Linux Archive date in `iso/profile/PINNED_DATE`, using
`iso/profile/pacman.conf`, which lists **only** `core`, `extra` and the local repo.

## 1. Local repository

`calamares` and `ckbcomp` are AUR packages and are not in the official repos.

```bash
./scripts/build-repo.sh
```

This packages `packaging/*/SOURCES` into a tarball per package, builds each in a
clean chroot (`extra-x86_64-build`), copies the result to `repo/x86_64/` and runs
`repo-add` to create `mahadevanos-local.db.tar.zst`.

Review before building: the script prints each PKGBUILD's `pkgname/pkgver/source`
lines. Nothing here should download at build time — the packages are local
configuration only.

## 2. ISO

```bash
./scripts/build-iso.sh
```

What the script does, in order:

1. Regenerates `iso/profile/packages.x86_64` from `iso/packages/*.txt`.
2. Copies the profile to `build/profile` (the tracked profile is never mutated).
3. Rewrites the local repo `Server` line to this checkout's absolute path.
4. Resolves `@ISO_LABEL@` in the boot entries to `MAHADEVANOS_YYYYMM`.
5. Runs `sudo mkarchiso -v -w build/work -o out build/profile`.
6. Writes `out/mahadevanos-<date>-x86_64.iso.manifest.txt` from the built airootfs,
   then runs `iso/checks/check-repo-origins.sh` on it.
7. Writes the `.sha256`.

Pinning: `ARCHISO_PINNED_DATE` comes from `PINNED_DATE`; change the date to move
the whole ISO to a newer Arch snapshot. The **installed** system always uses normal
mirrors — the install script rewrites the mirrorlist.

Repeatability: builds are *repeatable*, not bit-identical. Arch is rolling.

## 3. Tests

```bash
./scripts/test-boot.sh        # UEFI QEMU boot, serial log + screenshot in out/
./scripts/test-install.sh --prepare        # attach build/test-disk.qcow2
./scripts/test-install.sh --boot-installed # installed disk, no ISO
```

Then follow `documentation/installation/manual-test.md` for the GUI walkthrough,
which cannot be automated.

## 4. Output

```
out/mahadevanos-<date>-x86_64.iso
out/mahadevanos-<date>-x86_64.iso.sha256
out/mahadevanos-<date>-x86_64.iso.manifest.txt
out/build.log
out/test-boot.log, out/test-boot.png
```

Target size is 3–5 GB. Do not remove firmware to hit a number.

## Troubleshooting

- **`mkarchiso: command not found`** → `sudo pacman -S archiso`.
- **repo-origin check fails** → a package came from a host repository. The build
  `pacman.conf` must list Arch + `mahadevanos-local` only.
- **`package not found` during the build** → the pinned archive date may predate a
  package, or a name in `iso/packages/*.txt` is wrong. Fix the name, or move
  `PINNED_DATE` forward.
- **Calamares missing in the live session** → `repo/x86_64/` was not built or is
  empty; run `scripts/build-repo.sh`.
