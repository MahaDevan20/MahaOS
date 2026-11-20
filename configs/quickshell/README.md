# Quickshell desktop shell — M4 (PLANNED)

The blueprint (M4) says to **adopt and fork an existing Quickshell-based Hyprland
shell** rather than write one: a panel, launcher, notifications, quick settings,
clipboard history, screenshot/recording, lock screen and wallpaper picker is a
multi-month project on its own.

Nothing is vendored here yet, on purpose. Before adding one:

1. Pick a maintained upstream (for example Caelestia or end-4's dots).
2. Record the upstream URL, commit hash and **license** (GPL-3.0 and MIT are both
   acceptable; `${license}` must be compatible with this repo's MIT license for
   the parts we keep).
3. Vendor it under `configs/quickshell/upstream/` with the license file intact.
4. Rebrand only the strings, colours and icons; keep the structure so upstream
   fixes can be merged.
5. Pin the commit in `configs/quickshell/UPSTREAM.md`.

Until then, M0–M3 systems boot without a Quickshell dependency: Hyprland itself is
the session, and the panel controls come from `nm-applet`, `blueman-applet` and
`wpctl`/`brightnessctl` keybinds.
