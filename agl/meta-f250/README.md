# meta-f250

The F-250 head unit as a Yocto layer on AGL 22.0.1 (Vimba), for
`MACHINE = "raspberrypi5"`. It builds two images on AGL's compositor image,
with the head unit's software and none of the demo's
([ADR-0021](../../docs/architecture/adr/0021-trimmed-dev-and-release-images.md)):

- `agl-f250`, for the bench: `agl-devel`'s tools, package management, and
  root with an empty password
- `agl-f250-release`, for the truck: root's password locked, SSH by key only,
  no debug tools or package manager

Status: `[BENCH]` 2026-11-08, the trimmed `agl-f250` built from 33d8324 boots
on the bench Pi and passes `stage1-setup.sh --check` with nothing sideloaded;
its services run sandboxed. `agl-f250-release` from the same commit boots
too, with root reachable only by the built-in key. See [ROADMAP 5.4](../../docs/ROADMAP.md) and the
[bench log](../../docs/hardware/bench-log.md). Design:
[ADR-0017](../../docs/architecture/adr/0017-meta-f250-layer.md),
[ADR-0021](../../docs/architecture/adr/0021-trimmed-dev-and-release-images.md).

## Build

```bash
make agl-build
```

`agl/scripts/agl-build.sh` adds this layer to the build, then builds
`agl-f250` and `agl-f250-release` from **this checkout's HEAD commit** (`F250_REPO`, `F250_SRCREV` in
`conf/site.conf`). It stops if the checkout has uncommitted changes, because
BitBake reads these recipes from the working tree.
[linux-build-host.md](../../docs/setup/linux-build-host.md) covers the build VM.

## What is in it

| File | Does | Stage 1 equivalent |
|---|---|---|
| `recipes-platform/images/agl-f250-base.inc` | `agl-image-compositor` plus the Flutter compositor config, DejaVu, BlueZ, rsync, the three packages below, and root's SSH key (`F250_AUTHORIZED_KEYS`) | the prebuilt image, minus the demo |
| `recipes-platform/images/agl-f250.bb`, `agl-f250-release.bb` | development (adds package management; `agl-devel` adds the rest) and release (removes `agl-devel`'s features and packages) | — |
| `recipes-f250/f250-system` | `agl/rootfs/` (units, drop-ins, `/etc/default/f250`, helpers), the `f250` user, the masked KUKSA CAN units, the enabled units, the persistent journal, `f250-can`, `f250-storage`, `/opt/f250/share/agl`, `/etc/f250-release` | `stage1-setup.sh` steps 1, 3, 4, 7 |
| `recipes-f250/f250-services` | `vehicle-gateway` (with RFCOMM), `recorder`, `obd-console` in `/opt/f250/bin`, the gateway's data in `/opt/f250/share/data`; the recorder links the image's `libsqlite3` (`make deploy` builds SQLite in) | `make deploy`'s Rust build |
| `recipes-f250/f250-dashboard` | `apps/infotainment` as a flutter-auto bundle in `/usr/share/flutter/f250_infotainment/3.38.3/release` | `make deploy`'s Flutter build, step 6 |
| `recipes-bsp/bootfiles/rpi-config_git.bbappend` | appends `agl/boot/config-f250.txt` to `config.txt` | step 2 |
| `recipes-config/agl-users/agl-users_%.bbappend` | `agl-driver` joins group `f250` (the gateway socket) | step 3 |
| `recipes-connectivity/connman/connman_%.bbappend` | patches connman 2.0 to read whole netlink messages; without it the Pi 5's 16 KiB-page kernel cut `wlan0` out of connman's startup link dump and Wi-Fi never came up after boot | — (the prebuilt image has the bug) |
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

Not here, on purpose (ADR-0021): a kernel config fragment (`gs_usb`,
`can-raw` and `can-isotp` are modules the images install) and udev rules
(nothing writes the backlight or reads GPIO yet; each rule comes with its
feature). The services' sandboxes are in their units under `agl/rootfs`
(ADR-0021 §10).
