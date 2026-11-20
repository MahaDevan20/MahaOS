# Boot and install tests

Automated where an agent reasonably can; the Calamares GUI walkthrough is a human
step (`documentation/installation/manual-test.md`).

| Script | What it proves | Evidence |
|---|---|---|
| `scripts/test-boot.sh` | ISO boots under UEFI QEMU; serial log reaches a session/login; framebuffer renders | `out/test-boot.log`, `out/test-boot.png` |
| `scripts/test-install.sh --prepare` | ISO boots with a blank qcow2 attached, installer reachable | VM is interactive |
| `scripts/test-install.sh --boot-installed` | installed disk boots without the ISO (GRUB → login) | `out/test-install.log` |
| `iso/checks/check-repo-origins.sh` | every package comes from Arch or `mahadevanos-local` | build fails otherwise |
| `scripts/checksum.sh --verify-only` | ISO and manifest match their recorded sums | exit status |

Evidence convention: copy artefacts into `tests/evidence/<YYYY-MM-DD>/` after a run,
with a one-line `NOTES` file stating what passed and what did not. Do not move a
file there without having actually run the test.

Disk work is restricted to `build/test-disk.qcow2`. No script here may touch
`/dev/sd*`, `/dev/nvme*`, `mkfs`, `wipefs`, partitioning tools or `dd` on a device.
