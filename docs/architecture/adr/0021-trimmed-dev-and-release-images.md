# ADR 0021 — Trimmed images: development and release

- **Status:** Accepted (both images from 33d8324 pass their bench checks,
  [BENCH] 2026-11-08; the sandboxed units run on both, the release image
  from 0233cca)
- **Date:** 2026-11-08
- **Refines:** [ADR-0017](0017-meta-f250-layer.md)

## Context

`agl-f250` (ADR-0017) was AGL's Flutter demo image without its homescreen.
It boots and passes Stage 1's check (bench log, 2026-11-08). It still carries
the demo, and the development settings of `agl-devel`. Read in the 22.0.1 tree
on 2026-11-08:

- The demo image adds, on top of `agl-image-compositor` (meta-agl-core):
  - the KUKSA databroker and CAN provider, and the HVAC, radio and audio-mixer
    services that use it
  - Qt and MapLibre (the navigation demo)
  - gpsd, geoclue, oFono, rtl-sdr, mpd, flite and Open JTalk, the CJK fonts
  - applaunchd and its templates, the demo apps and the CAN simulator
- `agl-image-compositor` already gives:
  - boot and machine packages
  - connman (built with its `3g` option, so oFono comes along)
  - `agl-compositor` and `agl-users` (`agl-driver`)
- `agl-devel` is a distro feature set in `local.conf`. It changes images
  through `IMAGE_FEATURES`: `allow-empty-password`, `empty-root-password`,
  `allow-root-login`, `post-install-logging`, `tools-debug` and
  `tools-profile`. It also adds `packagegroup-agl-core-devel`, `libdrm-tests`
  and `weston-examples`. Below the image it changes only two things:
  `agl-compositor --debug`, and systemd's `coredump`.
- Without `allow-root-login`, OE leaves OpenSSH's default, `PermitRootLogin
  prohibit-password`. Without `empty-root-password`, it locks root's password
  (`zap_empty_root_password`).
- The dashboard has no fonts of its own; it draws with the system's sans,
  DejaVu.

## Decision

1. **Two images on one base** (`recipes-platform/images/agl-f250-base.inc`):
   `agl-image-compositor`, plus:
   - the Flutter compositor configuration
   - the boot splash
   - DejaVu fonts
   - BlueZ (the MX+ over RFCOMM)
   - avahi (`raspberrypi5.local`; the demo had it only through PipeWire)
   - rsync (`make deploy`)
   - our three packages

   None of the demo's software is installed. Each Phase 6 feature brings what
   it needs (PipeWire with the audio manager, gpsd with GPS).
2. **`agl-f250` is the development image**, for the bench. It has
   `agl-devel`'s tools, package management and an empty root password.
3. **`agl-f250-release` is the image for the truck.** It removes:
   - `agl-devel`'s image features and packages
   - package management
   - `screen` and `mc`

   Root's password is locked, and SSH takes root only with a key.
4. **Root's key is built in.** `build-vm.sh` copies the Mac's public key
   (`F250_SSH_KEY`, `~/.ssh/id_ed25519.pub`) into the VM. `agl-build.sh` points
   `F250_AUTHORIZED_KEYS` at it. Both images install it for root. The release
   image refuses to build without one. The key file is in the rootfs task's
   checksum, so a new key rebuilds the image.
5. **`agl-devel` stays a distro feature of the build.** Taking it out would
   rebuild nearly every recipe. So the release image still runs the compositor
   with `--debug` (a local Wayland debug protocol) and keeps core dumps.
   Revisit when there's a reason to run a second build directory.
6. **oFono stays installed but off.** connman's `3g` option pulls it in;
   the image build disables `ofono.service` (`systemctl disable` in a rootfs
   step: its package enables it on install, and OE's preset step runs
   enable-only), and `00-f250.preset` keeps a full preset from re-enabling it. Rebuilding connman without it
   would change the shared build for one idle daemon.
7. **`f250-system` declares the tools its scripts call**: `can-utils`,
   `usbutils`, `util-linux` (`blkid`, `lsblk`, `findmnt`) and
   `e2fsprogs-mke2fs`. Until now the demo happened to carry them.
8. **No kernel fragment and no udev rules yet.** `gs_usb`, `can-raw` and
   `can-isotp` are modules of the image's kernel, and both images install
   them (`kernel-modules`, from the Pi machine configuration). No code writes the backlight or reads GPIO yet.
   Each rule comes with the feature that needs it: backlight dimming in 6.7,
   the opto inputs with their wiring.
9. **`make build-vm CMD=image`** copies the newest images out of the VM to
   `build/agl/`, decompressed, named `<image>-<release>-<commit>.wic`.
10. **Each service runs in a sandbox** measured on the bench. On top of what
    Stage 1 had: no capabilities, systemd's `@system-service` call filter
    without `@privileged` and `@resources`, no namespaces, a hidden process
    list, no IP traffic beyond what the service needs. Per service:
    - gateway: devices limited to USB serial (`char-ttyUSB`), IP limited to
      localhost and private ranges (`tcp:` adapters)
    - recorder: also no network, no devices, its own user namespace
    - dashboard: had no sandbox at all. Now: the GPU only (`char-drm`), no
      network, the home read-only; it writes only to the state and cache
      directories systemd creates for it (`HOME` and `XDG_CACHE_HOME` point
      there). No `RemoveIPC=` and no `PrivateUsers=`: `agl-driver`
      also runs the compositor. The power-off helper (`ExecStopPost=+`) runs
      outside the sandbox.

    `systemd-analyze security`, before and after: gateway 6.8 → 1.6,
    recorder 5.3 → 0.2, dashboard 9.2 → 0.6 (2026-11-08, sim transport).

## Consequences

- The image is smaller and starts less. The demo's CAN units aren't
  installed at all. Their masks and the `00-f250.preset` stay as a guard,
  and `--check` accepts the units being absent.
- Anything the demo happened to provide that we relied on without knowing
  shows up on the bench. The trimmed image has to pass the same checks
  before it replaces the current one.
- The release image has no password login at all: a lost key means
  re-flashing. The development image stays for the bench.
- Audio, GPS and maps add their packages back when their phases land.
- connman keeps Bluetooth switched off (`[Bluetooth] Enable=false`; the
  controller is rfkill soft-blocked). Nothing in AGL's layers turns it on;
  the demo's settings app did that at run time, if anything. The MX+ over
  RFCOMM needs it on, and has never run on AGL. The CAN adapter
  (ADR-0012) doesn't need it.
- The gateway's sandbox has run with the simulator and with the `can`
  transport on vcan0 (bench-log 2026-11-08) and on the truck's bus
  (VERIFICATION_LOG 2026-11-08). The `obdlink` transports
  (serial, RFCOMM, TCP) may need a call or device the filter refuses. Each
  gets checked the first time it runs on AGL.
- A Phase 6 feature that needs a device or the network (cameras, audio,
  maps, the backlight) adds it to its unit's sandbox, with a new measurement.
