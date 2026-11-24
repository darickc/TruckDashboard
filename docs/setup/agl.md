# AGL on the Pi 5: Stage 1 (prebuilt image plus our services)

Phase 5.2–5.5, [ADR-0005](../architecture/adr/0005-staged-agl-bringup.md)
Stage 1. Flash the pinned AGL image, then `make deploy` installs our gateway,
recorder and dashboard on it. No Yocto build.

> **Status (2026-11-06):** sections 2–5 work on the Pi with AGL 22.0.1
> **[BENCH]**: flashing, `make deploy`, `--check`, and every bring-up check
> that needs no extra hardware (1–9; [bench-log](../hardware/bench-log.md)).
> Check 11 and the data drive ran on 2026-11-11 with the NVMe HAT; check 10
> on 2026-11-15 with the DAC (a RaspiAudio 8xOUT). Not run yet: the fallback
> procedure in section 6. Record each step that works
> on the Pi in the bench log.
>
> **2026-11-09 (image 288d091):** check 13 (power key) passes **[BENCH]**, and
> check 12's Bluetooth half does: powered, not discoverable. Pairing the MX+
> still waits for 12 V on its OBD pins ([bench-log](../hardware/bench-log.md)).

> **⚠ Vehicle bus:** the stock AGL image puts any CAN interface in normal mode
> at 500 kbit/s, so the adapter would ACK on the truck's bus, and it runs a
> CAN provider on `can0` ([ADR-0015](../architecture/adr/0015-agl-can-defaults.md)).
> **Keep the CAN adapter unplugged until `make deploy` has run and
> `stage1-setup.sh --check` passes.**

| What | Where |
|---|---|
| Release pin | [`agl/configurations/vimba.env`](../../agl/configurations/vimba.env): Vimba 22.0.1, Flutter engine 3.38.3 |
| Boot config we add | [`agl/boot/config-f250.txt`](../../agl/boot/config-f250.txt) |
| Files installed on the Pi | [`agl/rootfs/`](../../agl/rootfs/) |
| Setup, check, undo | [`agl/scripts/stage1-setup.sh`](../../agl/scripts/stage1-setup.sh) |
| Layout and users | [ADR-0016](../architecture/adr/0016-stage1-sideload-layout.md) |

## 1. What you need

