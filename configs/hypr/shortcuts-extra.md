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
