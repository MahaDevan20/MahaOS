# Recovery: snapshots, rollback and GRUB repair

## What exists

- `snapper` config `root` on `/` (subvolume `@`), snapshots stored in `@snapshots`
  mounted at `/.snapshots`.
- `snap-pac` creates a pre and post snapshot around every `pacman` transaction.
- `grub-btrfsd` rewrites the GRUB menu so snapshots appear in a **Snapshots**
  submenu, bootable read-only through overlayfs.
- `linux-lts` is installed as a fallback kernel, always present in the menu.

## Boot a snapshot

1. Power on, hold `Esc`/`Shift` if the menu is hidden (timeout is 5 s).
2. **Snapshots** → pick the newest entry before the change that broke the system.
3. The snapshot boots **read-only**. Verify it is the state you want.

## Roll back from a booted snapshot

Identify the snapshot number (`sudo snapper list`), then:

```bash
# Mount the top-level Btrfs (NOT a subvolume) to reach @ and @snapshots
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt

# Rename the broken root out of the way (keep it until you are sure)
sudo mv /mnt/@ /mnt/@.broken
sudo btrfs subvolume snapshot /mnt/@snapshots/<N>/snapshot /mnt/@

# Rebuild the initramfs for the restored tree
sudo mount -o subvol=@,compress=zstd:1 /dev/nvme0n1p2 /mnt
for d in boot/efi home var/log var/cache .snapshots; do :; done
sudo mount -o subvol=@home /dev/nvme0n1p2 /mnt/home
sudo mount -o subvol=@log  /dev/nvme0n1p2 /mnt/var/log
sudo mount -o subvol=@cache /dev/nvme0n1p2 /mnt/var/cache
sudo mount -o subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots
sudo mount /dev/nvme0n1p1 /mnt/boot/efi

sudo arch-chroot /mnt mkinitcpio -P
sudo arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
```

Swap the device name for yours — check with `lsblk -f` first. Never guess a device.

If the rollback is good: `sudo btrfs subvolume delete /mnt/@.broken` (once unmounted).

## Repair GRUB from the live USB

When the machine boots straight to firmware or `grub rescue`:

```bash
lsblk -f                      # find the Btrfs partition, e.g. /dev/nvme0n1p2
sudo mount -o subvol=@,compress=zstd:1 /dev/nvme0n1p2 /mnt
sudo mount -o subvol=@home /dev/nvme0n1p2 /mnt/home
sudo mount -o subvol=@log  /dev/nvme0n1p2 /mnt/var/log
sudo mount -o subvol=@cache /dev/nvme0n1p2 /mnt/var/cache
sudo mount -o subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots
sudo mount /dev/nvme0n1p1 /mnt/boot/efi      # the ESP, FAT32

sudo arch-chroot /mnt grub-install --target=x86_64-efi \
     --efi-directory=/boot/efi --bootloader-id=mahadevanos
sudo arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
sudo arch-chroot /mnt mkinitcpio -P
```

`grub-install` writes to the ESP of the disk you mounted — verify it before running.

## Regenerate the snapshot menu only

```bash
sudo systemctl restart grub-btrfsd.service
sudo /etc/grub.d/41_snapshots-btrfs    # rewrite the cache
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

## Emergency: no snapshots, no LTS kernel

Boot the live ISO, `arch-chroot` into the system as above, then:

```bash
pacman -Syu --overwrite '*'      # only if a partial upgrade broke the system
pacman -S linux linux-lts        # reinstall kernels
mkinitcpio -P && grub-mkconfig -o /boot/grub/grub.cfg
```

If `/` will not mount at all, `btrfs check --readonly` the partition before doing
anything destructive. Never run `btrfs check --repair` without a backup.
