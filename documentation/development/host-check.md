# M0 host check

Recorded on the build host at the start of this checkout (2026-11-20).

## Host

| Item | Value | Verdict |
|---|---|---|
| Distribution | Garuda Linux (`ID=garuda`, `ID_LIKE=arch`) | Arch-based, usable as build host |
| Kernel | `7.3.4-1-garuda` x86_64 | OK |
| Architecture | `x86_64` | OK |
| Free space in the project filesystem | 253 GiB (477 GiB total, 47 % used) | OK (build needs ~30 GiB) |
| `/dev/kvm` | present, `crw-rw-rw- root:kvm` | OK, KVM acceleration available |
| OVMF firmware | `/usr/share/edk2/x64/OVMF_CODE.4m.fd`, `OVMF_VARS.4m.fd` | OK |
| git | 2.56.1 | OK |

Note: the blueprint names **CachyOS** as the build host; this machine is **Garuda**.
Both are Arch-based and the ISO build never uses the host's repositories, only the
pinned Arch mirrors in `iso/profile/pacman.conf`, so the difference does not affect
the artifact. It does mean the CachyOS-specific caveat (blueprint §2 #16) applies to
the host's own `pacman.conf` — which the build deliberately does not read.

## Required tools

| Tool | Status |
|---|---|
| `qemu-system-x86_64`, `qemu-img` | present |
| `git`, `makepkg`, `repo-add` | present |
| `xorriso`, `mtools` | present |
| `pacman`, `grub-install`, `snapper` | present |
| **`mkarchiso` (archiso)** | **MISSING** |
| **`extra-x86_64-build` (devtools)** | **MISSING** |
| **`mksquashfs` (squashfs-tools)** | **MISSING** |
| **`shellcheck`** | **MISSING** |

Per the blueprint (§5 M0), missing host packages are **not installed silently**.
Install them with:

```bash
sudo pacman -S --needed archiso devtools squashfs-tools shellcheck libisoburn mtools
```

`qemu-full`, `edk2-ovmf`, `base-devel` and `git` are already satisfied.

## What works right now

- Repository scaffold, scripts, archiso profile, Calamares config, branding and docs.
- `scripts/generate-package-list.sh` (no privileges needed).
- Script syntax checks (`bash -n`) on every script.

## What does not work yet

- `scripts/build-iso.sh` exits early with `mkarchiso missing`.
- `scripts/build-repo.sh` exits early with `devtools not installed: need extra-x86_64-build`.
- `scripts/test-boot.sh` runs only after an ISO exists.
- `shellcheck` linting is unavailable on this host.

Nothing has been booted. No ISO exists in `out/` yet.
