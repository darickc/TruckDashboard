# meta-f250

The F-250 head unit as a Yocto layer on AGL 22.0.1 (Vimba), for
`MACHINE = "raspberrypi5"`. It builds the image `agl-f250`: AGL's Flutter demo
image with the head unit's software in place of the demo homescreen.

Status: written 2026-11-07; see [ROADMAP 5.4](../../docs/ROADMAP.md) and the
[bench log](../../docs/hardware/bench-log.md) for what has been built and
booted. Design: [ADR-0017](../../docs/architecture/adr/0017-meta-f250-layer.md).

## Build

```bash
make agl-build
```

`agl/scripts/agl-build.sh` adds this layer to the build, then builds
`agl-f250` from **this checkout's HEAD commit** (`F250_REPO`, `F250_SRCREV` in
`conf/site.conf`). It stops if the checkout has uncommitted changes, because
BitBake reads these recipes from the working tree.
[linux-build-host.md](../../docs/setup/linux-build-host.md) covers the build VM.

## What is in it

| File | Does | Stage 1 equivalent |
|---|---|---|
| `recipes-platform/images/agl-f250.bb` | `agl-ivi-demo-flutter` without `flutter-ics-homescreen`, plus the three packages below | the prebuilt image |
| `recipes-f250/f250-system` | `agl/rootfs/` (units, drop-ins, `/etc/default/f250`, helpers), the `f250` user, the masked KUKSA CAN units, the enabled units, the persistent journal, `f250-can`, `f250-storage`, `/opt/f250/share/agl`, `/etc/f250-release` | `stage1-setup.sh` steps 1, 3, 4, 7 |
| `recipes-f250/f250-services` | `vehicle-gateway` (with RFCOMM), `recorder`, `obd-console` in `/opt/f250/bin`, the gateway's data in `/opt/f250/share/data` | `make deploy`'s Rust build |
| `recipes-f250/f250-dashboard` | `apps/infotainment` as a flutter-auto bundle in `/usr/share/flutter/f250_infotainment/3.38.3/release` | `make deploy`'s Flutter build, step 6 |
| `recipes-bsp/bootfiles/rpi-config_git.bbappend` | appends `agl/boot/config-f250.txt` to `config.txt` | step 2 |
| `recipes-config/agl-users/agl-users_%.bbappend` | `agl-driver` joins group `f250` (the gateway socket) | step 3 |
| `files/f250-passwd`, `files/f250-group` | static IDs (AGL refuses dynamic ones): `f250` is 950 | — |

The paths are the Stage 1 paths ([ADR-0016](../../docs/architecture/adr/0016-stage1-sideload-layout.md)),
so `stage1-setup.sh --check` works on this image, and `make deploy` still
updates it in place for quick iterations.

## Keeping it in step

- After changing `Cargo.lock`, run `tools/dev/gen-crates-inc.py`: BitBake
  builds offline and needs every crate listed. `make agl-test` checks it.
- The workspace's `rust-version` is the AGL tree's Rust (1.96), so the
  services build with it.
- `make agl-test` also checks that the image enables every unit in
  `agl/rootfs` for the targets its `[Install]` names, and that this layer's
  `config.txt` step writes the same file as `stage1-setup.sh`.

Not here yet (ROADMAP 5.4): a kernel config fragment (none needed so far:
the USB CAN adapter's `gs_usb` is in the image's kernel), udev rules, unit
hardening beyond Stage 1's, trimming the demo apps, and turning off
`agl-devel` (the empty root password) before the truck.
