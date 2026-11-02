#!/usr/bin/env bash
# Install or check the macOS development toolchain. Safe to re-run.
#
# Installs with Homebrew: rustup, protobuf, buf, fvm. Then installs the Rust
# toolchain pinned in rust-toolchain.toml and the Flutter SDK pinned in .fvmrc
# (3.38.3, the engine version in the AGL Vimba 22.0.0 Pi 5 image).
# Only checks (never installs): Xcode, CocoaPods, PlatformIO, Docker.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN: %s\033[0m\n' "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || { echo "setup-macos.sh is for macOS; see docs/setup/"; exit 1; }
command -v brew >/dev/null || { echo "Homebrew is required: https://brew.sh"; exit 1; }

say "Homebrew packages"
for pkg in rustup protobuf buf fvm; do
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    echo "  $pkg: installed"
  else
    brew install "$pkg"
  fi
done

# Homebrew's rustup is keg-only; put its shims first for this script.
RUSTUP_BIN="$(brew --prefix rustup)/bin"
export PATH="$RUSTUP_BIN:$HOME/.cargo/bin:$PATH"

say "Rust toolchain (rust-toolchain.toml)"
rustup toolchain install   # reads rust-toolchain.toml
rustup show active-toolchain
rustc --version

say "Flutter SDK (.fvmrc)"
fvm install --skip-pub-get
fvm flutter --version

say "Checks"
if xcodebuild -version >/dev/null 2>&1; then
  xcodebuild -version | head -1
else
  warn "Xcode not found — needed for the Flutter macOS desktop target (Phase 2). Install from the App Store, then: sudo xcodebuild -runFirstLaunch"
fi
command -v pod >/dev/null || warn "CocoaPods not found — Flutter macOS plugins need it (brew install cocoapods)"
PIO="$(command -v pio || echo "$HOME/.platformio/penv/bin/pio")"
[[ -x "$PIO" ]] && echo "  PlatformIO: $("$PIO" --version)" || warn "PlatformIO not found — needed for firmware/esp32 (brew install platformio)"
command -v docker >/dev/null && echo "  Docker: $(docker --version)" || warn "Docker not found — needed for 'make linux-test'"

if ! grep -q "$RUSTUP_BIN" <<<"${SHELL_PATH_CHECK:-$(zsh -ic 'echo $PATH' 2>/dev/null || true)}"; then
  warn "Add rustup to your shell PATH:  echo 'export PATH=\"$RUSTUP_BIN:\$HOME/.cargo/bin:\$PATH\"' >> ~/.zshrc"
fi
say "Done. Next: make test"
