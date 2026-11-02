# ADR 0005 — Staged AGL bring-up

- **Status:** Accepted
- **Date:** 2026-11-01

## Context

A full AGL Flutter image build costs more than 300 GB and hours of compute.
Most early questions are about hardware, and can be answered without a custom
image:

- Does the DSI display come up?
- Does touch work?
- Does CAN work?
- Does the DAC work?
- Does A2DP work?

## Decision

| Stage | Image | What we do | Answers |
|---|---|---|---|
| 0 | Raspberry Pi OS | Hardware sanity and the HDMI fallback | Is the hardware OK? |
| 1 | Prebuilt **AGL Vimba Pi 5 Flutter** image | Edit `config.txt` overlays and sideload our binaries and Flutter bundle | Is AGL + hardware OK? |
| 2 | `meta-f250` custom image | Everything reproducible from the layer | Production |

## Consequences

- Stage 1 changes are manual and must be recorded in `docs/hardware/bench-log.md`,
  then folded into `meta-f250`.
- Binaries sideloaded in Stage 1 must match the image's libraries. Rust is
  cross-built for `aarch64-unknown-linux-gnu` against a compatible glibc, or
  built statically (musl). The Flutter bundle must target engine 3.38.3.
