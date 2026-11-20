# Architecture

## Boot and install flow

```
UEFI firmware
  └─ ISO (systemd-boot, live only)
       ├─ mahadevanos-linux        default, stock kernel
       ├─ mahadevanos-linux-lts    fallback kernel
       └─ mahadevanos-safe-graphics nomodeset for broken GPU/VM graphics
            └─ SDDM autologin → liveuser → Hyprland (fallback session: labwc)
                 └─ "Install MahaDevan's OS" → Calamares
                      └─ partition → mount → unpackfs (airootfs.sfs → /) → …
                           └─ post-install chroot scripts
                                └─ reboot → GRUB (installed) → SDDM → user
```

The **live** system uses systemd-boot because that is archiso's default. The
**installed** system uses GRUB, because GRUB can read Btrfs, lists snapshots via
grub-btrfs, and keeps kernels inside the root subvolume so a rollback rolls back
the kernel *and* its modules (blueprint §2 #2).

## Disk layout

| Partition | FS | Mount | Size |
|---|---|---|---|
| 1 | FAT32 (ESP) | `/boot/efi` | 1 GiB |

Btrfs on the rest, one partition, subvolumes:

| Subvolume | Mount | Options |
|---|---|---|
| `@` | `/` | `compress=zstd:1,noatime` |
| `@home` | `/home` | same |
| `@log` | `/var/log` | same |
| `@cache` | `/var/cache` | same |
| `@snapshots` | `/.snapshots` | same |

`/boot` is **not** a separate partition: kernels live in `@` so they roll back with
the rest of the system. This is the reason the ESP is 1 GiB — a separate `/boot`
would be needed only for encryption, and v1 encryption is LUKS1 (GRUB can unlock
LUKS1, not LUKS2 with argon2id).

## Installer

Calamares with `unpackfs`: it extracts
`/run/archiso/bootmnt/arch/x86_64/airootfs.sfs` to the target. There is no
`pacstrap`, no package download and no compilation. Consequently:

- Everything the installed system needs must be in the ISO.
- `calamares`/`ckbcomp` come from `repo/` inside the ISO.
- The post-install chroot scripts undo everything that is only valid live:
  archiso mkinitcpio hooks, the live user, passwordless sudo, autologin.

## Component choices

| Area | Choice | Why |
|---|---|---|
| Live builder | archiso (`mkarchiso`) | mature, Arch-native |
| Bootloader (installed) | GRUB + grub-btrfs | Btrfs + snapshots + os-prober |
| Filesystem | Btrfs, zstd:1, noatime | cheap snapshots, good compression |
| Snapshots | snapper + snap-pac | snapshot per pacman transaction |
| Display manager | SDDM | Wayland-capable, simple |
| Compositor | Hyprland | requested; labwc is the fallback |
| Audio | PipeWire + WirePlumber | current Arch default |
| Network | NetworkManager | tray, Wi-Fi, VPN |
| Firewall | ufw, deny incoming | simple, on by default |
| Packages | Arch official + Flatpak | AUR only via a warned helper |
| Secure Boot | none in v1 | signing is post-beta |

## What is intentionally missing

Custom settings app, store, system monitor, own desktop shell, own package repo,
AI assistant, website, BIOS support, install-alongside auto-resize. See blueprint
M7+. Deferring these is what makes an installable ISO achievable.
