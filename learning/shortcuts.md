# MahaDevan's OS — keyboard shortcuts

**Super is the Windows key.** It is the modifier every MahaDevan's OS shortcut
starts with, so `Super + Q` means "hold the Windows key and press Q".

This sheet is generated from the real compositor configuration
(`/etc/xdg/hypr/hyprland.lua`, source `configs/hypr/hyprland.lua`), so it cannot
drift from what the desktop actually does. Do not edit it by hand:
`mhelp keys` shows this file, `scripts/gen-shortcuts.sh` regenerates it.

## Applications

| Shortcut | Action |
|---|---|
| `SUPER + Q` | Open the terminal (kitty) |
| `SUPER + Return` | Open the terminal (kitty) — same as Super + Q |
| `SUPER + D` | Open the launcher (wofi): type to search apps, Enter to run |
| `SUPER + E` | Open Dolphin, the file manager |
| `SUPER + SHIFT + S` | Screenshot a region you select with the mouse, copied to the clipboard |
| `SUPER + PRINT` | Screenshot the whole screen, copied to the clipboard |

## Windows

| Shortcut | Action |
|---|---|
| `SUPER + C` | Close the focused window |
| `SUPER + F` | Toggle fullscreen for the focused window |
| `SUPER + Space` | Toggle floating (a normal, movable window) for the focused window |
| `SUPER + P` | Toggle pseudo-tiling (keep the split but tile as one window) |
| `SUPER + J` | Swap the split direction of the focused window |
| `SUPER + left` | Move focus to the window on the left |
| `SUPER + right` | Move focus to the window on the right |
| `SUPER + up` | Move focus to the window above |
| `SUPER + down` | Move focus to the window below |
| `SUPER + SHIFT + left` | Move the focused window to the left |
| `SUPER + SHIFT + right` | Move the focused window to the right |
| `SUPER + SHIFT + up` | Move the focused window up |
| `SUPER + SHIFT + down` | Move the focused window down |
| `SUPER + left drag` | Hold and drag with the left button to move a window |
| `SUPER + right drag` | Hold and drag with the right button to resize a window |

## Workspaces

| Shortcut | Action |
|---|---|
| `SUPER + <loop> (focus)` | Switch to workspace 1 … 10 (Super + 1 is the first, Super + 0 the tenth) |
| `SUPER + <loop> (window.move)` | Move the focused window to workspace 1 … 10 |
| `SUPER + scroll down` | Switch to the previous workspace (scroll down on the desktop) |
| `SUPER + scroll up` | Switch to the next workspace (scroll up on the desktop) |

## Hardware keys

| Shortcut | Action |
|---|---|
| `XF86AudioRaiseVolume` | Volume up in 5 % steps (up to 140 %) |
| `XF86AudioLowerVolume` | Volume down in 5 % steps |
| `XF86AudioMute` | Mute or unmute the sound output |
| `XF86AudioPlay` | Play or pause the current track (playerctl) |
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |
| `XF86MonBrightnessUp` | Screen brighter (brightnessctl, needs a backlight) |
| `XF86MonBrightnessDown` | Screen dimmer (brightnessctl, needs a backlight) |

## Session

| Shortcut | Action |
|---|---|
| `SUPER + SHIFT + L` | Lock the screen (loginctl lock-session) |
| `SUPER + SHIFT + R` | Reload the Hyprland configuration after editing it |
| `SUPER + SHIFT + Q` | Exit Hyprland (log out; SDDM comes back) |

## Live session only

| Shortcut | Action |
|---|---|
| `SUPER + I` | Start the installer again, or bring its window to the front |

## When something goes wrong

| Keys | What to do |
|---|---|
| `Ctrl + Alt + F2` … `F6` | Switch to a text console (TTY); log in there with your user name and password |
| `Ctrl + Alt + F1` | Back to the graphical session (SDDM runs on tty1) |
| `Super + Shift + R` | Reload the config from inside the session after fixing a typo |
| from a TTY: `hyprctl reload` | Reload the config when the session still answers |
| from a TTY: `mv ~/.config/hypr ~/.config/hypr.bak` | Delete a broken personal config; the next login uses the system default in `/etc/xdg/hypr` |

If Hyprland will not start at all, pick the **labwc** session in SDDM's session
menu instead: it is a small, plain window manager that is always installed, so a
graphical desktop stays reachable.

## Mouse and touchpad

| Gesture | Action |
|---|---|
| `Super` + scroll | Previous / next workspace |
| `Super` + left-drag | Move a window |
| `Super` + right-drag | Resize a window |
| three-finger horizontal swipe | Previous / next workspace (touchpad) |

## Terminal shortcuts (kitty)

| Shortcut | Action |
|---|---|
| `Ctrl + Shift + C` | Copy the selection |
| `Ctrl + Shift + V` | Paste |
| `Ctrl + Shift + +` / `-` / `0` | Bigger / smaller / normal font size |

`mhelp` — this sheet, the command guide and the network guide, all offline.
