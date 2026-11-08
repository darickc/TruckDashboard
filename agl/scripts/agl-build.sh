#!/usr/bin/env bash
# Build the head unit image from source on the build host (Phase 5.4): the
# pinned AGL release plus this repository's layer, agl/meta-f250.
# Runs on the Linux build host (the Lima VM from `make build-vm`, or a PC);
# prepare it first with agl/scripts/setup-build-host.sh.
#
#   agl-build.sh            fetch the layers (once), configure, bitbake the image
#   agl-build.sh fetch      repo init + sync only
#   agl-build.sh setup      fetch + aglsetup.sh only (prints the config)
#
# Environment:
#   AGL_TOP     where the layers, downloads, sstate and build live ($HOME/agl)
#   FEATURES    aglsetup.sh features ("agl-demo agl-devel")
#   TARGET      bitbake target (agl-f250; agl-ivi-demo-flutter is AGL's own)
#   F250_LAYER=0  leave meta-f250 out (only AGL's images build then)
#   F250_ALLOW_DIRTY=1  build although the checkout has uncommitted changes
#   THREADS     BitBake tasks at once (8); JOBS make -j per task (nproc)
#   KEEP_WORK=1 keep each recipe's work directory (no rm_work; much more disk)
#
# meta-f250 builds the head unit's software from this checkout's HEAD commit
# (F250_REPO, F250_SRCREV in site.conf), while BitBake reads the layer's
# recipes from the working tree. Uncommitted changes would mix the two, so
# the build stops unless F250_ALLOW_DIRTY=1.
#
# The release, branch and machine come from agl/configurations/vimba.env.
# The manifest is AGL-repo's vimba_<release>.xml at the release tag; on
# 2026-11-06 it pinned the same layers and revisions as the manifest AGL
# published with the 22.0.1 Pi 5 image (raspberrypi5_repo_default.xml).
#
# Status: [BENCH] built agl-ivi-demo-flutter for raspberrypi5 in the build VM
# on 2026-11-07; the image boots on the Pi and runs Stage 1 (docs/hardware/bench-log.md).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../configurations/vimba.env
. "$HERE/../configurations/vimba.env"

MODE="${1:-build}"
AGL_TOP="${AGL_TOP:-$HOME/agl}"
FEATURES="${FEATURES:-agl-demo agl-devel}"
TARGET="${TARGET:-agl-f250}"
F250_LAYER="${F250_LAYER:-1}"
F250_REPO="$(cd "$HERE/../.." && pwd)"
THREADS="${THREADS:-8}"
JOBS="${JOBS:-$(nproc)}"
SRC="$AGL_TOP/$AGL_BRANCH-$AGL_RELEASE"
BUILD="$SRC/build-$AGL_MACHINE"
export PATH="$HOME/bin:$PATH"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Linux ]] || die "run this on the Linux build host (make agl-build runs it in the VM)"
command -v repo >/dev/null || die "repo not found: run agl/scripts/setup-build-host.sh"

fetch() {
  mkdir -p "$SRC"
  cd "$SRC"
  if [[ ! -d .repo ]]; then
    say "repo init: AGL $AGL_RELEASE ($AGL_BRANCH)"
    repo init -q -u https://gerrit.automotivelinux.org/gerrit/AGL/AGL-repo \
      -b "refs/tags/$AGL_BRANCH/$AGL_RELEASE" -m "${AGL_BRANCH}_${AGL_RELEASE}.xml"
  fi
  # The manifest pins a release tag, so a checkout that is already there is
  # already right. Syncing it again only risks swapping meta-qt6 between
  # servers mid-tree, which repo refuses ("hooks is different").
  if [[ "$MODE" != fetch && -f .repo/project.list && -d meta-agl && -d external/meta-qt6 ]]; then
    say "Layers already fetched (agl-build.sh fetch to sync again)"
    return
  fi
  qt6_fallback
  say "repo sync"
  # --force-sync: replace a checkout whose source changed (the meta-qt6
  # fallback). Nothing in this tree is edited by hand.
  repo sync -q -j8 --no-clone-bundle --force-sync
}

# code.qt.io, meta-qt6's home, stopped answering on 2026-11-06 (from the Mac
# and the VM alike). When it is down, fetch the same pinned commit from a
# GitHub mirror instead. The manifest pins meta-qt6 by commit hash, so the
# files are identical whichever server provides them.
QT6_MIRROR="${QT6_MIRROR:-YoeDistro/meta-qt6}"
qt6_fallback() {
  local lm=.repo/local_manifests/qt6-mirror.xml rev
  if GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=20 \
       git ls-remote https://code.qt.io/yocto/meta-qt6.git HEAD >/dev/null 2>&1; then
    rm -f "$lm"
    return
  fi
  rev="$(sed -n 's/.*name="yocto\/meta-qt6".*revision="\([0-9a-f]\{40\}\)".*/\1/p' .repo/manifests/"${AGL_BRANCH}_${AGL_RELEASE}.xml")"
  [[ -n "$rev" ]] || die "code.qt.io is unreachable and meta-qt6 is not pinned to a commit in the manifest"
  say "code.qt.io unreachable: meta-qt6 $rev from github.com/$QT6_MIRROR"
  mkdir -p .repo/local_manifests
  cat > "$lm" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- Written by agl/scripts/agl-build.sh while code.qt.io is unreachable. -->
<manifest>
  <remove-project name="yocto/meta-qt6"/>
  <project name="$QT6_MIRROR" path="external/meta-qt6" remote="github" revision="$rev"/>
</manifest>
EOF
}

