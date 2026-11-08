# agl/ — the head unit on Automotive Grade Linux

Phase 5. Stage 1 of the bring-up ([ADR-0005](../docs/architecture/adr/0005-staged-agl-bringup.md)):
the prebuilt AGL Vimba Pi 5 Flutter image, plus our services and dashboard
copied onto it by `make deploy`. How to use it: [docs/setup/agl.md](../docs/setup/agl.md).

**Status:** Stage 1 runs on the Pi with AGL 22.0.1, the prebuilt image and
the one built from source **[BENCH]** (bench log, 2026-11-06 and 2026-11-07).
`make agl-test` covers the scripts and the layer in simulation.

| Path | What | Used by |
|---|---|---|
| `configurations/vimba.env` | The pinned release: image URL, SHA-256, engine version ([ADR-0001](../docs/architecture/adr/0001-agl-release.md)) | `make agl-image`, tests |
| `boot/config-f250.txt` | Lines appended to the image's `config.txt`: DSI panel, RTC charging, DAC8x (commented) | `stage1-setup.sh` |
| `rootfs/` | Files installed on the Pi at the same paths: systemd units, the networkd CAN override ([ADR-0015](../docs/architecture/adr/0015-agl-can-defaults.md)), the logind drop-in, `/etc/default/f250`, helper scripts | `stage1-setup.sh` |
| `flutter/config.toml` | flutter-auto window settings for the dashboard bundle | `stage1-setup.sh` |
| `scripts/stage1-setup.sh` | Runs on the Pi: apply, `--check`, `--restore-demo` | `make deploy` |
| `scripts/diagnose-display.sh` | Runs on the Pi (AGL or Raspberry Pi OS): display, touch, backlight evidence | by hand |
| `scripts/storage.sh` | Runs on the Pi as `f250-storage`: the data drive's `status`, and `format` (erases; asks first) | by hand ([agl.md](../docs/setup/agl.md#data-drive-nvme-hat-or-usb-ssd)) |
| `scripts/collect-logs.sh` | Runs on the Pi: journals, CAN state, setup check | `make logs` |
| `scripts/fetch-image.sh` | Runs on the Mac: download, verify and decompress the image | `make agl-image` |
| `scripts/setup-build-host.sh`, `scripts/agl-build.sh` | Run on the Linux build host: prepare it, then build `agl-f250` with `meta-f250` | `make build-vm`, `make agl-build` |
| `meta-f250/` | The Yocto layer (below) | `agl-build.sh` |

The layout on the Pi, and why: [ADR-0016](../docs/architecture/adr/0016-stage1-sideload-layout.md).

## meta-f250

[`meta-f250/`](meta-f250/README.md) is the Yocto layer for our own image
(Phase 5.4, [ADR-0017](../docs/architecture/adr/0017-meta-f250-layer.md)).
It builds `rootfs/`, `boot/` and `flutter/` into the image at the same paths,
so the same `stage1-setup.sh --check` applies. `make agl-build` builds it in
the build VM ([ADR-0004](../docs/architecture/adr/0004-linux-build-host.md)).
