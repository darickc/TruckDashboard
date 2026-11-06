# agl/ — the head unit on Automotive Grade Linux

Phase 5. Stage 1 of the bring-up ([ADR-0005](../docs/architecture/adr/0005-staged-agl-bringup.md)):
the prebuilt AGL Vimba Pi 5 Flutter image, plus our services and dashboard
copied onto it by `make deploy`. How to use it: [docs/setup/agl.md](../docs/setup/agl.md).

**Status:** written and tested in simulation (`make agl-test`); nothing here
has run on the AGL image yet.

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

The layout on the Pi, and why: [ADR-0016](../docs/architecture/adr/0016-stage1-sideload-layout.md).

## Not here yet

- `meta-f250/`, the Yocto layer for our own image (Phase 5.4). It needs the
  Linux build host ([ADR-0004](../docs/architecture/adr/0004-linux-build-host.md)).
  It should install the files in `rootfs/` and `boot/` rather than copy them,
  and leave `kuksa-can-provider` and `can-dev-helper` out of the image.
