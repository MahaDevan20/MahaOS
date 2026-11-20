# Local pacman repository

`repo/x86_64/` holds the packages that are not in the official Arch repositories —
chiefly **calamares** and **ckbcomp** (both AUR) plus this project's own
`mahadevanos-branding`, `mahadevanos-settings` and `calamares-config`.

Built packages (`*.pkg.tar.*`, `*.db`, `*.files`) are **gitignored**; only the
PKGBUILDs under `packaging/` are tracked.

```bash
./scripts/build-repo.sh          # build everything in clean chroots, then repo-add
./scripts/build-repo.sh --force  # rebuild
```

Rules:

- Build **in a clean chroot** with `extra-x86_64-build` (devtools), never as root,
  never with `makepkg` directly against the host.
- Review each AUR PKGBUILD before the first build and record anything suspicious.
- Never pull prebuilt binaries from third parties into this directory.
- `repo-add` runs with `--remove` and writes `mahadevanos-local.db.tar.zst`, which
  the ISO build `pacman.conf` consumes as `[mahadevanos-local]`.

The build `pacman.conf` in `iso/profile/` points at
`file:///home/mahadevanos/repo/$arch`; `scripts/build-iso.sh` rewrites that to this
checkout's absolute path in its working copy, so no manual editing is needed.
