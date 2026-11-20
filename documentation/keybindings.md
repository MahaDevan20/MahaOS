# Keybindings

Source of truth: `configs/hypr/conf.d/30-keybinds.conf`. `SUPER` is the Windows key.

## Applications

| Key | Action |
|---|---|
| `SUPER + Return` | kitty terminal |
| `SUPER + D` | wofi launcher |
| `SUPER + E` | dolphin |
| `SUPER + L` | lock (hyprlock) |
| `SUPER + V` | clipboard paste (cliphist) |
| `SUPER + SHIFT + S` | screenshot a region to clipboard |
| `SUPER + PRINT` | screenshot the screen to clipboard |

## Windows

| Key | Action |
|---|---|
| `SUPER + Q` | close window |
| `SUPER + SHIFT + Q` | exit Hyprland |
| `SUPER + F` | fullscreen |
| `SUPER + Space` | toggle floating |
| `SUPER + P` | pseudo-tile |
| `SUPER + J` | toggle split |
| `SUPER + arrows` | move focus |
| `SUPER + SHIFT + arrows` | move window |
| `SUPER + drag` | move window with mouse |
| `SUPER + right-drag` | resize window |

## Workspaces

| Key | Action |
|---|---|
| `SUPER + 1..0` | switch to workspace 1..10 |
| `SUPER + SHIFT + 1..0` | move window to workspace 1..10 |
| `SUPER + three-finger swipe` | switch workspace (touchpad) |

## Hardware keys

| Key | Action |
|---|---|
| `XF86AudioRaise/LowerVolume` | volume ±5 % |
| `XF86AudioMute` | mute output |
| `XF86AudioPlay/Next/Prev` | media control (playerctl) |
| `XF86MonBrightnessUp/Down` | brightness ±5 % (needs `brightnessctl`) |

## Escape hatches

| Key | Action |
|---|---|
| `SUPER + SHIFT + R` | reload Hyprland config |
| `CTRL + ALT + F2` | TTY (always available) |
| SDDM session menu | choose `labwc` if Hyprland fails |

If a config edit breaks the session: `hyprctl reload` from a TTY after fixing, or
delete `~/.config/hypr/conf.d/` to fall back to `/etc/xdg/hypr`.
