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
| [0014](0014-multichannel-dac8x.md) | Multichannel DAC (HiFiBerry DAC8x), a new 4-channel amp, the R150-2 kept | Proposed (pending bench measurement) |
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

New ADRs use the next number and the same headings.
