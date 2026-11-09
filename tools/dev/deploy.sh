#!/usr/bin/env bash
# `make deploy PI=<host>`: build the services and the dashboard for the Pi 5
# and install them on the AGL image (Stage 1 sideload, ADR-0005, Phase 5.5).
#
#   make deploy PI=agl-pi.local        # build, copy, run agl/scripts/stage1-setup.sh
#   make deploy-build                  # build only, into build/agl-arm64/
#   SKIP_BUILD=1 make deploy PI=...    # copy what build/agl-arm64/ already has
#
# PI is an SSH destination; the user defaults to root (the AGL image's only
# login with SSH). The build runs in an arm64 Docker container
# (tools/dev/docker/arm64-build.Dockerfile), so nothing is compiled on the Pi:
# the AGL image has no toolchain.
#
# What lands on the Pi:
#   /opt/f250/bin/              vehicle-gateway, recorder, obd-console, power-manager, f250-can, f250-storage
#   /opt/f250/share/agl/        this repo's agl/ (scripts, rootfs, boot config)
#   /opt/f250/share/data/       signal registry, warning rules, scenarios
#   /usr/share/flutter/f250_infotainment/<flutter>/release/
#                               flutter_assets, libapp.so, flutter-version
#
# Status: the build [SIM] (run on the Mac); the copy and setup not yet run
# against the AGL image.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

