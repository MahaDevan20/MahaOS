# Automated install rehearsal

`scripts/test-install-auto.sh --install` boots the built ISO with a blank
`build/test-disk.qcow2` attached and, over the serial console, runs
`tests/install/rehearsal.sh` inside the live system as root.

It is **not** the Calamares GUI. It runs the modules of the shipped
`/etc/calamares/settings.conf` exec sequence, reading each module's
configuration from `/etc/calamares/modules/`:

0. **Audit of every module config against Calamares 3.4.2.** Each top-level key
   in `settings.conf`'s module conf files is checked against the key set of
   `src/modules/<module>/<module>.schema.yaml` in the 3.4.2 tree (all of which
   declare `additionalProperties: false`), plus the schema's `required:` keys and
   the conditions that actually broke installs:
   `displaymanagers` non-empty, `initialPartitioningChoice: erase`, explicit
   `mandatory:` on every `services-systemd` unit, and `finished` in the show
   sequence with `restartNowEnabled`/`restartNowChecked`.
1. Regression guards on the shipped layout: exactly one `partitionLayout` entry
   (the Btrfs root — Calamares prepends the ESP itself), `filesystem:` rather
   than the ignored `fs:`, `efi.recommendedSize` >= 1024MiB, `btrfsSubvolumes`
   in `mount.conf`, `script:` in `shellprocess.conf`, and `preflight` before
   `unpackfs`.
2. GPT: one ESP (`ef00`, sized by `efi.recommendedSize`) + Btrfs root (`8300`)
   on `/dev/vda` — a qcow2 file, no host device is attached to the VM.
3. Btrfs subvolumes, mount points and options parsed from `mount.conf`, plus the
   fstab Calamares' fstab module would write.
4. The preflight guard (`/usr/share/mahadevanos/calamares/check-root-mount.sh`)
   is tested both ways: it must reject a tmpfs directory and accept the real
   mounted target root.
5. `unsquashfs /run/archiso/bootmnt/arch/x86_64/airootfs.sfs` onto the target.
6. A user (`tester`) the way Calamares' users module creates one.
7. **The other exec modules, from their shipped configs**:
   `displaymanager` (the DM list must be non-empty and installed, no autologin in
   the target), `networkcfg`, `hwclock`, `services-systemd` (each unit's action
   and `mandatory` flag respected — a non-mandatory unit that fails is only a
   warning), then every `installer/postinstall/*.sh` in Calamares' order
   (kernel restore + initramfs, branding, keyring, mirrors, snapper, hardware
   detection, cleanup), then `grubcfg` (kernel params merged, `GRUB_TOP_LEVEL`
   preserved) and `bootloader` (`efiBootloaderId`, `installEFIFallback`).
8. **Kernel assertions**: `/boot/vmlinuz-linux` and `/boot/vmlinuz-linux-lts`
   exist, are larger than 5 MiB, `/boot` carries the btrfs `C` (NOCOW/no
   compression) flag, and `grub-fstest` — the installed GRUB's own btrfs reader —
   reads both kernels back byte-identically. The first GRUB entry must boot the
   regular `linux` kernel with `linux-lts` present as fallback.
9. An assertion block that checks no live-only artefact reached the target.

Then `--boot-installed` boots the same disk **without the ISO**, once per kernel:
it picks the GRUB entry over the serial console (entry 0 = `linux`, entry 1 =
`linux-lts`, exposed by `GRUB_TERMINAL_*` in `configs/grub/grub-defaults`) and
runs `tests/install/verify-installed.sh` as the unprivileged `tester` user. That
proves both kernels reach the login prompt, the kernel and initramfs are on disk
and complete, no live user or passwordless sudo survives, and the installer is
gone.

```bash
scripts/test-install-auto.sh --install
scripts/test-install-auto.sh --boot-installed --kernel both     # default
scripts/test-install-auto.sh --boot-installed --kernel linux-lts
```

Evidence: `tests/evidence/<date>/install-rehearsal.{log,txt}` and
`installed-boot-{linux,lts}.{log,txt}`.

## Why the earlier rehearsal passed while the hand-clicked install failed

The 2026-11-21 rehearsal only ran `partition`, `mount`, `unpackfs`, `fstab`,
`users`, the postinstall scripts and `bootloader`. It never ran
`displaymanager`, `services-systemd`, `networkcfg`, `hwclock` or `grubcfg`, and
it validated only the handful of keys those steps happened to parse. So
`displaymanager.conf`'s invalid `services:` list (which makes Calamares abort at
75% with “No display managers selected”) could not fail the test, and neither
could `fstab.conf`'s dead `efiMountOptions:` key or `grubcfg.conf`'s singular
`kernelParam:`. The test now audits every key against the 3.4.2 schema and runs
those modules, so a config that Calamares would reject fails here instead.

The hand-clicked GUI walkthrough is still a human step:
`documentation/installation/manual-test.md`.
