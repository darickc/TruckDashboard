# ADR 0009 — Camera rendering chosen by a measured spike

- **Status:** Proposed. Decided in Phase 6 after measurement.
- **Date:** 2026-11-01

## Context

Critical engine alerts must stay visible on every screen, including a
full-screen reverse camera. On AGL there are two credible ways to show video:

- a Flutter texture fed by GStreamer
- a separate GStreamer `waylandsink` surface raised through agl-compositor's
  `agl-shell` roles

GStreamer 1.28.2 with V4L2 ships in the image (verified). Flutter video and
texture plugin support on flutter-auto is unverified.

## Decision

Build both on the Pi 5 with one UVC camera. Measure:

- glass-to-glass latency (LED and phone-camera method)
- CPU and GPU load
- startup time
- whether alerts stay visible

Pick the option that keeps alerts visible with latency the owner accepts. The
camera *policy* (reverse priority, debounce, restore the previous screen) is
independent of this decision and is implemented first.

## Consequences

The camera UI may stay simulated until Phase 6 measures this.
