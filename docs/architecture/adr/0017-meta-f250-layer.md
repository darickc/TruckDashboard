# ADR 0017 — meta-f250: the Stage 1 layout, built into the image

- **Status:** Proposed (the layer parses in the build VM; not built or booted yet)
- **Date:** 2026-11-07
- **Refines:** [ADR-0005](0005-staged-agl-bringup.md) Stage 2, [ADR-0016](0016-stage1-sideload-layout.md)

## Context

Stage 1 runs on the prebuilt AGL 22.0.1 image and is checked on the Pi
(bench log, 2026-11-06). The build VM builds the same image from source, and
that image boots and runs Stage 1 too (bench log, 2026-11-07). Facts from the
22.0.1 tree, read in the VM on 2026-11-07:

- Rust is **1.96.1** (`meta-lts-mixins_rust`, `RUSTVERSION ?= "1.96.1%"`),
  with OE-core's `cargo` class: offline builds with `--frozen`, every crate
  listed in `SRC_URI` as `crate://` with its checksum. The workspace pinned
  `rust-version = "1.99"`, but builds and passes its tests on 1.96.1, and
  clippy's MSRV lint passes at 1.96.
- Flutter apps use meta-flutter's `flutter-app` class: pub fetches the Dart
  packages in a task with network access, and the bundle is installed in the
  layout Stage 1 already uses. The engine is 3.38.3.
- AGL builds with `useradd-staticids` and `USERADD_ERROR_DYNAMIC = "error"`:
  every user and group needs a fixed ID from a table.
- `agl-driver` is made by `agl-users`; the demo homescreen comes from the
  image's `AGL_APPS_INSTALL`.
- The source of truth for the services, dashboard and system files is this
  repository, and the VM sees the Mac's checkout read-only at the same path.

## Decision

1. **One layer, `agl/meta-f250`, in this repository.** Image `agl-f250` =
   `agl-ivi-demo-flutter` minus `flutter-ics-homescreen`, plus three packages:
   `f250-system` (`stage1-setup.sh`'s steps as files), `f250-services` (the
   Rust binaries and the gateway's data) and `f250-dashboard` (the Flutter
   bundle). `config.txt` and `agl-driver`'s group come from appends to
   `rpi-config` and `agl-users`.
2. **Same paths as Stage 1** (ADR-0016): `/opt/f250`, units and drop-ins in
   `/etc/systemd/system`, the bundle under `/usr/share/flutter`. So
   `stage1-setup.sh --check` validates either kind of image, `make deploy`
   still updates a built image in place, and `make agl-test` can check that
   the layer and the script agree (the units it enables, the `config.txt` it
   writes).
3. **Built from a commit.** The recipes fetch this repository with git, at
   the commit `agl-build.sh` writes into `site.conf` (`F250_SRCREV`, HEAD
   when the build starts). BitBake reads the recipes from the working tree,
   so the build refuses uncommitted changes. The image records the commit in
   `/etc/f250-release`.
4. **The AGL tree's Rust.** The workspace's `rust-version` drops to 1.96, so
   the services build with 1.96.1; development keeps `rust-toolchain.toml`.
   No meta-rust-bin. The crate list is generated from `Cargo.lock`
   (`tools/dev/gen-crates-inc.py`), because `bitbake -c update_crates` would
   write into the read-only layer. `make agl-test` fails if it is stale.
5. **The KUKSA CAN units are masked, not removed**, as Stage 1 does, so
   nothing that depends on them breaks. Removing them belongs to trimming the
   demo apps, after this image boots.
6. **Static ID 950** for the `f250` user and group, in the layer's own tables
   (`files/f250-passwd`, `files/f250-group`), appended to AGL's lists.

## Consequences

- One source for the head unit's files: `agl/rootfs` and `agl/boot` feed both
  Stage 1 and the image.
- A build needs a commit; quick experiments still go through `make deploy`.
- Changing `Cargo.lock` means regenerating the crate list.
- Rust newer than 1.96 can't be used in the workspace until AGL's tree moves.
- The image still carries the demo apps and `agl-devel` (empty root
  password). Both go before the truck (ROADMAP 5.4).
