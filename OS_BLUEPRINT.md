# MahaDevan's OS — Master Blueprint v2 (ISO-first, Garuda-style install)

**Display name:** MahaDevan's OS
**Technical slug (use everywhere in code, paths, labels, package names):** `mahadevanos`
**Base:** Arch Linux, x86_64, UEFI-first
**Build host:** CachyOS (Arch-based), fish shell
**Audience:** the developer first; public release only after a long beta
**Purpose of this file:** the single specification and instruction set for an AI coding agent (Claude Code, Cursor, Codex, etc.)

---

## 0. PASTE THIS TO THE CODING AGENT FIRST

> You are the engineering agent for MahaDevan's OS. Read `OS_BLUEPRINT.md` (this file) fully before doing anything.
>
> **Your first deliverable is a bootable, installable ISO**, not a desktop mock-up and not a plan. Work through milestones M0 → M3 in order. Do not stop at planning: keep going until `out/mahadevanos-<date>-x86_64.iso` exists, boots in a UEFI QEMU VM, and the Calamares installer can install it onto a blank virtual disk that then boots on its own.
>
> Rules:
> 1. Reuse mature components (archiso, Calamares, GRUB, snapper, grub-btrfs, Hyprland, SDDM, NetworkManager, PipeWire). Do not write a kernel, compositor, package manager, installer, or file manager.
> 2. The installer must be **offline and Garuda-style**: it copies the live system image onto the disk. It must never download or compile anything during install, and the user must never have to install drivers or base packages by hand.
> 3. Nothing is "done" without evidence: a saved serial log or screenshot of the VM booting, command output, and the checksum. Never write "boots successfully" unless you actually booted it.
> 4. Work only inside the project directory. Never touch the host's real disks, partitions, bootloader, firewall, or network. Never run `mkfs`, `wipefs`, `parted`, `sgdisk`, `grub-install`, or `dd` against a real block device. All disk tests use files like `build/test-disk.qcow2` attached to QEMU.
> 5. The pre-approved command list in section 9 can be run without asking. Anything else privileged or destructive needs my explicit approval.
> 6. All scripts must be `#!/usr/bin/env bash` with `set -euo pipefail` (my interactive shell is fish; never write fish-only scripts).
> 7. If something fails, show the exact error, fix the root cause, and rerun. If a requirement is blocked, say so and propose the smallest safe alternative. Never fake it.
> 8. At the end of every work session, report: files changed, commands run, test evidence, what works, what doesn't, the next exact step.

---

## 1. What "simple install like Garuda" means (the core requirement)

The user boots the USB, sees a working desktop, clicks **Install**, answers a few questions, reboots, and has a finished system. Specifically:

| Requirement | How it is achieved |
|---|---|
| No manual driver or package installation | Everything needed is already inside the ISO's squashfs: full `linux-firmware`, `mesa`, `vulkan-radeon`, `vulkan-intel`, `amd-ucode`, `intel-ucode`, `sof-firmware`, NetworkManager, BlueZ, PipeWire, printing, fonts, codecs, etc. |
| Install works with no internet | Calamares `unpackfs` module copies the live squashfs to disk. No `pacstrap`, no downloads. |
| Graphical installer | Calamares (branded), launched from the live desktop |
| Sensible defaults | Btrfs with subvolumes, zstd compression, snapper snapshots, GRUB with a snapshot boot menu, firewall on, NetworkManager, SDDM, PipeWire |
| GPU "just works" | AMD/Intel/nouveau work out of the box. NVIDIA proprietary/open driver is detected during install and installed **from an offline repository on the ISO** (milestone M5). |
| Updates are safe | `snap-pac` takes a Btrfs snapshot before and after every pacman transaction; GRUB lists snapshots so a bad update is rolled back from the boot menu |
| Everyday extras are one click/command away | Post-install profile tool for gaming, development, virtualization, AI (M5). Not in the base ISO. |

---

## 2. Problems found in the original blueprint and what changed

