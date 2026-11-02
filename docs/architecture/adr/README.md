# Architecture decision records

Each ADR records one decision: its context, the decision itself, its
consequences, and what would make it worth revisiting. Statuses:

- `Accepted`
- `Proposed` (decided, but pending a measurement)
- `Superseded by NNNN`

| ADR | Title | Status |
|---|---|---|
| [0001](0001-agl-release.md) | Target AGL Vibrant Vimba 22.0.x | Accepted (revisit before Phase 5) |
| [0002](0002-rust-flutter-grpc-uds.md) | Rust services, Flutter UI, gRPC over Unix sockets | Accepted |
| [0003](0003-own-vehicle-api.md) | Own versioned vehicle API; KUKSA bridge optional | Accepted |
| [0004](0004-linux-build-host.md) | Yocto builds on a Linux x86_64 host | Accepted |
| [0005](0005-staged-agl-bringup.md) | Staged AGL bring-up | Accepted |
| [0006](0006-signal-registry-formula.md) | YAML signal registry with a safe formula grammar | Accepted |
| [0007](0007-read-only-vehicle-access.md) | Read-only vehicle access by default | Accepted |
| [0008](0008-crates-and-services.md) | Libraries in `crates/`, daemons in `services/` | Accepted |
| [0009](0009-camera-rendering.md) | Camera rendering chosen by a measured spike | Proposed |
| [0010](0010-offline-maps-routing.md) | flutter_map + offline tiles; Valhalla routing | Proposed |

New ADRs use the next number and the same headings.
