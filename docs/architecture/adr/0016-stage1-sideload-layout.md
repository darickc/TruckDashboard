# ADR 0016 — Stage 1 sideload: layout, users and the dashboard as the background surface

- **Status:** Proposed (written and tested in simulation; not run on the image)
- **Date:** 2026-11-06
- **Refines:** [ADR-0005](0005-staged-agl-bringup.md) Stage 1

## Context

Stage 1 runs our services and dashboard on the prebuilt Vimba Pi 5 Flutter
image, which has no compiler, before any Yocto build. Facts from the 22.0.1
image (manifest and layer sources, 2026-11-06):

- glibc 2.43, systemd 259, OpenSSH, rsync, bash; root login over SSH with an
  empty password (the `agl-devel` image features); SELinux in **permissive**
  mode (`agl-selinux.inc`).
- Flutter apps run under `flutter-auto` 2.0 with engine 3.38.3. A bundle lives
  in `/usr/share/flutter/<app>/<flutter version>/<runtime>/` with
  `data/flutter_assets`, `lib/libapp.so` (AOT), and links to the engine's
  `icudtl.dat` and `libflutter_engine.so` (meta-flutter's `flutter-app.inc`).
  `/etc/default/flutter` names the version and runtime.
- The demo homescreen, `flutter-ics-homescreen.service`, runs as `agl-driver`
  (uid 1001) with `XDG_RUNTIME_DIR=/run/user/1001/`, after `agl-compositor`,
  and its `config.toml` makes it the compositor's **background** surface
  (`window_type = "BG"`). Its layout is 1080×1920 portrait; our panel is
  800×480.

## Decision

1. **Build off the Pi.** `make deploy-build` builds in an arm64 Docker
   container on Debian bookworm (glibc 2.36, older than the image's, so the
   binaries run there) with the Flutter SDK from `.fvmrc`. The bundle's
   `libapp.so` and `flutter_assets` come from `flutter build linux`; the GTK
   runner it also builds is not used.
2. **Install under `/opt/f250`** (binaries, helpers, our `agl/` tree and the
   gateway's data), the bundle in the image's Flutter layout, and system
   configuration in `/etc`. Nothing in `/usr` except the bundle, so it never
   collides with an image package.
3. **Our dashboard replaces the demo homescreen** as the background surface:
   `f250-dashboard.service` mirrors the demo's unit (user, runtime dir,
   environment file, `flutter-auto -b`), with our `config.toml` (BG,
   800×480, fullscreen). The demo homescreen is disabled, not removed, so
   `stage1-setup.sh --restore-demo` brings it back.
4. **Services run as a system user `f250`**; the gateway's socket is
   `/run/f250/vehicle.sock`, group `f250`, mode 0770 (`UMask=0007`), and
   `agl-driver` joins the group. The gateway and recorder get systemd
   sandboxing (read-only system, no home, private `/tmp`, limited address
   families; the recorder also has no network or devices).
5. **The engine version is checked twice:** `make deploy` refuses a Pi whose
   `/etc/default/flutter` differs from the bundle's Flutter version, and
   `stage1-setup.sh` refuses a bundle built for another engine. An AOT
   snapshot runs only on the engine it was built for.
6. **The dashboard's Power button** keeps its contract (exit status 42):
   the unit treats 42 as success, and `ExecStopPost` (as root) powers off
   only on that status.

## Consequences

- Nothing is compiled on the Pi, and a deploy is minutes, not an image build.
- `meta-f250` (Phase 5.4) can install the same units and files; only the
  binary paths might move.
- Unverified until the first boot (open question H30): whether a `libapp.so`
  from `flutter build linux` runs under the image's `flutter-auto`, whether
  the compositor takes our app as its background surface with the app id
  `homescreen`, and whether `flutter-auto` honours the 800×480 size.
  If the BG route fails, the fallback is to install the app as an applaunchd
  app (`agl-app-flutter@f250_infotainment.service`) and launch it from the
  demo homescreen.
- The gateway reaches the MX+ over a raw RFCOMM socket (the `rfcomm` feature
  links no D-Bus library), so the `f250` user needs no BlueZ D-Bus policy.
  Not tested on AGL.

## Addendum 2026-11-06: the data drive

An NVMe HAT (or a USB SSD) holds the data that would wear the SD card
([agl.md](../../setup/agl.md#data-drive-nvme-hat-or-usb-ssd)):

- **Opt-in:** `DATA_DRIVE=1` in `/etc/default/f250`. `stage1-setup.sh` then
  writes one `/etc/fstab` entry, by filesystem label (`f250-data`), so no
  per-drive UUID is kept anywhere, with `nofail` and a 10 s device wait.
- **Mount point** `/var/lib/f250/storage`, inside the services' state
  directory. A mount at `/var/lib/f250` itself would make every unit with
  `StateDirectory=f250` require it (systemd's implicit `RequiresMountsFor=`),
  and the gateway with it.
- **Without the drive** the gateway runs (traffic logs fall back to the card,
  logged) and the recorder refuses to start. It never writes into the empty
  mount point, where the drive would hide the data later.
- Formatting is a separate, explicit command (`f250-storage format`), never
  part of setup or deploy.
- Booting from NVMe is out of Stage 1: the image's `boot.scr` loads the kernel
  from `mmc 0:1`.

## Revisit when

- Phase 5.4 builds `meta-f250`: fold this layout into recipes or replace it.
- The first boot answers H30.
