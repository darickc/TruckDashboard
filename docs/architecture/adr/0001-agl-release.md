# ADR 0001 — Target AGL Vibrant Vimba 22.0.x

- **Status:** Accepted. Revisit before Phase 5 locks the image.
- **Date:** 2026-11-01

## Context

The owner asked whether Vibrant Vimba 22.0.0, believed to have been released in
October 2026, is still the right target. Research on 2026-11-01 found:

| Release | Finding | Status |
|---|---|---|
| **Vimba 22.0.0** | The announcement calls it "the latest stable release", built on Yocto 6.0 "Wrynose". The download directory is dated **18 Sep 2026**; the October date is only the announcement page's "last updated" stamp. [announcement][a] · [downloads][d] | Verified |
| Vimba Pi 5 build | `MACHINE = "raspberrypi5"`. Prebuilt `agl-ivi-demo-flutter-raspberrypi5.wic.zst` and `agl-ivi-demo-qt-…` images. Kernel 6.18.33. U-Boot. Flutter 3.38.3, flutter-auto 2.0, agl-compositor 0.0.24, applaunchd 2.0. [images][i] · [manifest][m] | Verified |
| **Unagi 21.0.x** | The previous release, 21.0.4 (Sep 2026). AGL's AMM Tokyo 2026 slides reportedly call it the LTS release, based on Scarthgap, with updates to 2028. The slide text was not read directly, and the release date conflicts with the summary. [slides][s] | Conflicting |
| Known Vimba issues | None specific to the Pi. SPEC-5607 (Flutter label alignment) and SPEC-5679 (Profiles button) affect the demo apps, not ours | Verified |

[a]: https://www.automotivelinux.org/blog/automotive-grade-linux-announces-vibrant-vimba-v22-0-0/
[d]: https://download.automotivelinux.org/AGL/release/vimba/
[i]: https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/deploy/images/raspberrypi5/
[m]: https://download.automotivelinux.org/AGL/release/vimba/22.0.0/raspberrypi5/deploy/images/raspberrypi5/agl-ivi-demo-flutter-raspberrypi5.manifest
[s]: https://hosted-files.sched.co/aglammjapan2026/23/AGL%20Update%20AMM%20Tokyo%20Miner.pdf

## Decision

Target **Vimba 22.0.x** and pin the exact point release and layer revisions in
`agl/configurations/`.

## Consequences

- Prebuilt Pi 5 images make it possible to bring up the hardware before any
  Yocto build (ADR-0005).
- The development Flutter SDK must match the image engine: **3.38.3** (`.fvmrc`).
- Vimba is not confirmed as LTS. Long-term maintenance means following
  22.0.x point releases, or moving to an LTS line later.

## Revisit when

- Before Phase 5:
  - check whether Unagi 21.0.x has Pi 5 images and an official LTS statement
  - check whether a Vimba point release exists
- If 22.0.x breaks something we rely on: the DSI display, CAN, A2DP or
  flutter-auto.
