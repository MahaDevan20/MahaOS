# Learning files, mhelp and shortcuts

MahaDevan's OS ships help that works with the network cable unplugged. Nothing
here is copied into the image by hand: every file comes from a package built into
`repo/`, so `pacman -Qo` always answers where a file came from.

| Package | Contents |
|---|---|
| `mahadevanos-learning` | the three guides, `mhelp`, the terminal hint, `/etc/skel/practice`, the cheat-sheet launchers; depends on `less`, `man-db`, `man-pages` |
| `mahadevanos-bootpad` | `/usr/bin/mahadevanos-padboot` plus the pacman hook and mkinitcpio post hook that keep `/boot` readable by GRUB |
| `mahadevanos-settings` | the compositor configuration the shortcut sheet is generated from |

## The three guides

All in `/usr/share/doc/mahadevanos/`, readable with `mhelp` or `less`:

- **`commands.md`** — one line of explanation and one example per command, in
  sections: navigating (`pwd`, `ls`, `cd`), files and folders (`touch`, `mkdir`,
  `cp`, `mv`, `rm`, `rmdir`, `cat`, `less`, `nano`), finding things (`find`,
  `grep`, `locate`, `which`), permissions (`chmod`, `chown`, `sudo`), packages
  (`pacman`, `flatpak`), system and disks (`df`, `du`, `lsblk`, `free`, `htop`,
  `journalctl`), networking (`ip`, `ping`, `nmcli`, `nmtui`, `resolvectl`),
  snapshots (`snapper`, `btrfs`), and a safety section about `rm -rf`, `dd`,
  `curl | bash` and running commands you do not understand.
- **`shortcuts.md`** — every binding, generated (see below), with a note that
  **Super is the Windows key**, plus the live-session key, the TTY escape hatch
  (`Ctrl + Alt + F2`), the mouse gestures and kitty's own shortcuts.
- **`network.md`** — step by step: Ethernet (usually automatic), the panel applet,
  `nmcli device wifi list` / `nmcli device wifi connect "NAME" password "PASS"`,
  `nmtui` as the menu option, checking the connection, hidden networks, static IPs,
  and troubleshooting (`rfkill unblock`, restarting NetworkManager, DNS with
  `ping`/`resolvectl`). Every tool it names is installed by `iso/packages/`:
  NetworkManager (`nmcli`, `nmtui`), `network-manager-applet`, `wpa_supplicant`,
  `iproute2` (`ip`), `iputils` (`ping`) and systemd (`resolvectl`).

## mhelp

```
mhelp                 index of the three pages
mhelp commands        the command guide (paged with less when on a terminal)
mhelp keys            the shortcut sheet
mhelp network         the network guide
mhelp <word>          case-insensitive search of all three pages
```

`mhelp` reads `$MAHADEVANOS_DOCS` (default `/usr/share/doc/mahadevanos`), which
is what the offline test uses to run it against the repository copies. A word that
matches nothing exits nonzero, so scripts can rely on it.

## The terminal hint

`/etc/profile.d/10-mahadevanos-hint.sh` prints

```
Type mhelp for commands, shortcuts and network help.
```

once, and only in an interactive shell: it exports `MAHADEVANOS_HINT_SHOWN`, so a
shell started from an already hinted shell stays quiet. It is in the live ISO too
(the package is in `iso/packages/desktop.txt`).

`/etc/profile.d` is only read by **login** shells, and kitty starts a plain
interactive `bash` by default (measured on 2026-11-23: `ps -o args= -C bash`
showed `/bin/bash --posix`, and no hint appeared). `configs/kitty/kitty.conf`
therefore sets `shell /bin/bash --login`; the GUI test asserts the hint line is on
screen after `Super + Q`.

## The practice folder

`/etc/skel/practice/` holds `README.md`, `notes.txt`, `todo.txt`, `contacts.csv`,
`folders/` and `empty-folder/`. `useradd -m` (what the Calamares *users* module
runs) copies it into every new account, and `customize_airootfs.sh` copies the same
folder into `/home/liveuser` — only that folder, because liveuser's own
`hyprland.lua` must stay the live variant that starts the installer.

## The cheat sheet on the desktop

`/usr/share/applications/mahadevanos-shortcuts.desktop` opens
`/usr/bin/mahadevanos-cheatsheet` (kitty + less on `shortcuts.md`), and
`mahadevanos-help.desktop` opens `mhelp`. Both appear in wofi (`Super + D`) in the
live session and on the installed system. No notification daemon is required, so
nothing can fail to start on a session without one.

## Shortcuts are generated, not written

`scripts/gen-shortcuts.sh` parses `configs/hypr/hyprland.lua`:

- `hl.bind(mod .. " + Q", ...)` → `SUPER + Q`
- `hl.bind(mod .. " + SHIFT + R", ...)` → `SUPER + SHIFT + R`
- `hl.bind("XF86AudioMute", ...)` → `XF86AudioMute`
- the `for` loop over workspaces is documented once as `SUPER + <loop>`

Every key must have a line in `configs/hypr/shortcuts.tsv` and every line there
must match a key in the config, or the generator exits nonzero. The static extras
(live-only keys, TTY escape hatches, mouse gestures, kitty shortcuts) come from
`configs/hypr/shortcuts-extra.md`.

Where it runs:

| Where | Why |
|---|---|
| `scripts/build-repo.sh` | regenerate before packaging, so the shipped file is always current |
| `scripts/gen-shortcuts.sh --check` | used by `tests/docs/check-learning.sh` on the host, no VM needed |
| `tests/docs/check-learning.sh` | also proves `mhelp` works, the hint prints once, the guides only teach installed tools, and `mahadevanos-padboot` aligns a file |

## Issue 27: Hyprland's "autogenerated config" banner

Hyprland 0.57 reads `hyprland.lua`; a `hyprland.conf` is ignored silently and the
compositor then draws its "You're using an autogenerated config" banner and uses
the stock binds (no `Super + Q`). The shipped config is `configs/hypr/hyprland.lua`,
installed as `/etc/xdg/hypr/hyprland.lua` **and** `/etc/skel/.config/hypr/hyprland.lua`,
and the live account gets `/home/liveuser/.config/hypr/hyprland.lua`, which
`dofile`s the shared file and starts the installer.

Verified in the GUI install test, which does not trust the files:

- `Super + Q` is sent to the running live session; kitty must open and show the
  `mhelp` hint (so the shipped binds are live, not the defaults);
- `mhelp keys` is typed into that kitty window and must print the sheet;
- after the install, `tests/install/gui-install-audit.sh` greps the live session's
  Hyprland log for an `autogenerated` warning and requires it to be absent.

If Hyprland ever stops starting, a TTY is always reachable (`Ctrl + Alt + F2`), and
the **labwc** session in SDDM's menu is a plain fallback window manager.
