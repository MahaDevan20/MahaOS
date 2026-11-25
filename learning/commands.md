# MahaDevan's OS — Linux commands for beginners

One line of explanation and one example for every command. Run them in a
terminal: open **kitty** with `Super + Q`. Nothing here needs the internet.

A few conventions:

- `$` means "type the rest in a terminal". Do not type the `$`.
- `~/` is your home folder (`/home/yourname`), `~` on its own means the same.
- `sudo` asks for **your** password (it does not type it for you) and gives that
  one command administrator rights.
- The command name is followed by its options, then by what it works on:
  `cp notes.txt backup/` copies the file `notes.txt` into `backup/`.
- `mhelp commands | less` shows this page; press `q` to leave the pager.

---

## Navigating: where am I, what is here

| Command | What it does | Example |
|---|---|---|
| `pwd` | Print the folder you are in right now. | `pwd` |
| `ls` | List the files and folders in the current folder. | `ls` |
| `ls -l` | List with size, date and permissions. | `ls -l ~/practice` |
| `cd` | Change to another folder. | `cd ~/practice` |
| `cd ..` | Go up one folder. | `cd ..` |
| `cd ~` | Go to your home folder. | `cd ~` |

## Files and folders

| Command | What it does | Example |
|---|---|---|
| `touch` | Create an empty file (or update a file's time). | `touch todo.txt` |
| `mkdir` | Make a new folder. | `mkdir backup` |
| `mkdir -p` | Make a folder and any missing parents in one go. | `mkdir -p ~/practice/notes/2026` |
| `cp` | Copy a file or folder (add `-r` for a folder). | `cp notes.txt backup/` |
| `mv` | Move a file or folder; also renames it. | `mv notes.txt notes-old.txt` |
| `rm` | Delete a file. It does **not** go to a trash can. | `rm old-file.txt` |
| `rmdir` | Delete an **empty** folder. | `rmdir backup` |
| `cat` | Print a whole file to the screen. | `cat notes.txt` |
| `less` | Read a long file page by page (`Space` next page, `q` quit). | `less /usr/share/doc/mahadevanos/commands.md` |
| `nano` | Simple text editor: type, `Ctrl + O` saves, `Ctrl + X` quits. | `nano todo.txt` |

## Finding things

| Command | What it does | Example |
|---|---|---|
| `find` | Search for files by name inside a folder tree. | `find ~ -name '*.txt'` |
| `grep` | Print the lines of a file that contain a word. | `grep -i milk shopping.txt` |
| `grep -r` | Same, searching every file in a folder. | `grep -r "btrfs" /etc` |
| `locate` | Instant search of a database of all file names (run `sudo updatedb` first). | `locate kitty.conf` |
| `which` | Show which program a command name would run. | `which python3` |

## Permissions and administrators

| Command | What it does | Example |
|---|---|---|
| `ls -l` | The `rwx` columns are permissions: read, write, execute. | `ls -l script.sh` |
| `chmod` | Change who may read, write or run a file (`+x` = runnable). | `chmod +x script.sh` |
| `chown` | Change who owns a file (needs `sudo` for other people's files). | `sudo chown $USER ~/notes.txt` |
| `sudo` | Run one command as the administrator. | `sudo pacman -Syu` |
| `whoami` | Print your user name. | `whoami` |

## Packages

| Command | What it does | Example |
|---|---|---|
| `pacman -Syu` | Update the whole system (do this every week or two). | `sudo pacman -Syu` |
| `pacman -S` | Install a package. | `sudo pacman -S htop` |
| `pacman -Rns` | Remove a package and its unneeded dependencies. | `sudo pacman -Rns htop` |
| `pacman -Ss` | Search the repositories by name or description. | `pacman -Ss screenshot` |
| `pacman -Qs` | Search what is already installed. | `pacman -Qs kitty` |
| `pacman -Ql` | List the files a package installed. | `pacman -Ql kitty` |
| `flatpak install` | Install an app from Flathub (sandboxed, updates separately). | `flatpak install flathub org.gimp.GIMP` |
| `flatpak list` | Show the Flatpak apps you have. | `flatpak list` |
| `flatpak update` | Update Flatpak apps only. | `flatpak update` |

## System, memory and disks

| Command | What it does | Example |
|---|---|---|
| `df -h` | Free space on every mounted filesystem, in human units. | `df -h` |
| `du -sh` | Total size of one folder. | `du -sh ~/practice` |
| `lsblk` | List the disks, partitions and their mount points. | `lsblk -f` |
| `free -h` | Used and free memory (RAM and swap). | `free -h` |
| `htop` | Live view of processes, CPU and memory (`F10` or `q` quits). | `htop` |
| `btop` | Prettier version of the same idea. | `btop` |
| `uptime` | How long the machine has been running and its load. | `uptime` |
| `uname -r` | Which kernel you are running. | `uname -r` |
| `journalctl -b` | The system log of this boot (`/` searches, `q` quits). | `journalctl -b -p err` |

## Networking

| Command | What it does | Example |
|---|---|---|
| `ip a` | Show every network interface and its address. | `ip a` |
| `ip r` | Show the routing table (where traffic goes). | `ip r` |
| `ping -c 3` | Send three test packets: is that host reachable? | `ping -c 3 archlinux.org` |
| `nmcli` | Command-line control of NetworkManager (Wi-Fi, Ethernet, VPN). | `nmcli device wifi list` |
| `nmtui` | The same thing as a menu you can walk with the arrow keys. | `nmtui` |
| `resolvectl status` | Which DNS servers are in use (when systemd-resolved runs). | `resolvectl status` |

The step-by-step version of all of this is `mhelp network`.

## Snapshots (Btrfs)

| Command | What it does | Example |
|---|---|---|
| `snapper list` | List the snapshots of the root filesystem. | `sudo snapper -c root list` |
| `snapper create` | Take a snapshot right now, before a risky change. | `sudo snapper -c root create --description 'before upgrade'` |
| `snapper undochange` | Revert the files that differ between two snapshots. | `sudo snapper -c root undochange 12..13` |
| `snapper delete` | Delete a snapshot by number. | `sudo snapper -c root delete 12` |
| `snapper status` | Which files differ between two snapshots. | `sudo snapper -c root status 12..13` |
| `snapper diff` | The actual changes in those files. | `sudo snapper -c root diff 12..13` |
| `snapper rollback` | Make a snapshot the system again (run it *from* the booted snapshot). | `sudo snapper -c root rollback 14` |
| `btrfs subvolume list` | Show the subvolumes and snapshots on the disk. | `sudo btrfs subvolume list /` |
| `btrfs filesystem usage` | How full the Btrfs filesystem really is. | `sudo btrfs filesystem usage /` |
| `mhelp recovery` | The beginner page for exactly this: boot a snapshot, roll back. | `mhelp recovery` |

Snapshots are taken automatically before and after every `pacman` transaction
(the `snap-pac` package), so there is usually one to go back to. A snapshot is
bootable from the **Snapshots** submenu of the GRUB menu. The graphical way is
**Btrfs Assistant** in the launcher (`Super + D`). `mhelp recovery` has the
step-by-step version.

## Safety: read this before typing

- **`rm -rf` deletes forever.** `rm -rf /` or `rm -rf ~` destroys the system or
  your home folder with no confirmation and no trash can. Never copy such a
  command from a website. If a guide tells you to run `rm -rf` with a variable
  in it, run `echo` on it first and read what it would delete.
- **`dd` writes raw bytes to a device.** One wrong letter in `dd if=... of=/dev/sdX`
  and it overwrites a disk. `lsblk` first, every time; target a file, not a
  device, unless you are certain. The installer exists so you never need it.
- **Never run a command you do not understand.** Ask what it does, or look it up
  with `man <command>` (`man` pages are installed). "Just paste this" is how
  machines get broken and accounts get stolen.
- **`sudo` is not a habit.** Use it for the one command that needs it. A command
  from the internet that needs `sudo` deserves twice the suspicion.
- **Take a snapshot before experimenting**: `sudo snapper -c root create
  --description 'before experimenting'`.
- **Do not pipe the internet into a shell.** `curl ... | bash` runs whatever the
  server sends today; download, read, then run.