| # | Original idea | Why it is a problem | Change in v2 |
|---|---|---|---|
| 1 | Installer (Calamares) in Phase 5, ISO in Phase 1, desktop in Phase 2 | You would not have an installable ISO for a very long time. Your core requirement is the install experience. | Installer is now **M2**, right after the first ISO. Snapshots are **M3**. Desktop polish comes after the thing is already installable. |
| 2 | systemd-boot + Btrfs snapshots + "bootable snapshot rollback" | systemd-boot cannot read Btrfs. Kernels must live on the FAT ESP, so rolling back `/` does not roll back the kernel, causing kernel/module mismatch. Snapshot boot menus are far less mature than with GRUB. | **GRUB + grub-btrfs + snapper + snap-pac** (what Garuda uses). Kernels live inside the Btrfs root so they roll back together with modules. systemd-boot stays only as the *live ISO's* loader (archiso default). |
| 3 | Custom Rust/GTK4 Settings, Store, and System Monitor apps in Phase 3 | Three full applications is months of work and blocks the ISO. Also pulls GTK4 + Qt + KDE into one image with inconsistent theming. | **Deferred to M7+.** v1 uses existing tools: KDE System Settings modules where useful or `nwg-displays`, `pavucontrol`/`wiremix`, `nm-connection-editor`, `btrfs-assistant`, `missioncenter`/`btop`, `pamac`-like or `octopi`/KDE Discover for packages. |
| 4 | Quickshell desktop shell written from scratch (panel, launcher, overview, notifications, quick settings, clipboard, lock, wallpaper manager) | This alone is a multi-month project and the biggest daily-driver risk. | **Adopt and fork an existing Quickshell-based Hyprland shell config** (for example Caelestia or end-4's dots, check licenses and maintenance activity), rebrand it, trim it, and pin it. Writing your own is a later milestone. |
| 5 | "Calamares" assumed to be a normal package | `calamares` is **not in the official Arch repos**; it is in the AUR (plus `ckbcomp` for keyboard layouts). | Build `calamares` and `ckbcomp` in a **clean chroot** (`devtools`) into a **local repository** used by the ISO build. Do not pull prebuilt binaries from third parties. |
| 6 | "Official MahaDevan's repository" in early phases, AUR in the Store | Needs hosting, signing, and maintenance before there is even an ISO. | v1 uses a **local repo directory** (`repo/x86_64/`) for the few AUR/custom packages. Public repo and signing move to the public-beta milestone. |
| 7 | "Reproducible builds" | Arch is rolling; bit-for-bit reproducibility is unrealistic. | Goal is **repeatable builds**: pin the package snapshot with the Arch Linux Archive date (`https://archive.archlinux.org/repos/YYYY/MM/DD/$repo/os/$arch`) in the build `pacman.conf`, record a package manifest and checksum. The **installed** system uses normal mirrors. |
| 8 | LUKS "optional during install" with GRUB | GRUB cannot unlock LUKS2 with argon2id (the cryptsetup default). | Optional encryption uses **LUKS1** via Calamares (`luksGeneration: luks1`) and is an **experimental M5 feature**, after unencrypted install is proven. |
| 9 | Dual boot "alongside Windows" as a required feature | Resizing NTFS from an installer is the riskiest operation in an installer (BitLocker, Fast Startup, hibernation). | Dual boot is supported by `os-prober` + manual/"replace partition" workflows. "Install alongside with auto-resize" is **experimental and off by default**. |
| 10 | Live session depends entirely on Hyprland | Hyprland needs working GPU/GLES. Many VMs and some hardware fail, and then the user cannot even install. | Live ISO includes a **fallback session** (e.g. labwc or sway) selectable in SDDM, plus a boot menu entry "Safe graphics" (`nomodeset`, software rendering). Calamares must launch in either. |
| 11 | Name `MahaDevan's OS` used everywhere | The apostrophe and spaces break ISO volume labels, shell scripts, package names, GRUB IDs, and `os-release`. | Display name stays in branding text. Technical names use `mahadevanos`. ISO label: `MAHADEVANOS_YYYYMM` (max 32 chars, uppercase). `os-release`: `NAME="MahaDevan OS"`, `ID=mahadevanos`, `ID_LIKE=arch`. |
| 12 | Ollama, AI assistant, Docker, KVM, Android, Steam, Secure Boot, firewall GUI, performance profiles, website, repo signing all in the planned scope | None of this is needed for a bootable ISO and each is a rabbit hole. | Everything optional becomes an **install profile** (post-install) or is deferred. AI integration is deferred entirely. |
| 13 | Linux Zen as optional kernel | Fine, but a fallback kernel matters more for recovery. | Ship `linux` (default) + `linux-lts` (fallback in GRUB). Zen can be a post-install profile. |
| 14 | Agent must ask approval for every privileged action | `mkarchiso` needs root, so the agent would stall constantly. | Section 9: a **pre-approved command allowlist** scoped to the project directory. Destructive operations on real devices stay forbidden. |
| 15 | Tests assume interactive GUI testing | An agent cannot click through Calamares. | Agent automates what it can (ISO build, UEFI boot to login, serial log, screenshot via QEMU monitor, installed-disk boot). The **GUI install walkthrough** is a human step with a written checklist (section 8). |
| 16 | Host is CachyOS | CachyOS adds its own repos and x86-64-v3 packages. They must never leak into an Arch-based ISO. | Build with the profile's own `pacman.conf` (Arch repos only) and `devtools` clean chroots. Add a CI-style check that fails if any package in the manifest comes from a non-Arch repo. |
| 17 | `multilib` not mentioned | Steam/Proton need `[multilib]`. | Enabled in the installed system's `pacman.conf`. Gaming packages are installed by profile, not shipped in the ISO. |

---

## 3. Final technical decisions

| Component | Decision |
|---|---|
| Base | Arch Linux x86_64 |
| Live ISO builder | `archiso` (`mkarchiso`), profile copied from `/usr/share/archiso/configs/releng/` |
| Installer | Calamares (built from AUR in clean chroot), **offline `unpackfs`** |
| Installed bootloader | **GRUB (UEFI)** + `os-prober` for dual boot; `grub-btrfs` snapshot entries |
| Filesystem | Btrfs, `compress=zstd:1,noatime` |
| Subvolumes | `@` → `/`, `@home` → `/home`, `@log` → `/var/log`, `@cache` → `/var/cache`, `@snapshots` → `/.snapshots` (follow snapper's documented layout; verify before finalizing) |
| Snapshots | `snapper` + `snap-pac` + `grub-btrfs` (+ `grub-btrfsd`, overlayfs hook for read-only snapshot boots) |
| Kernels | `linux` default, `linux-lts` fallback |
| Init | systemd |
| Network | NetworkManager (+ iwd or wpa_supplicant backend as default) |
| Audio | PipeWire + WirePlumber |
| Bluetooth | BlueZ |
| Display manager | SDDM (Wayland-capable, autologin only in live session) |
| Compositor | Hyprland |
| Shell | Existing Quickshell-based config, forked and rebranded (decide in M4) |
| Fallback session | labwc or sway (live ISO and installed) |
| File manager | Dolphin with default config tweaks |
| Terminal | Kitty with MahaDevan theme |
| Firewall | `ufw` or `firewalld` enabled by default (pick one; `ufw` is simpler) |
| Flatpak | Installed, Flathub preconfigured |
| Package source policy | Arch official + Flatpak. AUR only via a clearly warned helper (`paru`/`yay`), never silently, never as root |
| Secure Boot | Not in v1 |
| Legacy BIOS | Not in v1 (UEFI only for the installed system) |

---

## 4. Repository structure

```text
mahadevanos/
├── README.md  LICENSE  CHANGELOG.md  SECURITY.md  CONTRIBUTING.md
├── OS_BLUEPRINT.md
├── .gitignore               # build/ out/ repo/x86_64/*.pkg.* *.qcow2 .env keys/
├── branding/                # logos, wallpapers, grub theme, plymouth, calamares branding
├── iso/
│   ├── profile/             # archiso profile (packages.x86_64, airootfs/, pacman.conf, profiledef.sh)
│   ├── packages/            # split package lists: base.txt desktop.txt live-only.txt firmware.txt
│   └── checks/              # manifest + repo-origin checks
├── installer/
│   ├── calamares/           # settings.conf, modules/*.conf, branding/
│   └── postinstall/         # shellprocess scripts run by Calamares
├── packaging/               # PKGBUILDs: calamares-config, mahadevanos-branding, mahadevanos-settings, ...
├── repo/                    # local pacman repo (gitignored binaries; PKGBUILDs tracked)
├── configs/                 # hyprland, quickshell, kitty, dolphin, sddm, snapper, grub defaults, ufw
├── profiles/                # post-install profiles: gaming, dev, virtualization, ai
├── scripts/                 # build-repo.sh build-iso.sh test-boot.sh test-install.sh checksum.sh
├── tests/                   # boot/install automation, manifest checks
└── documentation/           # build, install, recovery, architecture, known-issues
```

---

## 5. Milestones (do them in order; each must pass its tests before the next)

### M0 — Host preparation and repository scaffold
Tasks:
- Verify and report host tools: `archiso`, `devtools`, `qemu-full`, `edk2-ovmf`, `git`, `base-devel`, `squashfs-tools`, `libisoburn`, `mtools`, `shellcheck`. List missing ones and ask me to install them (do not install silently).
- Verify free disk space (build needs roughly 30 GB) and that `/dev/kvm` is accessible.
- Create the repo structure above, `.gitignore`, README, and commit.
- Confirm no CachyOS repo or x86-64-v3 package can enter the build (the profile's `pacman.conf` lists only Arch repos).

Acceptance: tool check report saved to `documentation/development/host-check.md`; initial commit exists.

### M1 — Bootable minimal live ISO
Tasks:
- Copy the `releng` profile into `iso/profile/`, rename to `mahadevanos` (label `MAHADEVANOS_YYYYMM`, `iso_name`, `iso_publisher`, `os-release` with `ID=mahadevanos`, `ID_LIKE=arch`).
- Set build `pacman.conf` to the pinned Arch Linux Archive date. Record the date in `iso/profile/PINNED_DATE`.
- Package list: base, `linux`, `linux-lts`, full `linux-firmware`, microcode, NetworkManager, `btrfs-progs`, `grub`, `efibootmgr`, `os-prober`, `mkinitcpio`, `nano`, `vim`, `git`, `htop`, `pciutils`, `usbutils`, `man-db`.
- Live user `liveuser` (passwordless sudo in live session only, never installed).
- `scripts/build-iso.sh`: builds with `sudo mkarchiso -v -w build/work -o out iso/profile`, then writes checksum and manifest (`pacman -Q` inside the image, or the package list from the build log).
- `scripts/test-boot.sh`: boots the ISO in QEMU with OVMF (UEFI), 4 GB RAM, serial console, and checks for a login prompt or shell; saves `out/test-boot.log` and a screenshot.

Acceptance:
- `out/mahadevanos-<date>-x86_64.iso`, `.sha256`, `.manifest.txt`, and `build.log` exist.
- ISO boots in UEFI QEMU to a shell; `ip a` shows a network interface; evidence saved.
- Nothing outside the project directory was changed.

### M2 — Calamares offline installer + minimal desktop
Tasks:
1. **Local repo.** In a clean chroot (`extra-x86_64-build` from `devtools`), build `calamares` and `ckbcomp` from the AUR (review each PKGBUILD first and report anything suspicious). Create `repo/x86_64/mahadevanos-local.db.tar.zst` with `repo-add`. Add the repo to the build `pacman.conf`.
2. **Minimal desktop.** SDDM (autologin to `liveuser` only in the live image), Hyprland with a simple stock-style config, Kitty, Dolphin, a launcher, NetworkManager applet/tray or equivalent, PipeWire. A fallback session (labwc or sway) available in SDDM.
3. **Calamares configuration** (`installer/calamares/`), module sequence:
   `welcome → locale → keyboard → partition → users → summary` (show), then exec:
   `partition → mount → unpackfs → machineid → fstab → locale → keyboard → localecfg → initcpio → users → displaymanager → networkcfg → hwclock → services-systemd → shellprocess (post-install) → grubcfg → bootloader → umount`.
   - `unpackfs`: source `/run/archiso/bootmnt/arch/x86_64/airootfs.sfs`, `sourcefs: squashfs`, destination `/` (verify the exact path on the live system).
   - `partition.conf`: default FS `btrfs`, `btrfsSubvolumes` as in section 3, `luksGeneration: luks1`, UEFI layout: 1 GiB FAT32 ESP at `/boot/efi`, rest Btrfs.
   - `bootloader.conf`: `efiBootLoader: "grub"`, bootloader ID `mahadevanos`.
   - `users.conf`: create the user with sudo group; disable autologin in the installed system; hostname set.
4. **Post-install shellprocess** (runs in the target chroot) must:
   - Remove live-only items: `liveuser`, SDDM autologin file, passwordless sudo rule, Calamares and its config, archiso mkinitcpio hooks/config.
   - **Restore a normal `/etc/mkinitcpio.conf`** (the live image uses archiso hooks which must not be on the installed system) and regenerate initramfs for both kernels. Include `btrfs` hook/module handling.
   - Run `pacman-key --init && pacman-key --populate archlinux` (the live keyring state is not copied).
   - Write a real mirrorlist (installed system uses normal mirrors, not the pinned archive date) and enable `[multilib]`.
   - Enable services: `NetworkManager`, `sddm`, `bluetooth`, `fstrim.timer`, firewall, `systemd-timesyncd`.
5. Desktop shortcut and autostart prompt: "Install MahaDevan's OS".
6. **Safe graphics boot entry** in the live boot menu.

Acceptance (automated by agent where possible):
- Calamares package is built from clean chroot; repo DB exists.
- Live ISO boots to Hyprland in QEMU with virtio-gpu; fallback session also starts.
- Calamares window launches (screenshot).
- **Human checklist (section 8) passes**: install onto a blank qcow2 disk in virt-manager/QEMU, reboot without the ISO, log in as the created user, network works.
- Installed system has no `liveuser`, no autologin, working `pacman -Syu`, correct `os-release`, and boots via GRUB.

### M3 — Btrfs snapshots and recovery
Tasks:
- Install and configure `snapper` (root config), `snap-pac`, `grub-btrfs`, `grub-btrfsd.service`, the overlayfs mkinitcpio hook for read-only snapshot booting.
- Snapshot retention limits so disk does not fill; never delete the last known-good snapshot.
- GRUB menu shows "Snapshots" submenu; `linux-lts` fallback entry; GRUB timeout visible (≥3 s).
- Documentation `documentation/recovery/`: how to boot a snapshot, roll back, repair GRUB from the live USB (chroot steps, using the BTRFS subvolume names above).
- Include `btrfs-assistant` (or equivalent GUI) for snapshot management.

Acceptance:
- On the installed VM: `sudo pacman -S <test-package>` creates pre/post snapshots; the snapshot appears in the GRUB menu.
- Break the system deliberately (e.g. remove a critical file in the VM), boot a snapshot, roll back, system works again.
- Evidence logs saved under `tests/evidence/`.

**After M3 you have a real, installable, recoverable Arch-based distro. Everything below is improvement.**

### M4 — Real desktop experience and branding
- Choose and fork the Quickshell shell config (record the license and upstream commit; pin it). Provide: top panel, launcher, notifications, quick settings (Wi-Fi, volume, brightness, Bluetooth, power), clipboard history, screenshot/screen recording, lock screen, wallpaper selection.
- Kitty theme and shortcuts; Dolphin with terminal panel, previews, archive support, network locations, Git plugin if available.
- Branding: logo, GRUB theme (must stay readable), SDDM theme, Plymouth splash, wallpapers, Calamares slideshow.
- Hyprland config split into modular files plus a **safe fallback** (restore defaults if config errors; keybind to reload; a TTY always reachable).
- Document all keybindings.

Acceptance: login → full desktop; every panel control acts on real system state or is removed; shell crash does not strand the user (fallback session or TTY works).

### M5 — Hardware auto-detection, optional profiles, optional LUKS
- **Hardware detection** (post-install shellprocess + first-boot service): detect GPU via `lspci`. AMD/Intel need nothing extra. For NVIDIA, install the right driver **from an offline repo on the ISO** (e.g. `/opt/mahadevanos-offline/`, local pacman repo or `pacman -U` files): `nvidia-open` for Turing and newer with the stock `linux` kernel; older GPUs need a legacy branch (verify current Arch package names). Add `nvidia-drm.modeset=1`, correct initramfs modules, and never install two conflicting stacks. Detect hybrid graphics and only configure PRIME where supported. Detect VMs and install guest tools (`qemu-guest-agent`, `spice-vdagent`, `virtualbox-guest-utils` as appropriate).
- **Profiles tool** `mahadevanos-setup` (TUI first, a simple GUI later): `gaming` (steam, lutris, gamemode, mangohud, wine), `dev` (docker, podman, git, github-cli, python, nodejs, rustup, jdk), `virtualization` (qemu, libvirt, virt-manager), `ai` (ollama; optional model download with disk-space warning), `zen-kernel`. Each profile lists what it installs, asks confirmation, and snapshots first.
- **Optional LUKS1** encryption in Calamares, tested on VM (GRUB unlocks, system boots, snapshots still work). Marked experimental.
- Performance: `power-profiles-daemon`, `zram-generator`, `thermald` where applicable.

Acceptance: install on a VM with GPU passthrough is not required; the NVIDIA path must at least be unit-tested for detection logic and produce a documented manual test on real hardware. Do **not** advertise NVIDIA as supported until tested on real hardware.

### M6 — Release candidate
- Clean build from scratch, all tests rerun, ISO signed (GPG) with checksums.
- Test on the developer's AMD laptop (Ryzen 5 5600H / RX 6500M) from USB: live boot, Wi-Fi, audio, brightness, suspend/resume, GPU acceleration (`vulkaninfo`, `glxinfo`), install to a **separate disk or partition chosen by the human**, never by the agent.
- Known-issues document, release notes, build instructions.

### M7+ (deferred; do not start before M6 passes)
Custom Rust/GTK settings, store, system monitor; own package repository and signing keys; Secure Boot; AI command assistant; website; public beta; BIOS support; install-alongside Windows auto-resize.

---

## 6. Package and build rules

- Package lists live in `iso/packages/*.txt` and are concatenated into `packages.x86_64` by script. One package per line, comments allowed.
- Every package in the final manifest must come from `core`, `extra`, `multilib` (installed system only), or `mahadevanos-local`. The check script fails the build otherwise.
- Custom packages (`mahadevanos-branding`, `mahadevanos-settings`, `calamares-config`) are PKGBUILDs under `packaging/`, built in a clean chroot into `repo/`. No loose files copied blindly into `airootfs` for anything that should exist on the installed system.
- `airootfs` holds only live-specific files (autologin, live user, Calamares autostart). Installed-system config comes from packages.
- Never include games, model weights, or proprietary assets in the ISO.
- ISO target: about 3-5 GB. Measure and report. Do not remove firmware or drivers just to hit a number.
- Keep scripts idempotent. Log everything under `build/logs/`.

---

## 7. Security and privilege rules

- No passwords in scripts or logs. Live user is passwordless only in the live session; the installer creates the real user with a password chosen by the person installing.
- No broad passwordless sudo in the installed system.
- Firewall enabled by default with deny-incoming; allow nothing extra by default.
- Never run AUR builds as root. Review every AUR PKGBUILD before building and report what you found.
- Keys and tokens never enter git. `.gitignore` covers `keys/`, `.env`, `*.gpg`, `*.key`.
- All installer destructive actions must show the exact device and require explicit confirmation (this is Calamares' default; do not weaken it).

---

## 8. Test strategy

**Automated by the agent (save evidence in `tests/evidence/<date>/`):**
1. `scripts/build-iso.sh` succeeds; checksum and manifest generated; repo-origin check passes.
2. `scripts/test-boot.sh`: QEMU + OVMF UEFI boot, serial log shows boot to login or live session; screenshot saved.
3. Installed-disk boot test: after a human or scripted install, boot `build/test-disk.qcow2` **without** the ISO and confirm GRUB → login.
4. Static checks: `shellcheck` on all scripts; package list lint; no secrets in repo.

Example QEMU command (adjust OVMF paths for the host; verify with `ls /usr/share/edk2/x64/`):
```bash
qemu-img create -f qcow2 build/test-disk.qcow2 40G
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd build/OVMF_VARS.fd
qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 6144 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=build/OVMF_VARS.fd \
  -drive file=build/test-disk.qcow2,if=virtio \
  -cdrom out/mahadevanos-*.iso -boot d \
  -device virtio-vga-gl -display gtk,gl=on \
  -device virtio-net-pci,netdev=n0 -netdev user,id=n0
```
For headless runs use `-display none -serial mon:stdio` and a test-only kernel parameter `console=ttyS0`, and capture screenshots through the QEMU monitor `screendump` command.

**Human checklist (agent provides this as `documentation/installation/manual-test.md` and I run it):**
- [ ] ISO boots in virt-manager (UEFI/OVMF) to the live desktop
- [ ] "Install MahaDevan's OS" starts Calamares
- [ ] Automatic partitioning with Btrfs completes with no network
- [ ] Reboot without ISO reaches the login screen
- [ ] Login works; Wi-Fi/Ethernet works; sound works; Kitty and Dolphin open
- [ ] `sudo pacman -Syu` works
- [ ] Snapshot menu appears in GRUB after a package install (from M3)
- [ ] Rollback works (from M3)

Physical hardware tests only on a USB stick and a disk/partition **I choose**.

---

## 9. Agent operating protocol

**Pre-approved without asking** (all inside the project directory, none touch real block devices):
`git`, `shellcheck`, `makepkg`/`extra-x86_64-build` (clean chroot), `repo-add`, `sudo mkarchiso -w build/work -o out ...`, `qemu-system-x86_64`, `qemu-img`, file operations under the project directory, `sha256sum`, `gpg` (verification only), read-only commands (`ls`, `cat`, `lsblk`, `pacman -Q*`, `pacman -Si`).

**Always ask me first:**
- Installing host packages (`pacman -S` on the host)
- Anything touching `/dev/sdX`, `/dev/nvmeXnY`, host `/boot`, host `/etc`, host firewall or network
- Writing the ISO to a USB device (I will do it myself, or you must show the exact device and wait for my confirmation)
- Any `sudo` command not listed above

**Never do:** `mkfs`, `wipefs`, partitioning tools, `grub-install`, `efibootmgr` modifications, or `dd` against a real device; assume a disk name; commit secrets; claim a test passed without evidence.

**Start of each session:** read this file and README; inspect git status and `tests/evidence/`; state the active milestone and what remains; propose a short plan; then execute.

**End of each session:** report files changed, commands run, tests passed and failed (with evidence paths), known limitations, security or compatibility concerns, the exact next step, and whether the milestone's acceptance criteria are met.

**Honesty rule:** status labels are `TESTED`, `IMPLEMENTED (untested)`, `EXPERIMENTAL`, or `PLANNED`. Never mix them up.

---

## 10. Writing the ISO to USB (human step)

On CachyOS, identify the USB with `lsblk` (check size and name carefully), then write it with `dd` (or a GUI writer such as balenaEtcher). Example (replace `sdX` only after verifying it is the USB stick; this erases it):
```bash
sudo dd if=out/mahadevanos-<date>-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```
Verify the checksum first: `sha256sum -c out/*.sha256`.

---

## 11. Definition of done for the first release (v0.1 "personal daily driver")

- Bootable UEFI ISO built by one command from the repo.
- Garuda-style offline Calamares install to Btrfs with GRUB and snapshots.
- Hyprland desktop, Kitty, Dolphin, NetworkManager, PipeWire, Bluetooth, firewall working out of the box.
- AMD and Intel graphics work with no manual steps; NVIDIA handled by M5 and labelled according to actual testing.
- Failed update recoverable from the GRUB snapshot menu.
- Documentation for building, installing, and recovering.
- Honest known-issues list.

**End of blueprint v2.**
