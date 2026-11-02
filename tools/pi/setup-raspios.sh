#!/usr/bin/env bash
# Install or check the toolchain on the Raspberry Pi 5 for the MX+ trial
# (Phase 3.5.1). Run it on the Pi, from a clone of this repo. Safe to re-run.
#
# Installs with apt: build tools, protoc, libdbus (the gateway's RFCOMM
# feature) and Flutter's Linux desktop packages. Then installs the Rust
# toolchain pinned in rust-toolchain.toml (rustup) and the Flutter SDK pinned
# in .fvmrc (fvm). BlueZ ships with Raspberry Pi OS; it is only checked.
#
# Status: written on the Mac, not yet run on a Pi. Record the first run in
# docs/hardware/bench-log.md.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN: %s\033[0m\n' "$*"; }

[[ "$(uname -s)" == "Linux" ]] || { echo "setup-raspios.sh runs on the Pi; on the Mac use 'make setup'"; exit 1; }
[[ "$(uname -m)" == "aarch64" ]] || warn "expected aarch64 (64-bit Raspberry Pi OS), got $(uname -m)"
command -v apt-get >/dev/null || { echo "apt-get not found; this script expects Raspberry Pi OS"; exit 1; }
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "  OS: ${PRETTY_NAME:-unknown}"
fi
[[ -r /proc/device-tree/model ]] && echo "  Board: $(tr -d '\0' </proc/device-tree/model)"

say "apt packages"
# Flutter's Linux desktop list names libstdc++-12-dev; newer Debian releases
# ship a later version, so take the newest one available.
LIBSTDCXX="$(apt-cache search --names-only '^libstdc\+\+-[0-9]+-dev$' 2>/dev/null \
  | awk '{print $1}' | sort -V | tail -1)"
PKGS=(
  git curl unzip xz-utils zip build-essential pkg-config
  protobuf-compiler libdbus-1-dev                    # gateway (rfcomm feature)
  clang cmake ninja-build libgtk-3-dev liblzma-dev   # Flutter Linux desktop
  ${LIBSTDCXX:+"$LIBSTDCXX"}
)
sudo apt-get update -qq
sudo apt-get install -y "${PKGS[@]}"

say "Rust toolchain (rust-toolchain.toml)"
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v rustup >/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
fi
rustup toolchain install   # reads rust-toolchain.toml
rustc --version

say "Flutter SDK (.fvmrc)"
export PATH="$HOME/fvm/bin:$PATH"
if ! command -v fvm >/dev/null; then
  curl -fsSL https://fvm.app/install.sh | bash
fi
fvm install --skip-pub-get
fvm flutter --version

say "Checks"
if command -v bluetoothctl >/dev/null; then
  echo "  BlueZ: $(bluetoothctl --version)"
  systemctl is-active --quiet bluetooth && echo "  bluetooth.service: active" \
    || warn "bluetooth.service is not active: sudo systemctl enable --now bluetooth"
else
  warn "bluetoothctl not found; the MX+ trial needs BlueZ (sudo apt-get install bluez)"
fi
if [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
  echo "  No desktop session in this shell (normal over SSH); 'make pi-run' finds the one on the Pi's screen"
fi
grep -q "$HOME/fvm/bin" <<<"$(bash -ic 'echo $PATH' 2>/dev/null || true)" \
  || warn "Optional, for running fvm by hand: echo 'export PATH=\"\$HOME/fvm/bin:\$HOME/.cargo/bin:\$PATH\"' >> ~/.bashrc"
say "Done. Next: make pi-build, then make pi-run (docs/setup/raspberry-pi.md)"
