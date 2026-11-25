# Roll back to a snapshot

Rolling back means: the subvolume `@` (your live system) is replaced by a copy of
the snapshot, and the broken `@` is kept as `@.broken` until you delete it. Your
files in `/home` (`@home`), the logs (`@log`), the caches (`@cache`) and the
snapshots themselves (`@snapshots`) are not touched.

`snapper rollback` is the one-command version, but it expects `/` to *be* the
snapshot subvolume. A snapshot booted through the overlayfs hook (see
[boot-snapshot.md](boot-snapshot.md)) is not, so on this distro the reliable
procedure is the manual one below. It works from the booted snapshot **and** from
the live USB.

Read [README.md](README.md) first for the layout and the device names.

## 0. Know which snapshot you want

```bash
sudo snapper -c root list            # number, type, date, description
```

Enter the number as `<N>` below. Snapshot `<N>` lives at
`/.snapshots/<N>/snapshot` on the Btrfs top level, i.e.
`@snapshots/<N>/snapshot`.

## 1. Find the Btrfs partition

```bash
lsblk -f                             # the btrfs one, e.g. /dev/vda2
```

Everything below uses `/dev/vda2` for the Btrfs root and `/dev/vda1` for the ESP.
Substitute yours; never guess.

## 2. Mount the top level and swap the root subvolume

The top level (`subvolid=5`) is the only place where `@` can be renamed, so mount
it somewhere temporary:

```bash
sudo mkdir -p /mnt/top
sudo mount -o subvolid=5 /dev/vda2 /mnt/top
sudo btrfs subvolume list /mnt/top        # @, @home, @log, @cache, @snapshots, ...
```

Now replace the live root. The old one is *renamed*, not deleted:

```bash
sudo mv /mnt/top/@ /mnt/top/@.broken
sudo btrfs subvolume snapshot /mnt/top/@snapshots/<N>/snapshot /mnt/top/@
sudo btrfs subvolume list /mnt/top | grep -E '(@|@\.broken)$'
```

`@` is now the snapshot's content and writable; `@.broken` is the state you just
abandoned.

## 3. Chroot into the restored system and repair what is version-bound

The restored `/etc/fstab`, `/etc/default/grub` and kernel are the snapshot's, so
the initramfs has to be regenerated for the *restored* kernel, and GRUB's menu has
to be rebuilt from the restored `/boot`.

```bash
sudo mkdir -p /mnt/top/@mnt 2>/dev/null || true      # not needed; use a fresh mount point
sudo mkdir -p /target
sudo mount -o subvol=@ /dev/vda2 /target
sudo mount -o subvol=@home    /dev/vda2 /target/home
sudo mount -o subvol=@log     /dev/vda2 /target/var/log
sudo mount -o subvol=@cache   /dev/vda2 /target/var/cache
sudo mount -o subvol=@snapshots /dev/vda2 /target/.snapshots
sudo mount /dev/vda1 /target/boot/efi

sudo mount --rbind /dev  /target/dev
sudo mount --rbind /proc /target/proc
sudo mount --rbind /sys  /target/sys
sudo mount --rbind /run  /target/run

sudo chroot /target mkinitcpio -P
sudo chroot /target grub-mkconfig -o /boot/grub/grub.cfg
```

On the live USB `sudo arch-chroot /target` does the four bind mounts for you.

`mkinitcpio -P` also runs the `/boot` padding hook, and `grub-mkconfig` runs
`/etc/grub.d/41_snapshots-btrfs`, so the Snapshots submenu is regenerated from the
snapshots that still exist. Both kernels must end up in the menu:

```bash
sudo chroot /target grep -c 'vmlinuz-linux'     /boot/grub/grub.cfg
sudo chroot /target grep -c 'vmlinuz-linux-lts' /boot/grub/grub.cfg
```

## 4. Check and clean up

```bash
lsattr -d /target/boot                 # must still contain C
sudo chroot /target lsinitcpio /boot/initramfs-linux.img | grep grub-btrfs-overlayfs
```

Then unmount and reboot:

```bash
for d in run sys proc dev; do sudo umount -l /target/$d; done
sudo umount -R /target
sudo umount /mnt/top
sudo reboot
```

Once the system is confirmed good, reclaim the space:

```bash
sudo mount -o subvolid=5 /dev/vda2 /mnt/top
sudo btrfs subvolume delete /mnt/top/@.broken
sudo umount /mnt/top
```

## Undoing a rollback

`@.broken` is still there until you delete it, so the same procedure with
`@.broken` in place of the snapshot restores the broken system — useful if you
rolled back too far.

## If the rollback does not fix it

- Boot **linux-lts** from the main menu (a real kernel on the real filesystem,
  independent of the newest kernel package).
- Roll back further: another, older snapshot.
- Repair GRUB from the live USB: [repair-grub.md](repair-grub.md).
- A filesystem that will not mount at all deserves `sudo btrfs check --readonly
  /dev/vda2` **before** anything destructive. Never run `btrfs check --repair`
  without a backup.
