# Known issues

Status labels: `TESTED`, `IMPLEMENTED (untested)`, `EXPERIMENTAL`, `PLANNED`.

## Build

| # | Issue | Status |
|---|---|---|
| 1 | No ISO has been built in this checkout. The host lacks `archiso`, `devtools` and `squashfs-tools`. | `IMPLEMENTED (untested)` |
| 2 | `repo/x86_64/` is empty until `scripts/build-repo.sh` runs; until then the live ISO would have no Calamares. | `IMPLEMENTED (untested)` |
| 3 | `shellcheck` is not installed on the build host, so only `bash -n` syntax checks have been run. | limitation |
| 4 | Builds are repeatable (pinned archive date) but not bit-for-bit reproducible. Arch is rolling. | by design |

## Installer

| # | Issue | Status |
|---|---|---|
| 5 | The Calamares GUI walkthrough has not been performed. | `IMPLEMENTED (untested)` |
| 6 | `unpackfs` source path `/run/archiso/bootmnt/arch/x86_64/airootfs.sfs` must be verified on the built live system. If archiso changes its mount layout, the install fails with "source not found". | verify on first boot |
| 7 | Encryption uses **LUKS1** (GRUB cannot unlock LUKS2/argon2id). Experimental, off by default. | `EXPERIMENTAL` |
| 8 | "Install alongside Windows" with automatic resize is not offered. Dual boot works via os-prober and manual partitioning. | `PLANNED` |
| 9 | Calamares may warn about missing `ckbcomp` if the local repo was not built; keyboard conversion then falls back to defaults. | `IMPLEMENTED (untested)` |

## Hardware

| # | Issue | Status |
|---|---|---|
| 10 | **NVIDIA proprietary drivers are not installed.** Nouveau/mesa works; the proprietary path (`nvidia-open`) is a placeholder in `50-hardware-detect.sh`. Do not advertise NVIDIA as supported. | `EXPERIMENTAL` |
| 11 | AMD/Intel graphics rely on mesa + vulkan-radeon/vulkan-intel being in the ISO; untested on real hardware. | `IMPLEMENTED (untested)` |
| 12 | Hybrid graphics (PRIME) is not configured automatically. | `PLANNED` |
| 13 | Brightness keys assume `brightnessctl`, which is not in the package list yet. Add it, or the keys do nothing. | `PLANNED` |
| 14 | Fingerprint readers are not configured. | `PLANNED` |
| 15 | Secure Boot is not supported; disable it to boot. | by design (v1) |

## Desktop

| # | Issue | Status |
|---|---|---|
| 16 | No Quickshell panel yet. Tray/clipboard/screenshot come from applets and keybinds. | `PLANNED` (M4) |
| 17 | Plymouth theme is installed but not enabled; enabling needs the `plymouth` mkinitcpio hook and `plymouth-set-default-theme -R mahadevanos`. | `PLANNED` (M4) |
| 18 | SDDM uses the stock Breeze theme; a branded theme is M4 work. | `PLANNED` |
| 19 | GTK apps may look inconsistent under Hyprland until `qt6ct`/`nwg-look` are configured. | known cosmetic issue |
| 20 | `btrfs-assistant` availability in the official repos varies; if it is missing from `extra`, the ISO build fails and it must be dropped or built into `repo/`. | verify |

## Packages

| # | Issue | Status |
|---|---|---|
| 21 | Package names drift in Arch. `iso/packages/*.txt` is checked only at build time; a rename breaks the build with "target not found". | expected maintenance |
| 22 | Gaming/AI/dev profiles install large packages and have not been run on an installed system. | `IMPLEMENTED (untested)` |
| 23 | Ollama model weights are never bundled (size, licensing). The profile installs the runtime only. | by design |

## Security notes

- Live session has a known password (`live`) and passwordless sudo; this is
  **live-only** and removed by `99-cleanup.sh`, which fails the install if the live
  user or sudoers rule survives.
- The firewall is enabled post-install with deny-incoming, nothing allowed.
- No AUR builds as root; the ISO carries prebuilt local packages only.
