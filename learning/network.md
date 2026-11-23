# MahaDevan's OS — getting on a network

MahaDevan's OS uses **NetworkManager** for every connection (Ethernet, Wi-Fi,
mobile broadband) and ships its applet in the panel, its `nmcli` command and the
menu-based `nmtui`. Nothing else is needed for the steps below.

Check what you have: `nmcli device status` lists each interface and whether it
is connected. `ip a` shows the addresses each interface actually got.

---

## 1. Ethernet (a cable)

Usually nothing to do: plug the cable in and NetworkManager connects within a
few seconds, asking the router for an address automatically (DHCP).

1. Plug the cable into the machine and the router/switch.
2. Check that the link is up:

   ```bash
   ip a
   ```

   Look for the wired interface (`enp1s0`, `eno1`, `eth0` …). It should say
   `state UP` and have an `inet 192.168.x.x/24` line.
3. Check that you can reach the internet:

   ```bash
   ping -c 3 archlinux.org
   ```

   Three replies with a small `time=` value means it works. `Destination Host
   Unreachable` or no reply at all means it does not (see step 7).

If the cable is in but there is no address, ask NetworkManager to retry:

```bash
nmcli device disconnect enp1s0 && nmcli device connect enp1s0
```

(replace `enp1s0` with your interface name from `ip a`).

## 2. Wi-Fi from the panel (the easy way)

1. Click the **Network** icon in the panel (the applet in the top bar; if the
   panel is not visible, open the launcher with `Super + D` and start
   **Network**).
2. Pick your network from the list.
3. Type the Wi-Fi password and press **Connect**.
4. The icon changes to the signal-strength bars when the connection is up.

From the launcher (`Super + D`) you can also start **Advanced Network
Configuration** for a full window with the same list.

## 3. Wi-Fi from the terminal

```bash
nmcli device wifi list
```

shows the networks in range, their signal strength and their security. Then:

```bash
nmcli device wifi connect "MyNetwork" password "my secret"
```

Quotes matter when the name or password contains a space. To join a network
that does not broadcast its name (hidden):

```bash
nmcli device wifi connect "HiddenName" password "my secret" hidden yes
```

If the machine has more than one Wi-Fi card, add `ifname wlan0`.

## 4. Wi-Fi from a menu (no typing of commands)

```bash
nmtui
```

Choose **Activate a connection**, pick the network with the arrow keys, press
Enter, type the password, then **Quit**. `nmtui` is also the fastest way to fix
things from a text console (`Ctrl + Alt + F2`) when the desktop will not start.

## 5. Check the connection

```bash
nmcli connection show --active     # which connection is in use
nmcli device show wlan0 | grep -E 'IP4|DNS'   # address and DNS servers
ip a                               # address on every interface
ping -c 3 1.1.1.1                  # is the network itself reachable?
ping -c 3 archlinux.org            # does name resolution work too?
```

`ping 1.1.1.1` working while `ping archlinux.org` fails is the classic sign of a
**DNS** problem, not a connection problem (see step 8).

## 6. A fixed (static) address

Only do this when you know the address your router expects. Either use the
graphical editor (Network settings → your connection → IPv4 → **Manual**), or:

```bash
nmcli connection modify "MyNetwork" \
  ipv4.method manual ipv4.addresses 192.168.1.50/24 \
  ipv4.gateway 192.168.1.1 ipv4.dns "192.168.1.1,1.1.1.1"
nmcli connection up "MyNetwork"
```

Back to automatic later:

```bash
nmcli connection modify "MyNetwork" ipv4.method auto
nmcli connection up "MyNetwork"
```

## 7. Nothing works? The short checklist

1. **Is the radio switched off?** Laptops have a Wi-Fi kill switch or `Fn` key:

   ```bash
   rfkill list          # "Soft blocked: yes" or "Hard blocked: yes"?
   sudo rfkill unblock all
   ```

   `Hard blocked: yes` means a physical switch is off — no command can undo that.
2. **Is NetworkManager running?**

   ```bash
   systemctl status NetworkManager
   sudo systemctl restart NetworkManager
   ```

   Restarting drops the connection for a few seconds and brings it back.
3. **Does the card exist at all?** `ip a` with no wireless interface, or
   `nmcli device status` saying `unmanaged`, usually means a missing driver or
   firmware (some Broadcom and Realtek cards). `lspci -k | grep -A3 Network`
   shows which driver is loaded.
4. **Is the password right?** Delete the saved profile and connect again — a
   wrong key is stored, not retried:

   ```bash
   nmcli connection delete "MyNetwork"
   nmcli device wifi connect "MyNetwork" password "my secret"
   ```
5. **Only some sites fail?** That is DNS:

   ```bash
   resolvectl status            # when systemd-resolved is running
   cat /etc/resolv.conf         # otherwise: NetworkManager writes it
   ```

   If `resolvectl status` says the resolver is not running, read
   `/etc/resolv.conf` instead; it should list nameservers. Setting DNS per
   connection: `nmcli connection modify "MyNetwork" ipv4.dns "1.1.1.1"` and
   `nmcli connection up "MyNetwork"`.
6. **Captive portal (hotel, airport, café):** open a browser and try any page;
   the portal appears instead of it. `nmcli connection modify "MyNetwork"
   ipv4.method auto` first if you had set it to manual.
7. **Everything looks fine but nothing loads?** Check the clock: a badly wrong
   date breaks HTTPS. `timedatectl` shows it; `sudo timedatectl set-ntp true`
   fixes it.

## 8. Connecting and disconnecting on purpose

```bash
nmcli radio wifi off        # turn Wi-Fi off (saves battery)
nmcli radio wifi on         # and back on
nmcli connection down "MyNetwork"
nmcli connection up "MyNetwork"
nmcli connection show       # every saved connection, not only active ones
```

`mhelp commands` has the same commands in one-line form, and `mhelp keys` lists
the desktop shortcuts.
