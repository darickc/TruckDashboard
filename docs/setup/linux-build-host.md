# Linux build host for AGL / Yocto

Status: **requirements only.** Nothing has been built yet. The layer and build
configuration arrive in Phase 5 ([ADR-0004](../architecture/adr/0004-linux-build-host.md),
[ADR-0005](../architecture/adr/0005-staged-agl-bringup.md)).

## Why not the Mac

| Constraint | Detail |
|---|---|
| AGL's supported build hosts | Native Linux: Ubuntu, Fedora, openSUSE, CentOS, Debian ([AGL](https://docs.automotivelinux.org/en/master/01_Getting_Started/02_Building_AGL_Image/02_Preparing_Your_Build_Host/)) |
| Yocto 6.0's supported hosts | Ubuntu 22.04/24.04/26.04, Debian 11–13, Fedora 42/43, Alma/Rocky 8–9, openSUSE Leap 15.6/16.0, CentOS Stream 9 ([Yocto 6.0](https://docs.yoctoproject.org/6.0/ref-manual/system-requirements.html)). macOS is not supported |
| Disk | AGL wants **at least 300 GB** free for Flutter demo images. The development Mac had 146 GB free on 2026-11-01 |
| aarch64 hosts | Not documented by AGL. Treat an Apple Silicon Linux VM as an experiment |

## Recommended host

| Resource | Minimum | Comfortable |
|---|---|---|
| Architecture | x86_64 | x86_64 |
| OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| CPU | 8 cores | 16+ cores |
| RAM | 32 GB | 64 GB |
| Disk | 400 GB SSD | 1 TB NVMe (keeps the sstate and download caches across releases) |

Options:

1. **A spare PC** running Ubuntu 24.04. This is cheapest over time.
2. **An on-demand cloud VM**, for example 16 vCPU, 64 GB, a 500 GB SSD. Start
   it for a build, keep `sstate-cache` and `downloads` on a persistent volume,
   and stop it afterwards.
3. *(Experiment)* An aarch64 Ubuntu VM on the Mac (Lima, UTM or OrbStack), with
   the build directory on an external SSD. Unsupported. Record the results if
   you try it.

## What runs where

| Task | Mac | Linux build host | Pi 5 |
|---|---|---|---|
| Flutter UI development and tests | ✓ | | |
| Rust services (simulated) and tests | ✓ | ✓ | |
| Cross-compiling Rust for the Pi (aarch64) | ✓ (cargo-zigbuild or cross) | ✓ | |
| AGL / Yocto image build | | ✓ | |
| Stage-1 sideload onto the prebuilt AGL image | ✓ (`make deploy`) | ✓ | target |

## Host preparation (to be confirmed against AGL docs in Phase 5)

Follow AGL's "Preparing Your Build Host" page for the exact package list for
the release being built. The Phase 5 deliverable is `agl/scripts/setup-build-host.sh`,
which installs those packages so the steps are repeatable instead of copied by
hand from this page.
