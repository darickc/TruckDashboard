# ADR 0001 — Target AGL Vibrant Vimba 22.0.x

- **Status:** Accepted. Rechecked for Phase 5 on 2026-11-06: pinned to
  **22.0.1** ([below](#recheck-2026-11-06-phase-5)).
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

## Recheck 2026-11-06 (Phase 5)

| Question | Finding | Status |
|---|---|---|
| A Vimba point release? | **22.0.1**, directory dated 2026-11-02; the Pi 5 images are dated 2026-10-28. Same kernel (6.18.33), Flutter engine (3.38.3), flutter-auto (2.0) and agl-compositor (0.0.24) as 22.0.0. glibc 2.43, systemd 259. [22.0.1 images][i1] · [manifest][m1] | V |
| Unagi on the Pi 5? | 21.0.4 (2026-09-25) has a `raspberrypi5` build | V |
| Unagi LTS? | Still no official statement found beyond the AMM slides | C |

**Pinned:** Vimba 22.0.1, `agl-ivi-demo-flutter-raspberrypi5.wic.zst`, SHA-256
`7ee71bfc…0209`, in [`agl/configurations/vimba.env`](../../../agl/configurations/vimba.env).
`make agl-image` downloads and checks it.

The image's CAN defaults turned out to matter for safety:
[ADR-0015](0015-agl-can-defaults.md).

[i1]: https://download.automotivelinux.org/AGL/release/vimba/22.0.1/raspberrypi5/deploy/images/raspberrypi5/
[m1]: https://download.automotivelinux.org/AGL/release/vimba/22.0.1/raspberrypi5/deploy/images/raspberrypi5/agl-ivi-demo-flutter-raspberrypi5.manifest

## Revisit when

- On each Vimba point release: bump `agl/configurations/vimba.env`, recheck
  the engine version against `.fvmrc`, and recheck ADR-0015's recipes.
- Before Phase 5 (done 2026-11-06):
  - check whether Unagi 21.0.x has Pi 5 images and an official LTS statement
  - check whether a Vimba point release exists
- If 22.0.x breaks something we rely on: the DSI display, CAN, A2DP or
  flutter-auto.
