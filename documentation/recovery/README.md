# Recovery: snapshots, rollback and GRUB repair

Status: **TESTED** on an installed QEMU disk (2026-11-24). Evidence in
`tests/evidence/2026-11-24/`.

This directory is the technical guide. The beginner page ships on every
installed system as `/usr/share/doc/mahadevanos/recovery.md` (`mhelp recovery`).

| Page | Read it when |
|---|---|
| [boot-snapshot.md](boot-snapshot.md) | the system still boots but you want the state from before a change |
| [rollback.md](rollback.md) | a snapshot is good and you want it to *be* the system again |
| [repair-grub.md](repair-grub.md) | the machine reaches the firmware or `grub rescue>` instead of the menu |

## The layout these instructions assume

| What | Where | Note |
|---|---|---|
| ESP (FAT32, 1 GiB) | `/dev/nvme0n1p1` → `/boot/efi` | partition 1, `vfat`, `umask=0077` |
| Btrfs root | `/dev/nvme0n1p2` | partition 2, `compress=zstd:1,noatime` |
| `@` | `/` | the live system |
| `@home` | `/home` | |
| `@log` | `/var/log` | |
| `@cache` | `/var/cache` | |
| `@snapshots` | `/.snapshots` | snapper's snapshots: `/.snapshots/<N>/snapshot` |

Kernels and initramfs live **inside** `@` (`/boot/vmlinuz-linux`,
`/boot/initramfs-linux.img`, plus `linux-lts`), not on the ESP. That is the reason
GRUB was chosen over systemd-boot: a rollback of `@` also rolls back the kernel
and its modules, so a snapshot cannot boot a kernel whose modules are gone.

`/boot` is marked `chattr +C` (NOCOW, no compression) and every file in it is
padded to a multiple of 4096 bytes, because GRUB 2.16's btrfs driver skips a
file's final partial block (see `documentation/known-issues.md` #50 and #52).
Both properties are inside the snapshot, so they survive a rollback. After a
rollback, check them anyway:

```bash
lsattr -d /boot                       # must contain C
for f in /boot/vmlinuz-* /boot/initramfs-*.img; do
  echo "$(( $(stat -c %s "$f") % 4096 )) $f"    # every number must be 0
done
```

Device names are examples. Always confirm with `lsblk -f` before running anything
from these pages, and never guess a device name.

## What is installed, and what enforces it

| Piece | Package | What it does |
|---|---|---|
| `snapper` config `root` | `mahadevanos-settings` | snapshots of `/` into `@snapshots` |
| `snap-pac` | `snap-pac` | a pre and a post snapshot around every pacman transaction |
| `grub-btrfs` + `grub-btrfsd.service` | `grub-btrfs` | the **Snapshots** submenu in GRUB, rewritten whenever a snapshot appears or disappears |
| `grub-btrfs-overlayfs` mkinitcpio hook | `grub-btrfs` | boots a snapshot read-only but writable through a tmpfs overlay |
| `mahadevanos-snapshot-guard` (+ timer) | `mahadevanos-settings` | marks the newest snapshot `important=yes` so cleanup can never delete the last known-good one |
| `btrfs-assistant` | `btrfs-assistant` | graphical snapshot management (`Super + D` → "btrfs") |

GRUB shows `linux` first (entry 0), `linux-lts` next (entry 3: entry 0 is the
default kernel, 1 its fallback initramfs, 2 its recovery entry), and the
**Snapshots** submenu after the kernel entries. The menu waits 5 seconds
(`GRUB_TIMEOUT=5`, `GRUB_TIMEOUT_STYLE=menu`) and stays visible.

### Retention

`/etc/snapper/configs/root` bounds the snapshots three ways, so the disk cannot
fill up:

- 10 number snapshots and 5 important ones (`NUMBER_LIMIT`,
  `NUMBER_LIMIT_IMPORTANT`), 5 hourly / 7 daily / 2 weekly / 1 monthly timeline
  snapshots;
- `NUMBER_MIN_AGE`/`TIMELINE_MIN_AGE` of 30 minutes, so a snapshot taken during
  the update you are recovering from is not deleted while you need it;
- `SPACE_LIMIT=0.5` and `FREE_LIMIT=0.2`: cleanup starts deleting older snapshots
  when snapshots exceed half the filesystem or free space falls below 20 %.

The last known-good snapshot is exempt: `mahadevanos-snapshot-guard.timer` (boot
+ hourly, i.e. before snapper's own hourly cleanup) marks the newest snapshot
`important=yes` with cleanup algorithm `number`, and releases the previous anchor.
Important snapshots are never removed by the number algorithm, and the timeline
algorithm only looks at timeline snapshots, so that anchor survives both.

## Rebuilding the snapshot menu

```bash
sudo systemctl restart grub-btrfsd.service
sudo /etc/grub.d/41_snapshots-btrfs      # rewrites /boot/grub/grub-btrfs.cfg
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

The daemon does the first two by itself; the third is only needed if
`/boot/grub/grub.cfg` is missing the submenu (it was generated before the first
snapshot existed).
