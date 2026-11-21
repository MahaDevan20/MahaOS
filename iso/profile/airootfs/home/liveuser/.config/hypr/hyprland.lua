-- MahaDevan's OS — live session (Hyprland 0.57 Lua config).
--
-- The shared defaults ship with mahadevanos-settings as
-- /etc/xdg/hypr/hyprland.lua; this file only adds what is live-only: starting
-- the installer automatically once the session is up, and a way to bring it
-- back if its window was closed.
--
-- This file lives only in /home/liveuser. The installer deletes liveuser, so an
-- installed system never sees it.

dofile("/etc/xdg/hypr/hyprland.lua")

-- Relaunch (or re-focus) the installer: SUPER + I.
hl.bind("SUPER + I", hl.dsp.exec_cmd("/usr/local/bin/mahadevanos-installer"))

hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/local/bin/mahadevanos-installer")
end)
