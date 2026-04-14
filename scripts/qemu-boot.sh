#!/usr/bin/env bash
# Boot the built VibeOS ISO in QEMU — also sandboxed in Docker so the
# host workstation needs no qemu-system-x86 or ovmf packages installed.
# QEMU exposes its display via SPICE on localhost:5930; connect with
# remmina, virt-viewer, or any SPICE client.
#
# Usage:
#   scripts/qemu-boot.sh                     # boot the default ISO, 4GB RAM
#   scripts/qemu-boot.sh --install           # attach empty 30GB qcow2 disk
#                                            #   to test Calamares install flow
#   scripts/qemu-boot.sh path/to/other.iso   # boot a specific ISO
#
# Host requirement: /dev/kvm accessible (most Linux hosts have it).
# Run `ls -l /dev/kvm` — if that fails, QEMU falls back to software
# emulation (10x slower but works).

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
IMAGE_TAG="vibeos-qemu:latest"

err()  { printf '\e[31m✗\e[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\e[36m→\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m✓\e[0m %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || err "docker not installed on host"

# Build the QEMU runner image on demand
if [ -z "$(docker image ls -q "$IMAGE_TAG")" ]; then
    info "building $IMAGE_TAG image (first run, ~2 min)"
    docker build -t "$IMAGE_TAG" -f - . <<'DOCKERFILE'
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-x86 qemu-utils ovmf \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
DOCKERFILE
    ok "qemu runner ready"
fi

ISO=""
INSTALL_DISK=0
for arg in "$@"; do
    case "$arg" in
        --install)      INSTALL_DISK=1 ;;
        *.iso|*.raw|*.img) ISO="$arg" ;;
    esac
done
[ -z "$ISO" ] && ISO="mkosi.output/vibeos.raw"
[ -f "$ISO" ] || err "ISO not found: $ISO  (run ./scripts/build.sh first)"

info "booting $ISO in QEMU (SPICE display on localhost:5930)"
info "connect with: remote-viewer spice://localhost:5930"

QEMU_ARGS=(
    -name vibeos-test
    -machine q35,accel=kvm:tcg
    -cpu host,kvm=on
    -m 4096
    -smp 2
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd
    -drive media=cdrom,file="/work/$ISO"
    -boot d
    -netdev user,id=net0
    -device virtio-net-pci,netdev=net0
    -vga virtio
    -spice port=5930,addr=0.0.0.0,disable-ticketing=on
    -device virtio-serial-pci
)

if [ "$INSTALL_DISK" = "1" ]; then
    DISK="mkosi.output/test-install.qcow2"
    if [ ! -f "$DISK" ]; then
        info "creating 30GB test disk: $DISK"
        docker run --rm -v "$REPO_ROOT:/work" "$IMAGE_TAG" \
            qemu-img create -f qcow2 "/work/$DISK" 30G
    fi
    QEMU_ARGS+=( -drive file="/work/$DISK",format=qcow2,if=virtio )
fi

# --device /dev/kvm gives hardware virtualization (optional, falls back to TCG)
KVM_FLAG=""
[ -r /dev/kvm ] && KVM_FLAG="--device /dev/kvm"

exec docker run --rm -it $KVM_FLAG \
    -p 5930:5930 \
    -v "$REPO_ROOT:/work" \
    "$IMAGE_TAG" \
    qemu-system-x86_64 "${QEMU_ARGS[@]}"
