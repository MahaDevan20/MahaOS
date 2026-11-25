# Repair GRUB from the live USB

Use this when the machine does not reach the GRUB menu: it stops at the firmware,
says `no bootable device`, or drops to `grub rescue>`. The installed system is
usually intact; only the bootloader, its configuration or the NVRAM entry is not.

All commands run as root on the **live USB** (the same ISO the installer came
from). Confirm the devices with `lsblk -f`; the examples use `/dev/vda2` for the
Btrfs root and `/dev/vda1` for the ESP.

## 1. Mount the installed system

The live ISO's `@` is a squashfs, so mount the *disk's* subvolumes into a
different directory, `/target`:

```bash
sudo mkdir -p /target
sudo mount -o subvol=@,compress=zstd:1 /dev/vda2 /target
sudo mount -o subvol=@home    /dev/vda2 /target/home
sudo mount -o subvol=@log     /dev/vda2 /target/var/log
sudo mount -o subvol=@cache   /dev/vda2 /target/var/cache
sudo mount -o subvol=@snapshots /dev/vda2 /target/.snapshots
sudo mount /dev/vda1 /target/boot/efi

sudo mount --rbind /dev  /target/dev
sudo mount --rbind /proc /target/proc
sudo mount --rbind /sys  /target/sys
sudo mount --rbind /run  /target/run
sudo cp /etc/resolv.conf /target/etc/resolv.conf      # only needed to pacman
```

`findmnt -R /target` must show all six mounts (and `efivarfs` under
`/target/sys/firmware/efi/efivars` on a UEFI machine). If `/target/boot/vmlinuz-linux`
is missing, the wrong subvolume was mounted.

## 2. Reinstall the bootloader

```bash
sudo arch-chroot /target grub-install --target=x86_64-efi \
     --efi-directory=/boot/efi --bootloader-id=mahadevanos
```

This writes `/boot/efi/EFI/mahadevanos/grubx64.efi` **and** an NVRAM entry. For
the removable path the installer also uses (it boots even if the firmware forgets
the entry, e.g. after a CMOS reset):

```bash
sudo arch-chroot /target grub-install --target=x86_64-efi \
     --efi-directory=/boot/efi --removable
```

## 3. Rebuild the menu (and the Snapshots submenu)

```bash
sudo arch-chroot /target grub-mkconfig -o /boot/grub/grub.cfg
sudo arch-chroot /target mkinitcpio -P
```

`grub-mkconfig` reads `/etc/default/grub`, so `linux` stays entry 0, `linux-lts`
entry 3 and the **Snapshots** submenu last; `41_snapshots-btrfs` rewrites
`/boot/grub/grub-btrfs.cfg` from the snapshots that exist.

```bash
sudo arch-chroot /target grep -E "menuentry|submenu" /boot/grub/grub.cfg | head -20
sudo arch-chroot /target grep -c 'subvol=/@snapshots' /boot/grub/grub-btrfs.cfg
```

## 4. Unmount and reboot

```bash
for d in run sys proc dev; do sudo umount -l /target/$d; done
sudo umount -R /target
sudo reboot
```

## If `grub-install` is not enough

- **No kernel in `/boot`** (the install was interrupted): reinstall them from the
  chroot, `pacman -S linux linux-lts`, then repeat step 3.
- **`error: unknown filesystem` / `grub rescue>`** means GRUB started but cannot
  read `/`: boot the live USB, mount `subvolid=5` and check that `@` exists
  (`sudo mount -o subvolid=5 /dev/vda2 /mnt/top && ls /mnt/top`). If it does not,
  roll back with [rollback.md](rollback.md).
- **Partial upgrade broke the system** (the classic "after a failed pacman -Syu"):
  from the chroot, `pacman -Syu --overwrite '*'`, then step 3. Take a snapshot
  first: `sudo snapper -c root create --description "before rescue upgrade"`.
- **Firmware boots another loader first**: `efibootmgr -v` lists the order; the
  NVRAM entry for `mahadevanos` must exist and be first. Re-running step 2 restores
  it.