setup() {
  cd "$SRC"
  say "aglsetup.sh -m $AGL_MACHINE: $FEATURES"
  # aglsetup.sh is meant to be sourced; it leaves us in the build directory.
  # shellcheck disable=SC1091
  set +u; source meta-agl/scripts/aglsetup.sh -f -m "$AGL_MACHINE" -b "$BUILD" $FEATURES; set -u

  # Our settings, in their own file so aglsetup.sh can rewrite local.conf.
  # Downloads and sstate sit outside the release tree, so a later release or
  # meta-f250 reuses them.
  cat > conf/site.conf <<EOF
# Written by agl/scripts/agl-build.sh. Edit the script, not this file.
DL_DIR = "$AGL_TOP/downloads"
SSTATE_DIR = "$AGL_TOP/sstate-cache"
# The hash-equivalence database beside the shared sstate, as BitBake's own
# warning recommends, so another build directory (meta-f250) can reuse it.
BB_HASHSERVE_DB_DIR = "\${SSTATE_DIR}"
BB_NUMBER_THREADS = "$THREADS"
PARALLEL_MAKE = "-j $JOBS"
# Fetch sources from AGL's mirror first, as AGL's own release builds do.
PREMIRRORS:prepend = " \\
git://.*/.*   https://download.automotivelinux.org/AGL/mirror/ \\
ftp://.*/.*   https://download.automotivelinux.org/AGL/mirror/ \\
http://.*/.*  https://download.automotivelinux.org/AGL/mirror/ \\
https://.*/.* https://download.automotivelinux.org/AGL/mirror/ \\
"
EOF
  if [[ "$F250_LAYER" == 1 ]]; then
    f250_layer
  fi
  if [[ "${KEEP_WORK:-0}" != 1 ]]; then
    # Delete each recipe's work directory once it is built: the main saving
    # in disk (docs/setup/linux-build-host.md).
    echo 'INHERIT += "rm_work"' >> conf/site.conf
  fi
  say "Configured $BUILD"
  grep -E '^(MACHINE|DISTRO|require)' conf/local.conf || true
}

# meta-f250 and the commit it builds. The repository is the build host's
# checkout (in the VM, the Mac's, mounted read-only at the same path).
f250_layer() {
  local rev dirty
  command -v git >/dev/null || die "git not found"
  rev="$(git -C "$F250_REPO" rev-parse HEAD)" || die "$F250_REPO is not a git checkout"
  dirty="$(git -C "$F250_REPO" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    if [[ "${F250_ALLOW_DIRTY:-0}" == 1 ]]; then
      say "WARNING: uncommitted changes; the software is built from $rev, the recipes from the working tree"
    else
      printf '%s\n' "$dirty" >&2
      die "uncommitted changes in $F250_REPO: commit them (the image is built from HEAD), or F250_ALLOW_DIRTY=1"
    fi
  fi
  cat >> conf/site.conf <<EOF
# The head unit's software: agl/meta-f250, built from this commit.
F250_REPO = "$F250_REPO"
F250_SRCREV = "$rev"
EOF
  if ! grep -q "$F250_REPO/agl/meta-f250" conf/bblayers.conf; then
    printf '\n# Added by agl/scripts/agl-build.sh\nBBLAYERS += "%s"\n' "$F250_REPO/agl/meta-f250" >> conf/bblayers.conf
  fi
  say "meta-f250 from $F250_REPO at ${rev:0:12}"
}

build() {
  mkdir -p "$AGL_TOP/logs"
  local log
  log="$AGL_TOP/logs/$TARGET-$(date +%Y%m%d-%H%M%S).log"
  say "bitbake $TARGET (log: $log)"
  local start=$SECONDS rc=0
  bitbake "$TARGET" 2>&1 | tee "$log" || rc=$?
  # The result goes in the log too, so it survives the terminal or tmux.
  {
    say "bitbake exit $rc after $(( (SECONDS - start) / 60 )) min"
    df -h "$AGL_TOP" | tail -1
    ls -lh "$BUILD/tmp/deploy/images/$AGL_MACHINE/"*.wic* 2>/dev/null || true
  } 2>&1 | tee -a "$log"
  return $rc
}

case "$MODE" in
  fetch) fetch ;;
  setup) fetch; setup ;;
  build) fetch; setup; build ;;
  *) die "usage: $0 [build|fetch|setup]" ;;
esac
