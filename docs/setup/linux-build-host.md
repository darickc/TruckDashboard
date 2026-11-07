# Linux build host for AGL / Yocto

Status: **first full build done `[BENCH]` 2026-11-07; the image has not been
booted yet.** `make build-vm` makes an Ubuntu 24.04 VM on the Mac with its disk
on an external drive, and `make agl-build` builds the pinned AGL release in it.
That arrangement is still outside what AGL documents (aarch64 host), so results
are recorded in
[bench-log.md](../hardware/bench-log.md) as they come
([ADR-0004](../architecture/adr/0004-linux-build-host.md),
[ADR-0005](../architecture/adr/0005-staged-agl-bringup.md)).

## Quick start (the Mac + an external drive)

The drive must be APFS (exFAT has no sparse files, symlinks or case-sensitive
names) and mounted at `/Volumes/External` (or set `BUILD_VOLUME`).

```bash
brew install lima
```

```bash
make build-vm
```

```bash
make agl-build
```

| Command | What it does |
|---|---|
| `make build-vm` | Create (once) and start the `agl-build` VM: Ubuntu 24.04 aarch64, 12 CPUs, 32 GiB RAM, a 420 GiB sparse disk. Everything Lima keeps lives in `/Volumes/External/lima`. Then runs `agl/scripts/setup-build-host.sh` in it |
| `make agl-build` | Runs `agl/scripts/agl-build.sh` in the VM: `repo` fetches AGL-repo's `vimba_<release>.xml` at the release tag, `aglsetup.sh -m raspberrypi5 agl-demo agl-devel`, then `bitbake agl-ivi-demo-flutter`. Log in `~/agl/logs/` in the VM |
| `make build-vm CMD=shell` | A shell in the VM. The repo is mounted read-only at the same path |
| `make build-vm CMD=status` | VM state, disk and memory |
| `make build-vm CMD=stop` | Stop the VM and free its RAM. Its disk stays on the drive |
| `make build-vm CMD=delete` | Delete the VM and everything built in it |

`VM_CPUS`, `VM_MEMORY` and `VM_DISK` size the VM when it is created.
`agl-build.sh` takes `FEATURES`, `TARGET`, `THREADS`, `JOBS` and `KEEP_WORK=1`
(see the script header). On a Linux PC, run the two `agl/scripts/` scripts
directly.

Settings the build adds (`conf/site.conf` in the build directory):

- `DL_DIR` and `SSTATE_DIR` outside the release tree (`~/agl/downloads`,
  `~/agl/sstate-cache`), so a later release or meta-f250 reuses them.
- `INHERIT += "rm_work"`, which deletes each recipe's work directory once it is
  built. This is the main disk saving.
- `PREMIRRORS` pointing at AGL's source mirror, as AGL's own release builds do
  (their `local.conf` is published next to each image).

Re-running `make agl-build` after a stop picks up where the build stopped:
the finished tasks are reused from `sstate-cache`. Once the layers are fetched,
it does not run `repo sync` again (`AGL_BUILD_ARGS=fetch` forces one).
`setup-build-host.sh` turns off Ubuntu's automatic apt updates in the VM.

**The drive's speed sets the build time.** On 2026-11-07 the External drive
was a 5,400 rpm laptop hard disk (Seagate ST9500325AS). The VM's disk was
86–96% busy at about 100 operations a second, and the CPUs spent about half
their time waiting on it. The first build from scratch took about 12¾ hours of
BitBake. At the end the VM's disk held 116 GB (downloads 49 GB, sstate 15 GB),
and its image file on the drive was 103 GB; the peak during the build was not
measured. An external SSD should be several times faster
([bench log](../hardware/bench-log.md)).

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
3. **An aarch64 Ubuntu VM on the Mac** with its disk on an external SSD: the
   quick start above. AGL doesn't document aarch64 hosts, and AGL's sstate
   mirror is built on x86_64, so a first build compiles everything. Being tried
   (ADR-0004 amendment).

## What runs where

| Task | Mac | Linux build host | Pi 5 |
|---|---|---|---|
| Flutter UI development and tests | ✓ | | |
| Rust services (simulated) and tests | ✓ | ✓ | |
| Cross-compiling Rust for the Pi (aarch64) | ✓ (cargo-zigbuild or cross) | ✓ | |
| AGL / Yocto image build | (in the build VM) | ✓ | |
| Stage-1 sideload onto the prebuilt AGL image | ✓ (`make deploy`) | ✓ | target |

## Host preparation

`agl/scripts/setup-build-host.sh` installs the Yocto 6.0 package list for
Ubuntu ([Yocto 6.0](https://docs.yoctoproject.org/6.0/ref-manual/system-requirements.html)),
plus `curl` and the `repo` tool (AGL), sets the `en_US.UTF-8` locale, adds a
16 GB swap file, and lifts Ubuntu 24.04's AppArmor block on unprivileged user
namespaces, which BitBake uses. Neither AGL's nor Yocto's page mentions that last
step; check it against the first build.
