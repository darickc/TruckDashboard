#!/usr/bin/env bash
# The AGL build host as a Lima VM on the Mac (ADR-0004 amendment, Phase 5.4).
#
#   make build-vm              create (once) and start the VM, prepare it for Yocto
#   make build-vm CMD=shell    a shell in the VM
#   make build-vm CMD=stop     stop it (frees its RAM; its disk stays)
#   make build-vm CMD=status   VM state and disk use
#   make build-vm CMD=log      follow the latest build log
#   make build-vm CMD=delete   delete the VM and everything built in it
#   make agl-build             run agl/scripts/agl-build.sh in the VM, in tmux
#                              (Ctrl-b d detaches; DETACH=1 starts it detached)
#
# The VM is Ubuntu 24.04 aarch64 under Apple's Virtualization framework.
# Everything Lima keeps for it (the VM's disk included) lives in one
# directory, BUILD_VM_DIR (~/agl-build-vm), used as LIMA_HOME: deleting that
# directory removes the VM entirely. The repo is mounted read-only at the same
# path, so the VM runs this checkout's scripts.
#
# Until 2026-11-07 it lived on an external hard disk (/Volumes/External/lima),
# which made builds slow; BUILD_VM_DIR=/Volumes/External/lima still uses it.
#
# Environment: BUILD_VM_DIR (~/agl-build-vm), VM_CPUS (12), VM_MEMORY in GiB
# (32), VM_DISK in GiB (420).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
REPO="$PWD"

CMD="${1:-up}"
VM_DIR="${BUILD_VM_DIR:-$HOME/agl-build-vm}"
NAME=agl-build
CPUS="${VM_CPUS:-12}"
MEMORY="${VM_MEMORY:-32}"
DISK="${VM_DISK:-420}"
export LIMA_HOME="$VM_DIR"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

command -v limactl >/dev/null || die "limactl not found: brew install lima"
mkdir -p "$VM_DIR"
fs="$(diskutil info "$(df "$VM_DIR" | awk 'NR==2{print $1}')" | sed -n 's/^ *File System Personality: *//p')"
[[ "$fs" == *APFS* ]] || die "$VM_DIR is on $fs; it must be APFS (exFAT can't hold the VM's sparse disk)"

exists() { limactl list -q 2>/dev/null | grep -qx "$NAME"; }
running() { [[ "$(limactl list --format '{{.Status}}' "$NAME" 2>/dev/null)" == Running ]]; }
in_vm() { limactl shell --workdir / "$NAME" -- "$@"; }

up() {
  if ! exists; then
    local free
    free=$(df -g "$VM_DIR" | awk 'NR==2{print $4}')
    (( free > DISK )) || say "warning: ${free} GB free for $VM_DIR; the VM disk may grow to ${DISK} GiB"
    say "Create $NAME: Ubuntu 24.04, $CPUS CPUs, ${MEMORY} GiB RAM, ${DISK} GiB disk in $LIMA_HOME"
    mkdir -p "$LIMA_HOME"
    limactl create --tty=false --name="$NAME" --vm-type=vz \
      --cpus="$CPUS" --memory="$MEMORY" --disk="$DISK" \
      --mount-only "$REPO" template:ubuntu-24.04
  fi
  running || { say "Start $NAME"; limactl start --tty=false "$NAME"; }
  say "Prepare the VM for Yocto"
  in_vm bash -lc "'$REPO/agl/scripts/setup-build-host.sh'"
}

case "$CMD" in
  up) up ;;
  shell) running || up; limactl shell "$NAME" ;;
  build)
    running || up
    # In tmux inside the VM, so a long build survives this terminal closing.
    # Attach from a terminal; with DETACH=1 (or no terminal) it runs on, and
    # `make build-vm CMD=log` follows it.
    job="cd ~ && '$REPO/agl/scripts/agl-build.sh' ${AGL_BUILD_ARGS:-}; echo \"agl-build.sh exit \$?\"; exec bash"
    if in_vm tmux has-session -t agl-build 2>/dev/null; then
      say "A build session is already running in the VM"
    else
      in_vm tmux new-session -d -s agl-build -x 200 -y 50 "bash -lc \"$job\""
    fi
    if [[ -t 1 && "${DETACH:-0}" != 1 ]]; then
      limactl shell "$NAME" -- tmux attach -t agl-build
    else
      say "Running in tmux session agl-build in the VM: make build-vm CMD=log"
    fi ;;
  log) in_vm bash -lc 'tail -n "${LINES:-40}" -F "$(ls -t ~/agl/logs/*.log | head -1)"' ;;
  stop) exists && running && limactl stop "$NAME"; say "stopped" ;;
  status)
    limactl list "$NAME" 2>/dev/null || echo "no VM yet: make build-vm"
    du -sh "$LIMA_HOME" 2>/dev/null || true
    df -h "$VM_DIR" | tail -1
    if running; then in_vm bash -lc 'df -h ~ | tail -1; free -g | head -2; ls ~/agl/logs 2>/dev/null | tail -3'; fi ;;
  delete) exists && limactl delete --force "$NAME"; say "deleted $NAME (rm -rf $VM_DIR removes the rest)" ;;
  *) die "usage: make build-vm [CMD=up|shell|stop|status|log|delete]" ;;
esac
