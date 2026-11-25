# Boot a snapshot

Use this when the system still powers on but a change broke something: a driver
update, a package that removed a file you need, a configuration you cannot undo.

## 1. Reach the GRUB menu

Restart. The menu is visible for 5 seconds (`GRUB_TIMEOUT=5`,
`GRUB_TIMEOUT_STYLE=menu`). If you missed it, `Esc` on the way out of the firmware
or hold `Shift` on a BIOS machine brings it back.

## 2. Open the Snapshots submenu

The menu looks like this:

```
MahaDevan OS
  * MahaDevan OS (linux)                    <- entry 0, default
    MahaDevan OS (linux, fallback initramfs)
    MahaDevan OS (linux, recovery mode)
    MahaDevan OS (linux-lts)                <- the fallback kernel
    ...
    Snapshots                               <- grub-btrfs, after the kernels
```

Move to **Snapshots** and press `Enter`. Each entry is one snapper snapshot,
newest first, titled with its date, number, type (`pre`/`post`/`single`) and the
description of the transaction that created it. A `post` entry is the state
*after* that transaction succeeded; the matching `pre` entry is the state before
it started, which is what you want when the transaction itself broke the system.

Entries are read from `/boot/grub/grub-btrfs.cfg` at boot; the file is written by
`grub-btrfsd` and can be regenerated at any time (see `README.md`).

## 3. What a snapshot boot is

The snapshot is a **read-only** Btrfs subvolume. The `grub-btrfs-overlayfs`
mkinitcpio hook puts a tmpfs overlay on top of it, so:

- the system boots normally and everything can write to `/`;
- every write lands in RAM and disappears on reboot (like the live USB);
- the snapshot itself is never modified, so it stays a valid rollback target.

Confirm you are in one:

```bash
cat /proc/cmdline | tr ' ' '\n' | grep subvol   # rootflags=subvol=/@snapshots/<N>/snapshot
findmnt -no FSTYPE,SOURCE /                     # overlay, overlay
```

`/` being `overlay` is the proof. A snapshot that boots with `/` on btrfs is
writable, which means the initramfs lost the hook:

```bash
lsinitcpio /boot/initramfs-linux.img | grep grub-btrfs-overlayfs
```

If that is empty, regenerate the initramfs from a working system
(`sudo mkinitcpio -P`) and rebuild the menu; snapshots taken before the fix
carry the old initramfs and cannot use the overlay.

## 4. From here

- Look around as long as you like; nothing is saved.
- Copy files out if you need them (`/home` comes from `@home`, the live one, so
  your documents are the current ones, not the snapshot's).
- If this state is what you want to keep, continue with
  [rollback.md](rollback.md).
- Otherwise reboot and pick another entry.

## Notes

- A snapshot with no `linux` kernel in `/boot` cannot boot. `snap-pac` snapshots
  always contain one, because the kernels live in `@`.
- The **linux-lts** entry in the main menu is the other escape hatch: it is a real
  kernel on the real filesystem, so it boots even when the newest kernel is the
  thing that broke.
