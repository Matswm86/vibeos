#!/usr/bin/env bash
# Headless smoke test — boot vibeos.raw in QEMU with serial console,
# watch for systemd reaching a stable target, then shut down.
#
# Proves:
# - Kernel boots (no panic)
# - Root filesystem mounts
# - systemd userspace comes up
# - Multi-user target reached (implies login-capable system)
#
# Does NOT prove (requires graphical boot + screenshot):
# - SDDM autologin actually lands on Plasma desktop
# - Theme renders
# - Network/flatpak/etc work

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
IMAGE_TAG="vibeos-qemu:latest"
ISO="${1:-mkosi.output/vibeos.raw}"
TIMEOUT="${TIMEOUT:-420}"   # TCG emulation is slow, give 7 min

err()  { printf '\e[31m✗\e[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\e[36m→\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m✓\e[0m %s\n' "$*"; }

[ -f "$ISO" ] || err "ISO not found: $ISO"

# Build minimal QEMU runner image if missing
if [ -z "$(docker image ls -q "$IMAGE_TAG")" ]; then
    info "building $IMAGE_TAG image (~2 min)"
    docker build -t "$IMAGE_TAG" -f - . <<'DOCKERFILE'
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-x86 qemu-utils ovmf \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /work
DOCKERFILE
    ok "qemu image ready"
fi

info "booting $ISO headless with serial console (timeout ${TIMEOUT}s)"
info "looking for: 'Reached target graphical' OR 'Reached target Multi-User' OR 'login:'"

LOG=/tmp/vibeos-smoke.log
rm -f "$LOG"

KVM_FLAG=""
[ -r /dev/kvm ] && KVM_FLAG="--device /dev/kvm"

# Direct kernel boot bypasses systemd-boot so we can inject console=ttyS0.
# systemd.unit=multi-user.target avoids launching SDDM (graphical) since
# we can't see a screen headless — multi-user is enough to prove boot works.
timeout "$TIMEOUT" docker run --rm $KVM_FLAG \
    -v "$REPO_ROOT:/work" \
    "$IMAGE_TAG" \
    qemu-system-x86_64 \
        -name vibeos-smoke \
        -machine q35,accel=tcg \
        -cpu qemu64 \
        -m 2048 -smp 2 \
        -kernel "/work/mkosi.output/vibeos.vmlinuz" \
        -initrd "/work/mkosi.output/vibeos.initrd" \
        -append "root=PARTLABEL=root-x86-64 rw console=ttyS0,115200 systemd.unit=multi-user.target quiet loglevel=4" \
        -drive file="/work/$ISO",format=raw,if=virtio \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        -nographic -serial mon:stdio \
        -no-reboot \
    2>&1 | tee "$LOG" \
    | while IFS= read -r line; do
        printf '%s\n' "$line"
        if echo "$line" | grep -qE "Reached target (graphical|Multi-User|Login Prompts)|login:"; then
            ok "boot succeeded: $line"
            # Trigger orderly shutdown via QEMU monitor
            break
        fi
    done || true

if grep -qE "Reached target (graphical|Multi-User|Login Prompts)|login:" "$LOG"; then
    ok "SMOKE TEST PASSED — systemd reached a login-capable target"
    grep -oE "Reached target [A-Za-z -]+" "$LOG" | sort -u
    exit 0
elif grep -q "Kernel panic" "$LOG"; then
    err "KERNEL PANIC — see $LOG"
elif grep -q "Timed out waiting for device" "$LOG"; then
    err "ROOT FS MOUNT FAILED — see $LOG"
else
    err "inconclusive — no obvious success marker. check $LOG manually"
fi
