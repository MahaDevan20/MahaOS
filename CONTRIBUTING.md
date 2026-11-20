# Contributing

## Before you start

Read [`OS_BLUEPRINT.md`](OS_BLUEPRINT.md). It is the specification; this file only
covers mechanics. Work happens inside the project directory. Never test on real
block devices.

## Ground rules

1. **Scripts are bash.** Every script starts with `#!/usr/bin/env bash` and
   `set -euo pipefail`. Never fish.
2. **No new components from scratch.** Reuse archiso, Calamares, GRUB, snapper,
   grub-btrfs, Hyprland, SDDM, NetworkManager, PipeWire. A PR that reimplements one
   of these will be declined.
3. **Respect the milestones.** Do not ship M4+ polish while M2 is unproven.
4. **Evidence or it did not happen.** A change that claims to fix booting must
   include the log or screenshot under `tests/evidence/<date>/`.
5. **Honest status.** Label work `TESTED`, `IMPLEMENTED (untested)`, `EXPERIMENTAL`
   or `PLANNED`.

## Checks to run before a PR

```bash
bash -n scripts/*.sh installer/postinstall/*.sh
shellcheck scripts/*.sh installer/postinstall/*.sh profiles/*.sh
./scripts/generate-package-list.sh
./scripts/checksum.sh --verify-only   # only when out/*.iso exists
```

`iso/checks/check-repo-origins.sh` must pass: every package in the manifest comes
from `core`, `extra`, `multilib` (installed system only) or `mahadevanos-local`.
CachyOS/Garuda repositories and `x86-64-v3` packages must never leak into the ISO.

## Commit style

Imperative subject under 72 characters, blank line, then why the change exists.
Reference the milestone (`M1`, `M2`, ...) when relevant.

## Adding a package

Edit the matching file in `iso/packages/` and regenerate:

- `base.txt` — boot, kernel, filesystem, networking essentials
- `desktop.txt` — desktop session and apps
- `firmware.txt` — firmware, microcode, GPU userspace
- `live-only.txt` — tools that must never reach an installed system

Never edit `iso/profile/packages.x86_64` by hand; `scripts/generate-package-list.sh`
owns it.

## Reporting bugs

Include: ISO checksum, host, firmware mode (UEFI/legacy), GPU, whether the failure
is in the live session or the installed system, the serial log (`out/test-boot.log`)
and `journalctl -b -1` from the installed system when reachable.
