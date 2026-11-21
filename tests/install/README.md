# Automated install rehearsal

`scripts/test-install-auto.sh --install` boots the built ISO with a blank
`build/test-disk.qcow2` attached and, over the serial console, runs
`tests/install/rehearsal.sh` inside the live system as root.

It is **not** the Calamares GUI. It performs the same work the installer's
`partition`, `mount`, `unpackfs`, `shellprocess` and `bootloader` modules perform,
and it reads the layout and mount setup **from the shipped
`/etc/calamares/modules/*.conf`** instead of hardcoding them:

0. Regression guards on the shipped config: exactly one `partitionLayout` entry
   (the Btrfs root — Calamares prepends the ESP itself), `filesystem:` rather
   than the ignored `fs:`, `efi.recommendedSize` >= 1024MiB, `btrfsSubvolumes`
   in `mount.conf`, `script:` in `shellprocess.conf`, and `preflight` before
   `unpackfs` in `settings.conf`.
1. GPT: one ESP (`ef00`, sized by `efi.recommendedSize`) + Btrfs root (`8300`)
   on `/dev/vda` — a qcow2 file, no host device is attached to the VM.
2. Btrfs subvolumes, mount points and options parsed from `mount.conf`, plus the
   fstab Calamares' fstab module would write.
3. The preflight guard (`/usr/share/mahadevanos/calamares/check-root-mount.sh`)
   is tested both ways: it must reject a tmpfs directory and accept the real
   mounted target root.
4. `unsquashfs /run/archiso/bootmnt/arch/x86_64/airootfs.sfs` onto the target.
5. A user (`tester`) the way Calamares' users module creates one.
6. Every `installer/postinstall/*.sh` in the chroot, in Calamares' order —
   including `10-mkinitcpio.sh` (kernel restore + initramfs) and `99-cleanup.sh`
   (which fails the install if anything live-only survives).
7. `grub-install` (NVRAM entry and removable fallback) + `grub-mkconfig`.
8. An assertion block that checks no live-only artefact reached the target.

Then `--boot-installed` boots the same disk **without the ISO** and runs
`tests/install/verify-installed.sh` as the unprivileged `tester` user, which
proves the system boots, the kernel and initramfs are on disk, no live user or
passwordless sudo survives, and the installer is gone.

Evidence: `tests/evidence/<date>/install-rehearsal.{log,txt}` and
`installed-boot.{log,txt}`.

The hand-clicked GUI walkthrough is still a human step:
`documentation/installation/manual-test.md`.
