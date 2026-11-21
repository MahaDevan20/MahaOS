# Boot and install tests

Automated where an agent reasonably can; the Calamares GUI walkthrough is a human
step (`documentation/installation/manual-test.md`).

| Script | What it proves | Evidence |
|---|---|---|
| `scripts/test-boot.sh [--entry default\|safe-graphics]` | ISO boots under UEFI QEMU; the serial console logs in as `liveuser` and records `ip a`, `nmcli`, the graphical session, the running `calamares` process and the Hyprland config log; the framebuffer is read back with tesseract to prove the installer window opened by itself | `tests/evidence/<date>/serial-<entry>.log`, `session-<entry>.txt`, `installer-<entry>.png` (plus `menu-<entry>.png` for the safe-graphics run) |
| `scripts/test-install-auto.sh --install` | unattended install rehearsal on `build/test-disk.qcow2`: partition, Btrfs subvolumes, `unsquashfs`, every postinstall script, `grub-install` (not the Calamares GUI) | `tests/evidence/<date>/install-rehearsal.log`, `install-rehearsal.txt` |
| `scripts/test-install-auto.sh --boot-installed` | the installed disk boots without the ISO and an unprivileged user proves the live-only artefacts are gone | `tests/evidence/<date>/installed-boot.log`, `installed-boot.txt` |
| `scripts/test-install.sh --prepare` / `--boot-installed` | interactive Calamares walkthrough VM (human step) | VM is interactive |
| `iso/checks/check-repo-origins.sh` | every package comes from Arch or `mahadevanos-local` | build fails otherwise |
| `scripts/checksum.sh --verify-only` | ISO and manifest match their recorded sums | exit status |

`scripts/test-boot.sh` writes straight into `tests/evidence/<YYYY-MM-DD>/`; the
`NOTES` file there states what passed and what did not. Do not move a file there
without having actually run the test. `--entry safe-graphics` finds the systemd-boot
menu with a screendump + tesseract OCR, presses Up/Enter through the QEMU monitor and
then proves the choice from `/proc/cmdline` (`nomodeset`) inside the guest.

Disk work is restricted to `build/test-disk.qcow2`. No script here may touch
`/dev/sd*`, `/dev/nvme*`, `mkfs`, `wipefs`, partitioning tools or `dd` on a device.
