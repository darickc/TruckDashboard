# ADR 0004 — Yocto builds on a Linux x86_64 host

- **Status:** Accepted
- **Date:** 2026-11-01

## Context

| Source | Requirement | Status |
|---|---|---|
| AGL | A native Linux host (Ubuntu, Fedora, openSUSE, CentOS or Debian). At least 100 GB free, and **at least 300 GB for Flutter demo images**. [AGL host prep][h] | Verified |
| Yocto 6.0 | Supported hosts: Ubuntu 22.04/24.04/26.04, Debian 11–13, Fedora 42/43, and others. At least 140 GB disk. 32 GB RAM given as an example. [Yocto 6.0 requirements][y] | Verified |
| aarch64 build hosts | Not documented by AGL | Unverified |
| macOS | Not a build host | — |

The development Mac is an Apple M4 Max with 64 GB RAM and **146 GB free**
(2026-11-01). It is not a supported Yocto host, and doesn't have the space.

[h]: https://docs.automotivelinux.org/en/master/01_Getting_Started/02_Building_AGL_Image/02_Preparing_Your_Build_Host/
[y]: https://docs.yoctoproject.org/6.0/ref-manual/system-requirements.html

## Decision

AGL and Yocto builds run on a **Linux x86_64 host**: a spare PC or an
on-demand cloud VM.

| Resource | Minimum |
|---|---|
| CPU | 8+ cores |
| RAM | 32 GB+ |
| Disk | 400 GB+ SSD |
| OS | Ubuntu 24.04 LTS |

Daily development stays on macOS. An aarch64 Ubuntu VM on the Mac (Lima, UTM or
OrbStack) with an external SSD is an **unsupported experiment** only.

## Amendment (2026-11-06): a VM on the Mac with an external drive

The owner added a 500 GB external drive ("External", reformatted APFS). It
turned out to be a 5,400 rpm laptop hard disk (Seagate ST9500325AS), which sets
the build time. The build
host is now tried as an **aarch64 Ubuntu 24.04 VM on the Mac** (Lima, Apple's
Virtualization framework) whose disk lives on that drive: 12 CPUs, 32 GiB RAM,
a 420 GiB sparse disk, a 16 GB swap file. `make build-vm` creates it and
`make agl-build` builds the pinned release in it
([linux-build-host.md](../../setup/linux-build-host.md)).

| Check | Result |
|---|---|
| VM created, host packages installed | Ran on the Mac |
| AGL 22.0.1 layers fetched from `vimba_22.0.1.xml` at tag `vimba/22.0.1` | Ran on the Mac. `code.qt.io` was unreachable, so `meta-qt6` came from a GitHub mirror at the same pinned commit |
| BitBake parses and passes its host sanity checks with `BUILD_SYS = aarch64-linux` | Ran on the Mac (3,659 recipes, 0 errors) |
| A full `agl-ivi-demo-flutter` build completes | **Yes**, 2026-11-07: all 13,261 tasks, about 12¾ hours of BitBake over two runs, no aarch64-specific failures. Kernel 6.18.33-v8-16k and Flutter 3.38.3, as in the prebuilt image ([bench-log.md](../../hardware/bench-log.md)) |
| The built image boots on the Pi | **Not yet** |

aarch64 build hosts are still not documented by AGL, and AGL's public sstate
mirror holds x86_64-host objects that this host can't reuse, so every build
from scratch compiles everything. The first build shows that the VM works as
the build host; it stays the build host unless the image fails to boot for a
reason tied to the host.

## Consequences

- An extra machine or a cloud bill during Phase 5.
- ADR-0005 delays the need: the prebuilt image is used first.
- See [docs/setup/linux-build-host.md](../../setup/linux-build-host.md).
