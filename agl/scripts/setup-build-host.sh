#!/usr/bin/env bash
# Prepare an Ubuntu 24.04 machine to build AGL with Yocto (ADR-0004, Phase 5.4).
# Runs on the build host itself: the Lima VM from `make build-vm`, or a Linux PC.
# Safe to run again.
#
# Sources (checked 2026-11-06):
#   Yocto 6.0 host packages:
#     https://docs.yoctoproject.org/6.0/ref-manual/system-requirements.html
#   AGL extras (curl, the repo tool):
#     https://docs.automotivelinux.org/en/master/01_Getting_Started/02_Building_AGL_Image/
set -euo pipefail

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Linux ]] || die "run this on the Linux build host, not $(uname -s)"
. /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die "written for Ubuntu (found ${ID:-unknown}); see the Yocto page above for other distributions"

say "Install the Yocto 6.0 host packages (+ curl, python3-websockets, lz4)"
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  build-essential chrpath cpio debianutils diffstat file gawk gcc git \
  iputils-ping libacl1 libcrypt-dev locales python3 python3-git python3-jinja2 \
  python3-pexpect python3-pip python3-subunit socat texinfo unzip wget xz-utils \
  zstd python3-websockets curl lz4 tmux

say "Locale en_US.UTF-8"
if ! locale --all-locales | grep -qi '^en_US.utf8$'; then
  sudo sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen >/dev/null
  sudo locale-gen
fi

say "repo tool in ~/bin"
mkdir -p "$HOME/bin"
if [[ ! -x "$HOME/bin/repo" ]]; then
  curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"
  chmod a+x "$HOME/bin/repo"
fi
grep -q 'HOME/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH=$HOME/bin:$PATH' >> "$HOME/.bashrc"

# repo needs an identity for its manifest checkout. A neutral one: nothing is
# ever pushed from the build host.
git config --global user.name  >/dev/null || git config --global user.name  "F250 build host"
git config --global user.email >/dev/null || git config --global user.email "build@localhost"
git config --global color.ui false

# BitBake runs tasks in user namespaces (to cut network access). Ubuntu 24.04's
# AppArmor blocks unprivileged user namespaces by default, and BitBake stops
# with "User namespaces are not usable by BitBake". This host only builds, so
# lift the restriction. UNVERIFIED that 6.0 still needs it: check the first build.
if [[ -e /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]]; then
  say "Allow unprivileged user namespaces (for BitBake)"
  echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/60-bitbake-userns.conf >/dev/null
  sudo sysctl -q -p /etc/sysctl.d/60-bitbake-userns.conf
fi

# Ubuntu's daily automatic upgrades ran at 07:00 during the first build, added
# load to an already saturated disk, and the BitBake client gave up waiting for
# its server (bench log, 2026-11-07). A build host is updated by hand between
# builds, so turn them off.
if systemctl list-unit-files apt-daily-upgrade.timer >/dev/null 2>&1; then
  say "Turn off automatic apt updates (update by hand between builds)"
  sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service >/dev/null 2>&1 || true
fi

# Big link steps (LLVM, Rust, the Flutter engine) can each take several GB.
# A swap file stops a peak from killing the build on a 32 GB VM.
if ! swapon --show=NAME --noheadings | grep -q .; then
  say "16 GB swap file"
  sudo fallocate -l 16G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap -q /swapfile
  sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

say "Done: $(nproc) CPUs, $(free -g | awk '/^Mem:/{print $2}') GB RAM, $(df -h --output=avail "$HOME" | tail -1 | tr -d ' ') free in $HOME"
