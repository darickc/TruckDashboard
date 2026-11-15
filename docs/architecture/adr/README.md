# Architecture decision records

Each ADR records one decision: its context, the decision itself, its
consequences, and what would make it worth revisiting. Statuses:

- `Accepted`
- `Proposed` (decided, but pending a measurement)
- `Superseded by NNNN`

| ADR | Title | Status |
|---|---|---|
| [0001](0001-agl-release.md) | Target AGL Vibrant Vimba 22.0.x (pinned: 22.0.1) | Accepted (rechecked 2026-11-06) |
| [0002](0002-rust-flutter-grpc-uds.md) | Rust services, Flutter UI, gRPC over Unix sockets | Accepted |
| [0003](0003-own-vehicle-api.md) | Own versioned vehicle API; KUKSA bridge optional | Accepted |
| [0004](0004-linux-build-host.md) | Yocto builds on a Linux x86_64 host | Accepted |
| [0005](0005-staged-agl-bringup.md) | Staged AGL bring-up | Accepted |
| [0006](0006-signal-registry-formula.md) | YAML signal registry with a safe formula grammar | Accepted |
| [0007](0007-read-only-vehicle-access.md) | Read-only vehicle access by default | Accepted |
| [0008](0008-crates-and-services.md) | Libraries in `crates/`, daemons in `services/` | Accepted |
| [0009](0009-camera-rendering.md) | Camera rendering chosen by a measured spike | Accepted |
| [0010](0010-offline-maps-routing.md) | flutter_map + offline tiles; Valhalla routing | Proposed |
| [0011](0011-mx-plus-trial-first.md) | MX+ truck trial before buying CAN hardware | Accepted |
| [0012](0012-direct-can-usb-adapter.md) | Direct CAN through a USB CANable adapter, with our own single-frame ISO-TP | Accepted |
| [0013](0013-dcdc-usb-power-supply.md) | Power from a mini-box DCDC-USB; the CarPiHAT is dropped | Proposed (pending bench measurement) |
| [0014](0014-multichannel-dac8x.md) | Multichannel DAC (HiFiBerry DAC8x; RaspiAudio 8xOUT bought, same driver), a new 4-channel amp, the R150-2 kept | Proposed (jacks identified on the bench; levels and pop pending) |
| [0015](0015-agl-can-defaults.md) | Override the AGL demo image's CAN defaults (networkd, KUKSA provider) | Accepted |
| [0016](0016-stage1-sideload-layout.md) | Stage 1 sideload: layout, users, the dashboard as the background surface | Proposed (not run on the image) |
| [0017](0017-meta-f250-layer.md) | meta-f250: the Stage 1 layout, built into the image | Accepted (built and booted 2026-11-08) |
| [0018](0018-computed-inputs-read-together.md) | Read a computed signal's inputs back to back | Accepted ([SIM] only) |
| [0019](0019-poll-intervals-budgeted.md) | Poll intervals budgeted from the measured link throughput | Accepted ([SIM] only) |
| [0020](0020-spare-budget-to-priority-0.md) | Priority 0 spends the spare link budget | Accepted ([SIM] only) |
| [0021](0021-trimmed-dev-and-release-images.md) | Trimmed images: development (`agl-f250`) and release (`agl-f250-release`) | Accepted (both images [BENCH] 2026-11-08) |
| [0022](0022-grow-root-on-first-boot.md) | Root fills the SD card on the first boot | Accepted ([BENCH] 2026-11-08) |
| [0023](0023-bluetooth-belongs-to-bluez.md) | Bluetooth belongs to BlueZ, not connman | Accepted ([SIM] only) |
| [0024](0024-camera-selection-switch-and-can-reverse.md) | Cameras: a 5-way switch picks the view, reverse comes from CAN; no opto board | Accepted (owner; reverse decoder not yet verified) |
| [0025](0025-camera-switch-through-gpio-key.md) | The camera switch is read through the kernel's `gpio-key` overlay | Accepted ([SIM] only) |
| [0026](0026-camera-manager-interfaces.md) | camera-manager runs one `gst-launch` pipeline at a time and serves `f250.camera.v1` | Accepted ([SIM] only) |
| [0027](0027-front-and-rear-recording.md) | Front and rear cameras record like a dashcam, kept by retention settings | Accepted (owner; nothing built or measured yet) |
| [0028](0028-day-night-and-backlight.md) | Day/night and the backlight belong to power-manager: the sun on a trusted clock, else a fallback | Accepted ([SIM] only) |
| [0029](0029-settings-screen.md) | A Settings tab; camera assignment and recording set through camera-manager | Accepted ([SIM] only) |
| [0030](0030-navigation-position-and-raster-map.md) | Position from gpsd through services/navigation; a raster PMTiles map | Accepted ([SIM] only) |
| [0031](0031-raster-map-build.md) | The raster map is built from a Protomaps extract, rendered locally by tileserver-gl | Accepted (built and checked on the Mac; not on the Pi) |
| [0032](0032-vector-map.md) | The dashboard draws vector maps itself (vector_map_tiles, bundled styles); vector is the default build | Accepted ([SIM] only; Pi speed unmeasured) |
| [0033](0033-map-updates-by-usb-stick.md) | Map updates by USB stick: the Pi copies, checks and swaps in the map on the data drive | Accepted (owner; [SIM] only) |
| [0034](0034-home-buttons-and-back.md) | Screens are reached from Home and left by Back; Power and Restart move to Settings | Accepted (owner; [SIM] only) |
| [0035](0035-routing-with-valhalla.md) | Routing with Valhalla, one `valhalla_service` per request, in services/navigation | Accepted ([SIM]; real Valhalla on the Mac; not on the Pi) |
| [0036](0036-clear-advisories.md) | Advisories can be cleared from the alert banner; critical alerts can't | Accepted (owner; [SIM], seen on the bench Pi) |
| [0037](0037-recordings-to-a-usb-stick.md) | Dashcam recordings are copied to a USB stick from the dashboard by `usb-export` (`f250.export.v1`); map sticks are left alone | Accepted (owner asked; [SIM] only) |
| [0038](0038-offline-address-search.md) | Offline address search: a SQLite FTS5 index of OSM addresses, streets, towns and places, on the map stick, served by navigation (`SearchService`) | Accepted ([SIM] only; not on the Pi) |
| [0039](0039-audio-manager.md) | audio-manager: Bluetooth A2DP sink and AVRCP through BlueZ and PipeWire, a pairing window opened from the dashboard with the code confirmed on screen, and the speakers' filter-chain as its own PipeWire client (`f250.audio.v1`) | Proposed ([SIM] only; not on the Pi) |
| [0040](0040-saved-places-and-spoken-directions.md) | Saved places (Home, favourites, recents) and spoken directions from Valhalla's words, in navigation (`PlacesService`, `SetVoice`); Flite the Pi's candidate engine; audio through audio-manager (ADR-0039) | Accepted ([SIM] only; not on the Pi, never heard there) |
| [0041](0041-us-census-address-ranges.md) | US Census TIGER/Line address ranges (ADDRFEAT 2026) in the search index: a house number OSM lacks is estimated along its street and labelled ESTIMATED | Accepted ([SIM] only; not on the Pi) |
| [0042](0042-cover-art-from-the-phone.md) | The phone's cover art on the Media screen: audio-manager fetches each track's thumbnail over AVRCP 1.6 BIP through obexd (system bus, user f250, client only); bluetoothd with `--experimental`; `GetCoverArt` | Accepted (owner asked; [SIM] only; not on the Pi) |
| [0043](0043-master-volume-and-the-volume-knob.md) | One master volume in audio-manager, a gain in the speakers' filter-chain (steps in dB, a cap, a start cap, mute, saved 2 s after a change), `SetVolume`; the knob as Linux input (volume keys, `REL_DIAL`) from any device; Media's buttons and a level shown on every screen | Accepted (owner asked; [SIM] only; not on the Pi; which knob is TODO) |
| [0044](0044-knob-display.md) | The knob display (Waveshare ESP32-S3 round touch screen with a knob): speed, fuel, EOT, ECT and EOT − ECT; one USB cable, a serial port for `services/knob-link`'s frames (from the gateway's snapshots) and a HID knob for audio-manager; `firmware/knob-display` | Accepted (owner asked; [SIM] only; no board yet, its drivers not written) |
| [0045](0045-phone-calls.md) | Phone calls (plan): hands-free through PipeWire 1.6.8's native backend and its Telephony D-Bus service on the system bus (no oFono), calls in audio-manager, WebRTC echo cancellation added back to PipeWire (in the image, its own unit), the microphone as configuration (no mic, no calls), call banners under the alert banner, the knob's push to answer; bench spikes S1–S4 first | Accepted for phases 1–2 [SIM]; S1 and S3 (echo cancellation) [BENCH] |
| [0046](0046-automatic-reverse.md) | Automatic reverse: the gateway reads the broadcast `230` receive-only (`WatchReverse`; unknown when stale, never "not engaged"), camera-manager follows it with `--auto-reverse` (`CAMERA_AUTO_REVERSE`, on with `TRANSPORT=can`) | Accepted (owner asked; [SIM]; not yet seen in the truck) |
| [0047](0047-head-unit-enclosure.md) | The head unit's enclosure: the display flush behind the radio opening on its own M3 holes, printed ASA rails and side brackets, a rear box for the electronics with a fan, the amplifier on its own bracket, a USB 2 hub only when more cameras come | Proposed (owner asked; design only, nothing printed or fitted) |

New ADRs use the next number and the same headings.