- **A second microSD card, 16 GB or larger.** The image is 8.05 GB once
  decompressed. Keep the Raspberry Pi OS card as it is: it is the fallback
  ([section 6](#6-fallback-is-it-the-hardware-or-agl)).
- Ethernet to the Pi for the first boot (the image gets an address by DHCP
  through connman). Wi-Fi setup on AGL is not covered here.
- Optional: an HDMI monitor on HDMI0. AGL's own `config.txt` doesn't turn the
  7" panel on; our boot config does, after the first deploy.
- On the Mac: Docker Desktop running (`make deploy-build` uses it) and `zstd`
  (`brew install zstd`).

## 2. Download and flash

```bash
make agl-image
```

This downloads the image (1.3 GB) into `build/agl/`, checks its SHA-256
against the pin, and decompresses it to `build/agl/agl-ivi-demo-flutter-raspberrypi5.wic`.
It never writes to a disk.

Flash the `.wic` with **Raspberry Pi Imager**: *Choose OS → Use custom*, pick
the `.wic`, choose the new card, and **skip OS customisation** (it is for
Raspberry Pi OS). A `.wic` is a raw disk image like an `.img`; if Imager
doesn't list it, rename it to `.img`.

Command-line alternative: find the card with `diskutil list` (check its size
twice; `dd` overwrites whatever disk you name), then `diskutil unmountDisk
/dev/diskN` and `sudo dd if=build/agl/agl-ivi-demo-flutter-raspberrypi5.wic of=/dev/rdiskN bs=4m`.

**An image you built** (meta-f250, [linux-build-host.md](linux-build-host.md)):
`make build-vm CMD=image` copies the newest builds into `build/agl/` as
`agl-f250-<release>-<commit>.wic` (development) and
`agl-f250-release-<release>-<commit>.wic` (release: root logs in only with the
key it was built with, [ADR-0021](../architecture/adr/0021-trimmed-dev-and-release-images.md)).
Flash either one the same way. It already has the services, the dashboard and
Stage 1's settings, so skip section 4: after the first boot (which grows
root to fill the card, [ADR-0022](../architecture/adr/0022-grow-root-on-first-boot.md)),
`/opt/f250/share/agl/scripts/stage1-setup.sh --check` passes with nothing
deployed **[BENCH]** (bench-log 2026-11-08). `make deploy` updates it in
place **[BENCH]** (2026-11-09); it reruns `stage1-setup.sh` over the image's
files.

## 3. First boot and SSH

1. CAN adapter **unplugged**. Card in, Ethernet in, power on.
   **The 7" panel stays dark on this first boot:** the stock image's
   `config.txt` doesn't load the DSI overlay; our block adds it at deploy. The
   green ACT LED flickering means it's booting. A monitor on HDMI0 should show
   the AGL demo (UNVERIFIED).
2. Find the Pi. The image has avahi and answers as `raspberrypi5.local`
   (seen on both the prebuilt and the source-built image). Otherwise look in
   the router's DHCP list. A re-flashed card has a new host key: clear the old
   one with `ssh-keygen -R raspberrypi5.local`.
3. `ssh root@raspberrypi5.local`. The AGL development image has an **empty
   root password**: press Enter. Put your key on it so `make deploy` doesn't
   ask each time:
   ```bash
   ssh root@raspberrypi5.local 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys' < ~/.ssh/id_ed25519.pub
   ```
   Not `ssh-copy-id`: with no root password, its first test login succeeds
   and then waits at a shell, so it hangs (Ctrl-C gets out; bench log
   2026-11-07).
   This image is for the bench. It is not locked down. Our own release image,
   `agl-f250-release`, is: root's password is locked and SSH takes only the
   key built into it ([ADR-0021](../architecture/adr/0021-trimmed-dev-and-release-images.md),
   [linux-build-host.md](linux-build-host.md)).
   On their first boot, our images grow root to fill the card
   ([ADR-0022](../architecture/adr/0022-grow-root-on-first-boot.md);
   `systemctl status f250-grow-root`, `df -h /`). The stock image doesn't.
4. Before deploying, look at the image as it comes (bench-log entry):
   `cat /etc/os-release`, `uname -r`, `cat /etc/default/flutter`,
   `systemctl is-enabled systemd-networkd kuksa-can-provider can-dev-helper`.

## 4. Deploy

```bash
make deploy PI=raspberrypi5.local
```

1. Builds the gateway, recorder and `obd-console` for aarch64, and the
   dashboard's AOT bundle with Flutter 3.38.3, in an arm64 container. The
   first run builds the container and takes a while. The output goes to
   `build/agl-arm64/`.
2. Refuses a Pi whose Flutter engine (from `/etc/default/flutter`) isn't the
   version the bundle was built with.
3. Copies everything to the Pi ([ADR-0016](../architecture/adr/0016-stage1-sideload-layout.md)):
   `/opt/f250/bin/`, `/opt/f250/share/{agl,data}/`, and the bundle in
   `/usr/share/flutter/f250_infotainment/3.38.3/release/`.
4. Runs `stage1-setup.sh` on the Pi. CAN safety comes first: it masks the KUKSA
   CAN units, installs the networkd override, and takes `can0` down if it is up
   in normal mode. Then it appends our block to `config.txt`, adds the `f250`
   user, installs the units, swaps the demo homescreen for the dashboard, and
   starts the services.

Then **reboot** (`ssh root@raspberrypi5.local reboot`), since `config.txt` and
the logind change apply at boot, and check:

```bash
ssh root@raspberrypi5.local /opt/f250/share/agl/scripts/stage1-setup.sh --check
```

Later deploys: `make deploy PI=…` again; it is idempotent.
`SKIP_BUILD=1` reuses the last build. Your settings in `/etc/default/f250` are
never overwritten.

## 5. Bring-up checks (Phase 5.2)

Each line is a bench-log entry when it passes. Mark results **[BENCH]**.

| # | Check | How | Answers |
|---|---|---|---|
| 1 | CAN safety | `stage1-setup.sh --check`: both KUKSA units masked, override in place, `can0` absent or down | ADR-0015 |
| 2 | Display | Picture on the 7" panel after the reboot. If not: [section 6](#6-fallback-is-it-the-hardware-or-agl) | — |
| 3 | Touch | Tap a Home button, then **Back** at the top left | ADR-0034 |
| 4 | Backlight | `cat /sys/class/backlight/*/max_brightness`; write a lower value to `brightness` and back | Phase 6.7 dimming |
| 5 | Dashboard | Runs fullscreen at 800×480, shows the simulator's data with the SIMULATED badge. `journalctl -u f250-dashboard -b` | H30 |
| 6 | Gateway and recorder | `systemctl status f250-gateway f250-recorder`; `obd-console` (finds the AGL socket itself), then `pids`, shows live values; `ls -l /var/lib/f250/` | — |
| 7 | Power and Restart | Dashboard *Settings → Power* → the Pi powers off cleanly (`journalctl -b -1 -u f250-dashboard` after the next boot shows "power off: requested"; the journal is kept on the SD card since 2026-11-06). *Settings → Restart* → the Pi reboots and the dashboard comes back (`journalctl -b -1 -u f250-dashboard` shows "restart: requested") | ADR-0016, ADR-0034 |
| 8 | CAN, listen-only | Plug in the adapter, then `f250-can status` (still down), `f250-can listen`, `ip -details link show can0` shows `LISTEN-ONLY`. With a second node on a bench bus: no ACKs | H7 on the AGL kernel |
| 9 | RTC | `ls /sys/class/rtc/`, `hwclock -r`. `dtparam=rtc_bbat_vchg=3000000` is on in `agl/boot/config-f250.txt` (the official rechargeable cell is fitted; comment it out before fitting any primary cell such as a CR2032): `cat /sys/class/rtc/rtc0/charging_voltage` shows 3000000, `battery_voltage` about 2.7–3.0 V, and `journalctl -b -k \| grep rpi-rtc` shows "trickle charging enabled" and the clock set from the RTC | H20 on AGL |
| 10 | Audio (the DAC fitted directly on the header, not over another HAT) | The RaspiAudio 8xOUT's EEPROM loads `hifiberry-dac8x` itself (a board without one: uncomment it in `agl/boot/config-f250.txt`). `cat /proc/asound/cards` lists `snd_rpi_hifiberry_dac8x` (the image has no `aplay`); `wpctl status` shows "Built-in Audio Pro" as the sink (`62-f250-dac.conf` picks the pro-audio profile), and `pw-link -l` shows `f250.speakers.out` on its `playback_AUX0`–`AUX7`. Done `[BENCH]` 2026-11-15. Then check 21 | ADR-0014 on AGL |
| 11 | NVMe (once the HAT is fitted) | `dtparam=pciex1` (on), deploy, reboot; `lspci` lists the drive's controller; `f250-storage status` shows `nvme0n1` and its health (no health until the image has `smartctl`). Passed on the bench 2026-11-11. Then [the data drive](#data-drive-nvme-hat-or-usb-ssd) | H31 |
| 12 | Bluetooth and the MX+ | After a reboot, `--check` has no Bluetooth warnings; `bluetoothctl show` says `Powered: yes`, `Discoverable: no`. Then [pair the MX+](#bluetooth-and-the-mx) and run `TRANSPORT=obdlink` in the gateway's sandbox | ADR-0023, ADR-0021 §10 |
| 13 | Power key ([power-manager](../architecture/power-states.md), pulse-only) | `journalctl -u f250-power-manager -b` shows "reading the power key on /dev/input/eventN". Press the Pi's power button within 30 s of power-on: "ignored: inside the boot window". Press it later: "power off: power key after the boot window", and the Pi halts cleanly (`journalctl -b -1` after the next boot). The DCDC-USB's PSW on J2 is the same press once it is wired (H21) | ADR-0013 |
| 14 | Camera ([camera-manager](../architecture/adr/0026-camera-manager-interfaces.md)) | Plug in a UVC webcam; `ls -l /dev/v4l/by-path/`; set `CAMERA_REAR=` to its `...-video-index0` path in `/etc/default/f250`; `systemctl restart f250-camera-manager`. `ls -l /run/f250-camera/` shows `camera.sock` as `agl-driver f250`, `srwxrwx---`. `camera-ctl move back`: the picture appears right of the camera buttons, below the status bar (x 220–800, y 44–479), and `camera-ctl view` says `rear (switch), live` within a second or two (if it never goes live while the picture moves, the frame count is wrong: ADR-0026 decision 3). `camera-ctl move press` closes it (forward is the front camera). `ls /var/cache/f250-camera/gstreamer-1.0/` has the registry. `journalctl -u f250-camera-manager -b` | ADR-0009, ADR-0026 |
| 15 | Day/night and the backlight ([power-manager](../architecture/adr/0028-day-night-and-backlight.md)) | After `make deploy`: `ls -l /sys/class/backlight/10-0045/brightness` is group `f250`, `-rw-rw-r--` (the udev rule); `ls -l /run/f250-power/` shows `power.sock` as `f250 f250`, `srwxrwx---`. `journalctl -u f250-power-manager -b` shows "display: backlight 10-0045 (max 255)" and, with no location set and no GPS fix, "auto unavailable (no GPS position, none configured)"; Settings → Display reads "Location: none · Clock: …". Dashboard → Settings → Display: **Night** dims the panel over about a second (`cat .../brightness` reads 102) and switches the palette; **Day** brings back 255; repeated −10 % stops at 26 (10 %). `systemctl restart f250-power-manager` keeps the choice (`cat /var/lib/f250-power/display`). Then set `DISPLAY_LATITUDE`/`DISPLAY_LONGITUDE`, join Wi-Fi so `timedatectl` says `System clock synchronized: yes`, choose **Auto**: the screen says "by the sun" with the elevation and "Location: configured (no GPS position yet) · Clock: synchronized". With a GPS receiver (H11): "Location: GPS", `/var/lib/f250-power/location` written once (`cat` it; it isn't rewritten while parked), and after a cold start with Wi-Fi off, "Clock: GPS time" (ADR-0028 amendment). Record `systemd-analyze security f250-power-manager` (ProtectKernelTunables is off) | ADR-0028 |
| 16 | Settings screen ([ADR-0029](../architecture/adr/0029-settings-screen.md)) | With a webcam plugged in: dashboard → Settings → Cameras lists it by USB port (and model), matching `camera-ctl settings` "plugged in" (if the list is empty while `ls /dev/v4l/by-path` isn't, the sandbox hides it). Give its port to Rear, **Apply**: `journalctl -u f250-camera-manager -b` shows "restarting to apply the saved settings" and the same PID (`systemctl show -p MainPID f250-camera-manager` before and after), no watchdog kill; the screen comes back "Set on this screen" within seconds; `cat /var/lib/f250-camera/settings`. The camera buttons show it as Rear. With a camera on screen, Apply is refused. **Use /etc/default/f250** removes the file. Settings → Units → Metric, reboot: still metric (`cat /var/lib/f250-dashboard/settings.json`) | ADR-0029 |
| 17 | Map stick ([ADR-0033](../architecture/adr/0033-map-updates-by-usb-stick.md)), once the data drive is in | On the Mac: `make map-region ...`, `make map-stick STICK=/Volumes/<name>` (an exFAT stick). Plug it into the Pi with the dashboard on: `systemctl list-units 'f250-map-import@*'` shows the import; the status bar shows **MAP n%**, then **MAP UPDATED**, and the Nav screen draws the new map without a restart. `cat /run/f250-maps/status.json`; `ls -l /var/lib/f250/storage/maps/`; `journalctl -u 'f250-map-import@*' -b` gives the copy and checksum times: record them. Pull a stick mid-copy: **MAP UPDATE FAILED**, the old map stays, no `.part` left. A music stick: nothing happens | ADR-0033 |
| 18 | Routing ([ADR-0035](../architecture/adr/0035-routing-with-valhalla.md)) | `valhalla_service --version` says 3.9.1. On the Mac: `make route-region REGION=<the map's region>`, `make map-stick STICK=/Volumes/<name> ROUTING=build/routing/valhalla_tiles.tar`; plug it in: "Routing data updated", and `/var/lib/f250/storage/routing/valhalla_tiles.tar` is there. Within a second the Nav screen says "Long-press the map to route"; long-press, **Route here**: a line, the next turn, and "Not checked for heavy vehicles or trailers". `journalctl -u f250-navigation -b` shows no Valhalla errors. With a receiver (or `NAV_SIMULATE=1`), drive off the route: a new one within 15 s | ADR-0035 |
| 19 | Recordings to a USB stick ([ADR-0037](../architecture/adr/0037-recordings-to-a-usb-stick.md)), with recordings on the data drive | `systemctl status f250-usb-export`; `ls -l /run/f250-export/` shows `export.sock` as `root f250`, `srwxrwx---`. Plug in an exFAT stick without map data: within 2 s `journalctl -u f250-usb-export -b` says "stick sda1 plugged in" then "export stick, n GB free"; `findmnt` shows nothing mounted (only in the unit's namespace, and only while checking or copying). Dashboard → Cameras → **Recordings to USB**: the list matches `ls /var/lib/f250/storage/video/*`; choose two, **Copy**: progress, then "Safe to unplug the stick". On a computer, `F250-recordings/front/...` plays and `cmp`s with the Pi's file. Copy the same again: "already there". Pull the stick mid-copy: "removed during the copy", no `.part` left on it after a replug. A map stick: "A map stick" and Copy refused; the map import still runs. A stick with the write-protect switch on, an NTFS stick: the reason on screen. Record the copy speed and `systemd-analyze security f250-usb-export` | ADR-0037 |
| 20 | Address search ([ADR-0038](../architecture/adr/0038-offline-address-search.md)) | On the Mac: `make search-region REGION=<the routing data's region>`, `make map-stick STICK=/Volumes/<name> SEARCH=build/search/search.sqlite`. Plug it in with the dashboard on: the Nav notice says "Copying search data", then "Search data updated"; `ls -l /var/lib/f250/storage/search/` shows `search.sqlite` `-rw-r--r--`. Nav → Search, type a street near the simulated loop: results within a second, each labelled ADDRESS/STREET/TOWN/PLACE, Route here routes. With a US region, a house number OSM lacks on a rural road comes back ESTIMATED with "Estimated from US Census address ranges", and the footer credits the Census ([ADR-0041](../architecture/adr/0041-us-census-address-ranges.md)). `journalctl -u f250-navigation -b` shows "search data: … (region; OSM data …)". Time it: `ssh -L 127.0.0.1:50299:/run/f250-nav/nav.sock`, then `cargo run -p navigation --example search -- tcp:127.0.0.1:50299 "main st"` on the Mac | FTS5 in the image's SQLite; search speed on the Pi |
| 21 | Bluetooth audio ([ADR-0039](../architecture/adr/0039-audio-manager.md)), after check 12 | `systemctl status pipewire wireplumber@audio wireplumber@bluetooth wireplumber@policy f250-audio-manager`; `ls -l /run/f250-audio/` shows `audio.sock` as `f250 f250`, `srwxrwx---`. `bluetoothctl show`: `Discoverable: no`, `Pairable: no`. Media → **Phones** → **Pair a phone**: `Discoverable: yes`; on the phone pick "F-250": the screen shows the phone's code, **Yes, it matches**: paired and trusted (`bluetoothctl info <addr>`), the window closes. Play music: title, artist, position, Play/Pause/Next/Previous; `pw-link -l` shows the phone → Multimedia loopback → `f250.speakers` → the default sink or DAC. Walk away with the phone: the track goes; come back: it reconnects. `bluetoothctl disconnect <addr>`: audio-manager reconnects the last phone by itself ("trying … every 20 s"). With two phones paired, Phones → **Connect** the other: the first is disconnected. Let a window run out; kill audio-manager with one open (BlueZ closes it). A spoken prompt over the music (navigation's directions, or `F250_AUDIO_RUN=/tmp /opt/f250/libexec/speak-prompt 'Test'` for the voice alone): the music stops at once, the phone pauses, and it resumes about 1 s after the prompt. With the DAC8x: its node name and positions (`pw-cli ls Node`, `pw-cli i <id>`), one test tone per jack to set `AUDIO_DAC_NODE` and `AUDIO_FRONT/REAR/SUB`, then Settings → Speakers live, and `pw-top` for xruns. Record `systemd-analyze security f250-audio-manager` | A2DP sink, AVRCP and the agent on AGL; the DAC8x's channel map |
| 22 | Saved places and spoken directions ([ADR-0040](../architecture/adr/0040-saved-places-and-spoken-directions.md)) | With `DATA_DRIVE=1` and the NVMe mounted: `journalctl -u f250-navigation -b` says "saved places in /var/lib/f250/storage/navigation/places.json (the data drive)" and "voice: the log only: …". Nav → long-press → **Save** → type a name → **Favourite**; `cat /var/lib/f250/storage/navigation/places.json` shows it. Places → **Route here**; the recent list gains it; restart `f250-navigation` and the places are still there. Corrupt the file (`echo x > …/places.json`), restart: the panel says it was kept as `places.json.bad`. With the route driven by the simulated receiver (`NAV_SIMULATE=1`), after check 21 (audio-manager and a phone playing music), the prompts are heard and the music pauses for each and resumes 1 s after the last; `journalctl -u f250-navigation` shows "voice: Turn right onto …" and nothing while the fix is lost (`--sim-outage-every-s`); **Muted** on the route's buttons stops them and survives a restart. `systemctl stop f250-audio-manager`: the toggle says "No audio" and prompts are logged as not said, not said later. Unmount the drive (or boot without it) with `DATA_DRIVE=1`: "the SD card: the data drive isn't mounted", places in `/var/lib/f250-nav/`. `systemd-analyze security f250-navigation` | The sandbox's StateDirectory and `ReadWritePaths` on the Pi; whether the drive check sees the NVMe's mount; that navigation reaches audio-manager's socket; how long the phone takes to pause |
| 23 | The phone's cover art ([ADR-0042](../architecture/adr/0042-cover-art-from-the-phone.md)), after check 21 | `systemctl status bluetooth f250-obexd`; `tr '\0' ' ' </proc/$(pidof bluetoothd)/cmdline` shows `--experimental`; `busctl --system status org.bluez.obex` shows obexd as user f250. Play music: `busctl --system introspect org.bluez /org/bluez/hci0/dev_XX/player0` lists `ObexPort`; `journalctl -u f250-audio-manager` says "cover art: BIP session to … open"; Media shows the track's picture, and Next the next one's (never the last one's). Note whether the first track after connecting had one. `ls -l /run/f250-obex/cover-art` (f250, 0600). A track without art shows the note and "No picture for this track". `systemctl restart f250-obexd` while playing: the next track's picture still arrives. `systemd-analyze security f250-obexd` | Whether the owner's iPhone offers cover art over AVRCP; whether the first track gets a handle; obexd's sandbox on the Pi |
| 24 | The volume and the knob ([ADR-0043](../architecture/adr/0043-master-volume-and-the-volume-knob.md)), after check 21 | Media: Volume + and − change the level and the speakers follow (a phone playing); Mute silences them and Volume + unmutes; `journalctl -u f250-audio-manager` shows no `pw-cli` failures. Set a level (say 22), wait 3 s and `reboot`: it comes back at 22 ("volume: starting at 22, as saved" in the log; `cat /var/lib/f250-audio/volume.json`), unmuted. With the chosen knob: [its events](#input-events) show `KEY_VOLUMEUP`/`KEY_VOLUMEDOWN`/`KEY_MUTE` or `REL_DIAL`; the log names it ("volume knob: …"); one step a detent, clockwise up (else `AUDIO_KNOB_INVERT=1`); a fast turn follows without lag; its play/pause (`KEY_PLAYPAUSE`) pauses and plays the phone. A spoken direction at a low level: heard, quiet; muted: silent | Which knob (owner); a GPIO encoder's overlay settings (`/boot/overlays/README` on the image); that the gain change is click-free |
| 25 | The knob display ([ADR-0044](../architecture/adr/0044-knob-display.md)), when the board is here | `lsusb` shows "F-250 knob" with a CDC and a HID interface (else turn the USB-C plug over); `ls /dev/serial/by-id/` has `*F-250_knob*`; [the events](#input-events) of its HID device show `KEY_VOLUMEUP`/`KEY_VOLUMEDOWN` a detent and `KEY_PLAYPAUSE`. `journalctl -u f250-knob-link`: "dial on …" and "dial: knob-display …"; the dial's `# frames:` lines count data frames and no bad checksums. The dial shows the simulated gateway's values, SIMULATED; `systemctl stop f250-gateway`: everything stale within 2 s, ages counting. Swipe left and right: gauges, navigation (the next turn with a route; "no data" within 3 s of `systemctl stop f250-navigation`), media (the phone's track and the volume); a swipe never plays or pauses. No `TAIJI_*` in a phone's Bluetooth list. Readable in daylight | Daylight at 600 cd/m² (the rest passed on the bench Pi, bench log 2026-11-22). Known: the plug way round that shows "F-250 knob"; no push switch on the schematic; the dial draws from knob-link's frames; the second ESP32 reflashed, no `TAIJI_*` |
| 26 | Wi-Fi from the dashboard and online navigation ([ADR-0052](../architecture/adr/0052-online-navigation-with-mapbox-and-wifi-settings.md)) | `systemctl status f250-network`; `journalctl -u f250-network -b` says "Wi-Fi from connman" and no "not allowed to talk to connman". Settings › System shows the Wi-Fi row with the current network; open it: the networks connman sees (`connmanctl services` agrees), **Scan** finds the phone's hotspot. Forget the hotspot, join it again with its passphrase on the keyboard: "Joined …", `connmanctl services` shows it `*AO`/`*AR`, and it rejoins after a reboot. A wrong passphrase says "Wrong passphrase". Wi-Fi off and on. Then the token (docs/setup/maps.md, Online navigation): `journalctl -u f250-navigation -b \| grep online` says Mapbox; the Nav screen shows Mapbox's map with its attribution; a route says "Mapbox route · live traffic"; turn the hotspot off: the map turns offline within a few tiles and the next reroute says "Offline route". `systemd-analyze security f250-network f250-navigation`. Remove `/etc/credstore/mapbox-token` and restart navigation: it still starts, offline | connman 2.0's D-Bus API and agent on the image; the D-Bus policy; `ImportCredential=` without the file; curl and its CA certificates under navigation's sandbox |

### Input events

For checks 24 and 25, and the 5-way switch: the image has no `evtest`, but
libinput's recorder names each event the same way (checked on image cb62346,
2026-11-14, bench-log). Find the device's `eventN` in
`/proc/bus/input/devices` (its `N: Name=` line, then `H: Handlers=`), then:

```bash
/usr/libexec/libinput/libinput-record /dev/input/eventN
```

It first lists what the device can send (`Event code 115 (KEY_VOLUMEUP)`), then
one line an event, `# EV_KEY / KEY_VOLUMEUP 1` for a press and `0` for the
release (`EV_REL / REL_DIAL` for a dial). Ctrl+C stops it. It doesn't grab the
device, so audio-manager and power-manager still act on each press while it
records.

Once installed in the truck, the [acceptance checklist](acceptance.md) checks
the whole system; the [troubleshooting guide](troubleshooting.md) goes by
symptom.

If something fails, collect the evidence before changing anything:

```bash
make logs PI=raspberrypi5.local
ssh root@raspberrypi5.local /opt/f250/share/agl/scripts/diagnose-display.sh
```

`make logs` copies an archive into `build/logs/`. `diagnose-display.sh` (for
display, touch and backlight problems) prints the archive's path on the Pi;
copy it with `scp`.

**Panel on, black, with a blinking cursor at the top:** that's the text
console, so the compositor isn't running. It restarts itself after a crash
(our drop-in), so look at why: `systemctl status agl-compositor`,
`coredumpctl list`. To bring the screen back:
`systemctl restart agl-compositor` (the dashboard comes back with it). Never
restart `f250-dashboard` on its own: agl-compositor 0.0.24 aborts when a
second homescreen app connects to it.

### Settings

`/etc/default/f250` has the same options as `make pi-run`:
`TRANSPORT=sim|obdlink|can`, `TRANSMIT=0|1`, `ADAPTER`, `CAN_IF`, `ENABLE`,
`BUDGET_RPS`, plus `DATA_DRIVE` ([below](#data-drive-nvme-hat-or-usb-ssd)) and the power-manager's
`BOOT_KEY_IGNORE_S`. Edit it on the Pi, then `systemctl restart f250-gateway` (or the service you changed). The
same rules as on Raspberry Pi OS apply: without `TRANSMIT=1` the gateway never
opens the adapter (ADR-0007), and `TRANSPORT=can TRANSMIT=1` needs
`f250-can active` first ([can.md](can.md)).

**Without a laptop** (ADR-0007 amendment, 2026-11-10): set
`CAN_AUTO_ACTIVE=1`. At every boot `f250-can-auto.service` puts `can0` in
listen-only mode. It switches to active only after hearing the truck's bus
cleanly for 3 s (at least 1000 frames, no errors; the truck sends ~712/s), and then restarts the
gateway. With the ignition off, or on the bench, it stays listen-only.
`CAN_AUTO_CAPTURE=1` also records every frame until shutdown in
`/var/lib/f250/captures`. See what it did with
`journalctl -u f250-can-auto -b`.

`f250-can` is `tools/pi/can.sh`; everything in [can.md](can.md) applies, run
as root on the Pi (no `sudo` on AGL). The firmware `flash` command needs
`dfu-util`, which the image doesn't have: flash from Raspberry Pi OS. The
truck session on AGL: [can.md, On the AGL image](can.md#on-the-agl-image).

### Wi-Fi: a phone hotspot

The images start with Wi-Fi off, and only Ethernet is configured. To reach
the Pi in the truck, join it to your phone's hotspot once, on the bench over
Ethernet, with the hotspot on. connman remembers the network and joins it on
later boots.

Needs an image built from e82719f or later. Before that, connman 2.0 lost
`wlan0` at boot on the Pi 5, and `scan wifi` answered "Not implemented"
(bench-log 2026-11-08).

```bash
ssh root@raspberrypi5.local
connmanctl enable wifi
connmanctl                       # interactive: the passphrase prompt needs it
```

```
connmanctl> agent on
connmanctl> scan wifi
connmanctl> services             # find the hotspot's wifi_..._psk name
connmanctl> connect wifi_<...>_managed_psk
Passphrase? <type it yourself>
connmanctl> quit
```

From an image with services/network (ADR-0052) the dashboard does the same:
**Settings › System › Wi-Fi** turns Wi-Fi on, lists the networks, and joins
one with the passphrase typed on the on-screen keyboard (connman keeps it).
On the bench Pi it joined the owner's hotspot (bench-log 2026-11-23);
`connmanctl` stays the fallback.

**WPA3-only networks can't be joined.** WPA3's handshake (SAE) through the
Pi 5's Wi-Fi driver times out on its firmware, and connman reported that as
"invalid-key": a correct passphrase was refused as "Wrong passphrase"
(bench-log 2026-11-23). `agl/rootfs/etc/modprobe.d/zz-f250-brcmfmac.conf`
turns that path off, so a mixed WPA2/WPA3 network joins over WPA2. A
WPA3-only network now ends in "Didn't connect within 60 s. A WPA3-only
network can't be joined…": set the router (or one of its networks) to
WPA2/WPA3 or WPA2. Phone hotspots are usually WPA2 or mixed.

A saved network that fails to rejoin by itself (connman left it in
`failure` with `connect-failed`) is tried again after 20 s, then after
longer waits up to 5 min (ADR-0052 decision 13); a wrong passphrase isn't.
`journalctl -u f250-network` shows "connman gave up joining … clearing it
so connman tries again".

Then `ip -br addr show wlan0` shows its address on the hotspot. Write it
down: if `raspberrypi5.local` doesn't resolve on the hotspot, SSH to that
address instead (the phone usually hands out the same one again). Your laptop
joins the same hotspot. The clock syncs over it too (connman's NTP), so
captures get real times.

### Bluetooth and the MX+

connman no longer manages Bluetooth; BlueZ powers the controller at boot
([ADR-0023](../architecture/adr/0023-bluetooth-belongs-to-bluez.md)). Needs an
image built with that change, or a Stage 1 card after `make deploy` and a
reboot. `connmanctl technologies` doesn't list Bluetooth any more: use
`bluetoothctl power on|off`. **[SIM] only so far:** none of this has run on
the Pi.

Pair the MX+ once from the Pi, as on Raspberry Pi OS. Disconnect the phone
and the ESP32 first. Keep the transcript for the bench log: which Secure
Simple Pairing variant BlueZ uses with the MX+ hasn't been recorded yet.

```bash
ssh root@raspberrypi5.local
bluetoothctl
# agent on / default-agent / scan on / pair 00:04:3E:85:EA:FC / trust 00:04:3E:85:EA:FC
```

Phones pair from the dashboard instead (Media → **Phones** → **Pair a phone**, check 21):
audio-manager's agent refuses pairing outside that window, but
`bluetoothctl` uses its own agent for what it starts, so pairing the MX+
from the Pi still works.

Confirm the passkey it shows; don't enter `1234`
([bench-log](../hardware/bench-log.md)). Then set `TRANSPORT=obdlink` in
`/etc/default/f250` and `systemctl restart f250-gateway`. Without
`TRANSMIT=1` the gateway doesn't open the adapter. The `obdlink` transports
haven't run in the gateway's sandbox yet (ADR-0021): if it can't connect,
look for a refused call or device in `journalctl -u f250-gateway -b`.

### Data drive (NVMe HAT or USB SSD)

The SD card still boots. The drive holds the telemetry database, the
gateway's traffic logs and the offline map (`maps/map.pmtiles`, put there by a
[map stick](maps.md#updating-the-map-in-the-truck-usb-stick)), later the
camera recordings, which would otherwise wear the card. Status: `[BENCH]`: on the
Pi 5 with a 500 GB NVMe on 2026-11-11, formatted with `f250-storage format`,
mounted at boot, the recorder, recordings, map and routing data on it
([bench-log](../hardware/bench-log.md)). Not yet with a USB SSD.

An NVMe HAT needs the Pi 5's external PCIe connector turned on:
`dtparam=pciex1` in `agl/boot/config-f250.txt`, on since the HAT was fitted
(2026-11-11). The 22.0.1 kernel has the NVMe and PCIe drivers built in. **A USB SSD
needs neither**, so it works with no HAT and no boot change.

1. NVMe: fit the HAT (see [H4](../hardware/open-questions.md): stacking with
   the DAC8x), deploy and reboot. USB SSD: plug it
   in. Then check that the drive is there:

   ```bash
   f250-storage status          # lsblk, lspci, the f250-data filesystem, smartctl health
   ```

2. Format it, once. This **erases the disk**; it asks you to type its name:

   ```bash
   f250-storage format /dev/nvme0n1
   ```

   One GPT partition, ext4, label `f250-data`. It refuses a partition, a disk
   with anything mounted, the disk the system runs from, and a second
   `f250-data` drive.
3. Turn it on: set `DATA_DRIVE=1` in `/etc/default/f250` (add the line if your
   file predates it), then:

   ```bash
   /opt/f250/share/agl/scripts/stage1-setup.sh
   ```

   It adds an `/etc/fstab` entry (`LABEL=f250-data`, `nofail`, a 10 s device
   wait) that mounts the drive at `/var/lib/f250/storage`, mounts it, and
   gives it to the `f250` user. `--check` then reports it.

   The mount hides whatever was already in `/var/lib/f250/storage` on the
   card: a map or routing data imported from a stick before the drive was on.
   Copy them onto the drive first (mount it somewhere else, `cp -a maps
   routing`, check the `.sha256` files), or import the stick again.

What happens without the drive while `DATA_DRIVE=1`:

- **Boot and the dashboard carry on.** `nofail` keeps the drive out of the
  boot path, and the gateway runs without it. Its traffic logs go to
  `/var/lib/f250/traffic` on the card, with a line in its journal.
- **The recorder stops instead of writing to the card.** A second database
  there would be split from the first, and the drive would hide it once
  mounted. `systemctl status f250-recorder` and `--check` show it.

The database already on the card (`/var/lib/f250/telemetry.sqlite`) stays
there; it isn't moved. `DATA_DRIVE=0` and the setup script remove the fstab
entry again (the drive stays mounted until a reboot).

**Booting from NVMe isn't possible with this image.** It boots through U-Boot,
and its boot script loads the kernel from the SD card's first partition
(`fatload mmc 0:1`). `cmdline.txt` also names the card (`root=/dev/mmcblk0p2`).
It would need our own image (5.4) and a U-Boot that drives the Pi 5's PCIe,
which is unconfirmed
([matrix](../hardware/compatibility-matrix.md#nvme-on-the-pi-5-agl-2201)).

## 6. Fallback: is it the hardware or AGL?

Phase 5.3. When the display, touch, CAN or audio fails on AGL, find out which
side the fault is on before changing anything. The Raspberry Pi OS card is the
known-good reference: the panel, touch and dashboard worked on it on
2026-11-02 ([bench-log](../hardware/bench-log.md)).

1. **Collect on AGL first:** `make logs PI=…` and `diagnose-display.sh` (above).
   Keep the archives.
2. **Swap to the Raspberry Pi OS card**, same Pi, same cables, nothing else
   changed, and run `agl/scripts/diagnose-display.sh` there too (the same
   script, from the repo).
3. Compare:

   | Raspberry Pi OS | AGL | Then |
   |---|---|---|
   | Works | Fails | **AGL side.** Compare the two archives: is the overlay applied (`drm-connectors.txt` has a DSI connector), are the modules loaded (`modules.txt`: `tc358762`, `edt_ft5x06`, `rpi_panel_attiny_regulator`), is the right I2C bus there (`i2c.txt`)? Check our block is in `config.txt` (`boot-config.txt`). Is the overlay on the ribbon's port? Our line is `dtoverlay=vc4-kms-dsi-7inch,dsi0` (CAM/DISP 0); drop `,dsi0` for CAM/DISP 1. `edt_ft5x06 … error -121` in `dmesg` means nothing answered on that port's I2C: the wrong port, or no panel power. The backlight driver doesn't check the panel is there, so `/sys/class/backlight` reading 255 proves nothing. Record the result in the [compatibility matrix](../hardware/compatibility-matrix.md) |
   | Fails | Fails | **Hardware or cabling.** Reseat the ribbon at both ends (contacts facing the right way), try the other DISP port, check the panel's 5 V. HDMI0 with a monitor tells whether the Pi itself boots and draws |
   | Works | Works | The fault was transient: note what changed (cables, power) in the bench log |

4. **Display dark, but you need the Pi:** plug HDMI0. Raspberry Pi OS's
   console uses it; AGL's compositor should too (UNVERIFIED).
   Over SSH, `stage1-setup.sh --restore-demo` brings the AGL demo homescreen
   back (to tell our dashboard apart from the platform). Undo our boot block by
   copying `config.txt.agl-orig` over `config.txt` on the boot partition
   (readable from the Mac, it's FAT).
5. **CAN:** the same comparison with `f250-can status` and `listen` on both
   cards. Same result on both points at the adapter or wiring
   ([can.md](can.md)); a difference points at the AGL kernel's `gs_usb` (H7).

## What's not here yet

- How to build the custom image (`agl/meta-f250`, the same layout as Stage 1):
  [linux-build-host.md](linux-build-host.md) and
  [ADR-0017](../architecture/adr/0017-meta-f250-layer.md).
- The hardware watchdog (`RuntimeWatchdogSec`, Phase 6.7 with the
  power-manager). The gateway and recorder already have systemd's service
  watchdog: `Type=notify`, `WatchdogSec=60` and `30`, keep-alives only while
  their loops make progress ([diagnostic-recovery.md](../architecture/diagnostic-recovery.md)).
- Booting from NVMe: see [the data drive](#data-drive-nvme-hat-or-usb-ssd).
- The rest of the power-manager: the hardware watchdog, and the dashboard's
  *Power* button becoming Restart. Day/night and the backlight are built
  [SIM] (check 15). It reads the
  5-way switch and passes long presses to camera-manager and short ones to
  audio-manager [SIM] (ADR-0051), but the switch isn't wired yet; `camera-ctl`
  stands in for it (check 14). Its first part
  handles the power key: after the boot window
  (`BOOT_KEY_IGNORE_S`, 30 s), pressing the Pi's button powers it off, as the
  DCDC-USB's PSW pulse will. The dashboard's *Power* button still shuts down
  too, until the DCDC-USB is installed (ADR-0013 decision 5).
