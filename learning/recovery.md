# Snapshots and going back in time

MahaDevan's OS keeps copies of your system, so a bad update is not a disaster.
This page is the short, beginner version; the full technical guide is in
`documentation/recovery/` and is also installed on your computer under
`/usr/share/doc/mahadevanos/`.

## What a snapshot is (and is not)

A **snapshot** is a saved state of the whole system (not your home folder files'
*history* — for those, copy the file first). It is almost free in disk space:
only blocks that change afterwards are stored twice. Before and after every
package install or update, one is taken automatically.

Two important facts:

- A snapshot is **read-only**. When you boot one, the system behaves like a live
  USB: you can look around and fix things, but every change disappears on reboot.
- Snapshots live in their own subvolume (`@snapshots`), so rolling the system
  back does **not** throw away the snapshots themselves.

## See the snapshots you have

```bash
sudo snapper -c root list            # all snapshots, newest last
sudo snapper -c root list --all      # include ones cleanup will remove soon
```

The `pre`/`post` pairs are the before/after of one `pacman` transaction. The
description says which command caused it.

## Boot a snapshot

1. Restart the computer.
2. At the GRUB menu (it waits 5 seconds and is always visible), choose
   **Snapshots**. Press `Enter` on it, then pick the newest entry that is *older*
   than the problem.
3. The system boots read-only. Everything looks normal, and nothing you do there
   is saved.

If the menu does not appear, hold `Shift` (BIOS) or tap `Esc` (UEFI) while the
firmware logo is on screen.

## Roll back (keep the snapshot's state as your system)

From the booted snapshot, open a terminal and run:

```bash
sudo mhelp recovery        # this page, offline
```

then follow `documentation/recovery/rollback.md`. In short: mount the Btrfs
top level, move the broken `@` aside, make a new `@` from the snapshot, and
rebuild the initramfs and the GRUB menu. The old `@` is kept until you delete it,
so the rollback itself can be undone.

## The graphical way

**Btrfs Assistant** (`Super + D`, type "btrfs") lists snapshots, takes one on
demand, deletes old ones and has a *Snapper* and a *Btrfs Maintenance* tab. It
runs as root through a polkit prompt, so it asks for your password.

## GRUB is broken: repair from the live USB

If the machine powers on to the firmware or to a `grub rescue>` prompt, boot the
MahaDevan's OS USB and run the steps in `documentation/recovery/repair-grub.md`.
The installer is not needed; the same subvolume names (`@`, `@home`, `@log`,
`@cache`, `@snapshots`) are used there.

## Space

Snapshots cannot fill your disk: the retention policy keeps a small number of
them and also deletes the oldest when the filesystem gets tight. The newest
known-good snapshot is marked *important* and is never deleted automatically.

```bash
sudo btrfs filesystem usage /     # how full the disk really is
sudo snapper -c root list         # what takes the space
```
