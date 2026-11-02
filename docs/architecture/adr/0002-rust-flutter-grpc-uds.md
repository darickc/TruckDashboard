# ADR 0002 — Rust services, Flutter UI, gRPC over Unix domain sockets

- **Status:** Accepted
- **Date:** 2026-11-01

## Context

The owner prefers Rust for backend services, Flutter for the UI, and
protobuf/gRPC between them. The AGL Vimba Pi 5 image ships flutter-auto (Toyota
meta-flutter / ivi-homescreen) with Flutter 3.38.3. AGL's own applaunchd
already uses gRPC.

## Decision

- **Backend:** Rust (stable), with tokio, tonic/prost for gRPC, and rusqlite.
  SocketCAN goes through a socketcan crate behind `cfg(target_os = "linux")`.
- **UI:** Flutter, pinned to **3.38.3** to match the target engine. During
  development it runs as a macOS desktop app in an 800×480 window.
- **IPC:** gRPC over **Unix domain sockets** in `/run/f250/`, with a
  per-service socket group controlling access. Packages are named
  `f250.<domain>.v1`.
- **Codegen:** `buf` for linting and breaking-change checks. Generated Rust and
  Dart code is produced by `make proto` and is not hand-edited.

## Consequences

- The UI is decoupled from vehicle hardware and can be tested against
  simulated sources.
- The Dart gRPC client must support UDS on Linux. Dart's `InternetAddress` has
  a `unix` type. If the flutter-auto runtime blocks it, fall back to loopback
  TCP bound to 127.0.0.1 with a token.
- Two languages to maintain. Accepted for a good fit with each layer.
