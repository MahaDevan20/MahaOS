# Post-install profiles

Optional software, installed **after** the base system works. Each script prints
what it will install, asks for confirmation, takes a snapper snapshot, then
installs with `pacman`. Nothing here is part of the ISO.

```bash
sudo ./profiles/gaming.sh
sudo ./profiles/dev.sh
sudo ./profiles/virtualization.sh
sudo ./profiles/ai.sh
sudo ./profiles/zen-kernel.sh
```

| Profile | Installs | Notes |
|---|---|---|
| `gaming.sh` | steam, lutris, gamemode, mangohud, wine, gamescope | needs `[multilib]` (enabled by the installer) |
| `dev.sh` | docker, podman, compilers, python/node/rust/go/jdk, CLIs | adds your user to the `docker` group |
| `virtualization.sh` | qemu-full, libvirt, virt-manager, ovmf, swtpm | adds your user to `libvirt` |
| `ai.sh` | ollama runtime | no model weights are bundled; pulls are explicit |
| `zen-kernel.sh` | linux-zen | `linux` stays default, `linux-lts` stays the fallback |

Status: `IMPLEMENTED (untested)` — these have not been run against an installed
MahaDevan's OS yet. Package names come from the Arch repos and can drift.

`sudo` is used only because `pacman` and `systemctl` need it. The snapshot is
taken before any package is downloaded, so a profile that breaks the system can be
undone from the GRUB Snapshots menu.
