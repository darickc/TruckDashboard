# Build environment for `make deploy` (Phase 5.5): the Rust services and the
# dashboard's Flutter bundle for the Pi 5 (aarch64 Linux), built natively in
# an arm64 container (fast on Apple Silicon; emulated on x86_64).
#
# Debian bookworm's glibc (2.36) is older than the AGL image's (2.43), so the
# binaries run there. camera-manager links GStreamer (libgstreamer-1.0.so.0,
# 1.22 here, 1.28 on the image: the same ABI, newer). The Flutter SDK is the one in .fvmrc, which must match
# the engine in the image (3.38.3, ADR-0001): an AOT snapshot (libapp.so)
# only runs on the engine it was built for.
FROM --platform=linux/arm64 rust:1-bookworm

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      protobuf-compiler libdbus-1-dev pkg-config \
      libgstreamer1.0-dev \
      clang cmake ninja-build libgtk-3-dev liblzma-dev \
      git curl unzip xz-utils rsync ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ARG RUST_TOOLCHAIN
RUN rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal \
 && rustup default "$RUST_TOOLCHAIN"

ARG FLUTTER_VERSION
ENV PATH=/opt/flutter/bin:$PATH
RUN git clone -q --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter \
 && git config --global --add safe.directory /opt/flutter \
 && flutter config --no-analytics --no-cli-animations >/dev/null \
 && flutter precache --linux --no-android --no-ios --no-web --no-macos --no-windows --no-fuchsia \
 && flutter --version