MODE="${1:-deploy}"          # deploy | build
PI="${PI:-}"
OUT=build/agl-arm64
IMAGE=f250-arm64-build
APP_ID=f250_infotainment
FLUTTER_VERSION="$(sed -n 's/.*"flutter": *"\([^"]*\)".*/\1/p' .fvmrc)"
RUST_TOOLCHAIN="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' rust-toolchain.toml)"
SOCK=/run/f250/vehicle.sock

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[[ -n "$FLUTTER_VERSION" ]] || die ".fvmrc has no flutter version"
[[ -n "$RUST_TOOLCHAIN" ]] || die "rust-toolchain.toml has no channel"
if [[ "$MODE" == deploy ]]; then
  [[ -n "$PI" ]] || die "usage: make deploy PI=<host>  (or make deploy-build)"
  [[ "$PI" == *@* ]] || PI="root@$PI"
fi

build() {
  command -v docker >/dev/null || die "docker not found (make setup)"
  docker info >/dev/null 2>&1 || die "Docker is not running: start Docker Desktop"
  say "Build image $IMAGE (Rust $RUST_TOOLCHAIN, Flutter $FLUTTER_VERSION; first run takes a while)"
  docker build -q --platform linux/arm64 -t "$IMAGE" \
    --build-arg RUST_TOOLCHAIN="$RUST_TOOLCHAIN" --build-arg FLUTTER_VERSION="$FLUTTER_VERSION" \
    -f tools/dev/docker/arm64-build.Dockerfile tools/dev/docker >/dev/null

  say "Build the services and the dashboard for aarch64"
  rm -rf "$OUT"; mkdir -p "$OUT"
  # The source is mounted read-only; Cargo's target, the pub cache and the
  # Flutter work tree live in volumes, so rebuilds are incremental and the
  # Mac's own build directories are never touched.
  docker run --rm --platform linux/arm64 \
    -v "$PWD":/src:ro -v "$PWD/$OUT":/out \
    -v f250-arm64-cargo:/usr/local/cargo/registry -v f250-arm64-target:/target \
    -v f250-arm64-pub:/root/.pub-cache -v f250-arm64-work:/work \
    -e CARGO_TARGET_DIR=/target -e FLUTTER_VERSION="$FLUTTER_VERSION" -e SOCK="$SOCK" \
    "$IMAGE" bash -euo pipefail -c '
      cd /src
      cargo build -q --release --locked -p vehicle-gateway --features rfcomm
      cargo build -q --release --locked -p recorder -p obd-console -p power-manager
      mkdir -p /out/bin
      cp /target/release/vehicle-gateway /target/release/recorder /target/release/obd-console /target/release/power-manager /out/bin/

      for d in apps/infotainment simulator/powerstroke; do
        mkdir -p "/work/$d"
        rsync -a --delete --exclude build/ --exclude .dart_tool/ "/src/$d/" "/work/$d/"
      done
      cd /work/apps/infotainment
      flutter pub get >/dev/null
      flutter build linux --release \
        --dart-define=VEHICLE_SOURCE=gateway --dart-define=GATEWAY=unix:$SOCK
      b=build/linux/arm64/release/bundle
      mkdir -p /out/bundle/lib /out/bundle/data
      cp "$b/lib/libapp.so" /out/bundle/lib/
      cp -r "$b/data/flutter_assets" /out/bundle/data/
      flutter --version --machine | sed -n "s/.*\"frameworkVersion\": *\"\([^\"]*\)\".*/\1/p" >/out/bundle/flutter-version
      [ "$(cat /out/bundle/flutter-version)" = "$FLUTTER_VERSION" ] \
        || { echo "built with Flutter $(cat /out/bundle/flutter-version), expected $FLUTTER_VERSION"; exit 1; }
    '
  say "Built into $OUT:"
  (cd "$OUT" && find . -type f -maxdepth 3 | sort | sed 's/^/  /')
  file "$OUT/bin/vehicle-gateway" "$OUT/bundle/lib/libapp.so" | sed 's/^/  /'
}

deploy() {
  local ver
  [[ -x "$OUT/bin/vehicle-gateway" && -f "$OUT/bundle/lib/libapp.so" ]] \
    || die "$OUT is incomplete: run without SKIP_BUILD, or make deploy-build"
  say "Check $PI"
  ver="$(ssh "$PI" 'sed -n "s/^FLUTTER_VERSION=//p" /etc/default/flutter 2>/dev/null')" \
    || die "ssh $PI failed (docs/setup/agl.md: SSH)"
  [[ -n "$ver" ]] || die "$PI has no /etc/default/flutter: not the AGL Flutter image"
  [[ "$ver" == "$(cat "$OUT/bundle/flutter-version")" ]] \
    || die "$PI runs Flutter engine $ver; the bundle was built with $(cat "$OUT/bundle/flutter-version")"

  say "Copy to $PI"
  ssh "$PI" "mkdir -p /opt/f250/bin /opt/f250/share/agl /opt/f250/share/data /usr/share/flutter/$APP_ID/$ver/release"
  rsync -a "$OUT/bin/" "$PI:/opt/f250/bin/"
  rsync -a tools/pi/can.sh "$PI:/opt/f250/bin/f250-can"
  rsync -a agl/scripts/storage.sh "$PI:/opt/f250/bin/f250-storage"
  # The gateway's runtime data (agl/rootfs/opt/f250/libexec/gateway-start).
  rsync -a --delete shared/signals/ "$PI:/opt/f250/share/data/signals/"
  rsync -a --delete simulator/powerstroke/scenarios/ "$PI:/opt/f250/share/data/scenarios/"
  rsync -a apps/infotainment/assets/config/warning_rules.json "$PI:/opt/f250/share/data/"
  rsync -a --delete agl/ "$PI:/opt/f250/share/agl/"
  # --delete removes the engine links and config.toml; stage1-setup puts them back.
  rsync -a --delete "$OUT/bundle/" "$PI:/usr/share/flutter/$APP_ID/$ver/release/"

  say "Set up (agl/scripts/stage1-setup.sh)"
  ssh -t "$PI" /opt/f250/share/agl/scripts/stage1-setup.sh
}

case "$MODE" in
  build) build ;;
  deploy) [[ "${SKIP_BUILD:-0}" == 1 ]] || build; deploy ;;
  *) die "usage: $0 [deploy|build]" ;;
esac
