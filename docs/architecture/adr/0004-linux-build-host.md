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

## Consequences

- An extra machine or a cloud bill during Phase 5.
- ADR-0005 delays the need: the prebuilt image is used first.
- See [docs/setup/linux-build-host.md](../../setup/linux-build-host.md).
