#!/usr/bin/env bash
# VibeOS ISO build — runs mkosi inside a Docker container so the host
# workstation stays clean. Output ISO lands in ./mkosi.output/.
#
# Usage:
#   scripts/build.sh              # build ISO
#   scripts/build.sh clean        # wipe mkosi.output/
#   scripts/build.sh shell        # drop into builder container for debugging
#
# The container needs --privileged because mkosi mounts loopback devices,
# creates filesystems, and runs debootstrap. This is safe — the container
# can mount/unmount inside its own namespace but has no access outside
# the mounted ./  volume and the Docker daemon.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
IMAGE_TAG="vibeos-builder:latest"

err()  { printf '\e[31m✗\e[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\e[36m→\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m✓\e[0m %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || err "docker not installed on host"

# Build the builder image if missing or stale
if [ -z "$(docker image ls -q "$IMAGE_TAG")" ] \
   || [ Dockerfile.builder -nt "$(docker inspect -f '{{.Created}}' "$IMAGE_TAG" 2>/dev/null || echo 1970)" ]; then
    info "building $IMAGE_TAG image (first run, ~3-5 min)"
    docker build -t "$IMAGE_TAG" -f Dockerfile.builder . \
        || err "builder image build failed"
    ok "builder image ready"
fi

ACTION="${1:-build}"
case "$ACTION" in
    clean)
        info "wiping mkosi.output/"
        rm -rf mkosi.output/
        ok "clean"
        exit 0
        ;;
    shell)
        info "entering builder shell (exit with Ctrl+D)"
        exec docker run --rm -it --privileged \
            -v "$REPO_ROOT:/work" \
            "$IMAGE_TAG" bash
        ;;
    build|"")
        info "building VibeOS ISO (~10 min first time, faster on rebuild)"
        docker run --rm -i --privileged \
            -v "$REPO_ROOT:/work" \
            "$IMAGE_TAG" \
            bash -c 'cd /work && mkosi --directory mkosi build'
        ;;
    *)
        err "unknown action: $ACTION (try: build / clean / shell)"
        ;;
esac

if [ -f mkosi.output/vibeos.iso ]; then
    SIZE=$(du -h mkosi.output/vibeos.iso | cut -f1)
    ok "ISO built: mkosi.output/vibeos.iso ($SIZE)"
    info "next step: ./scripts/qemu-boot.sh"
else
    err "ISO not produced — check mkosi output above for errors"
fi
