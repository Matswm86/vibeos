#!/usr/bin/env bash
# Build VibeOS .debs inside the sandboxed builder container.
# Outputs go to packages/local/ which mkosi consumes as a local apt repo
# via PackageDirectories= in mkosi/mkosi.conf.
#
# Usage:
#   scripts/build-deb.sh                     # build every package under packages/
#   scripts/build-deb.sh vibeos-desktop      # build just one

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
IMAGE_TAG="vibeos-builder:latest"

info() { printf '\e[36m→\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m✓\e[0m %s\n' "$*"; }
err()  { printf '\e[31m✗\e[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || err "docker not installed on host"

# Reuse the same builder image scripts/build.sh produces.
if [ -z "$(docker image ls -q "$IMAGE_TAG")" ] \
   || [ Dockerfile.builder -nt "$(docker inspect -f '{{.Created}}' "$IMAGE_TAG" 2>/dev/null || echo 1970)" ]; then
    info "builder image missing — running scripts/build.sh to prime it first"
    docker build -t "$IMAGE_TAG" -f Dockerfile.builder . \
        || err "builder image build failed"
    ok "builder image ready"
fi

mkdir -p packages/local

TARGETS=("${@}")
if [ "${#TARGETS[@]}" -eq 0 ]; then
    TARGETS=(vibeos-desktop)
fi

for pkg in "${TARGETS[@]}"; do
    src_dir="packages/${pkg}"
    [ -d "$src_dir" ] || err "no package source at $src_dir"
    [ -f "$src_dir/debian/control" ] || err "no debian/control in $src_dir"

    info "building $pkg"
    docker run --rm -i \
        -v "$REPO_ROOT:/work" \
        -w "/work/$src_dir" \
        "$IMAGE_TAG" \
        bash -euo pipefail -c "
            # Render SVG wallpapers to PNG so KDE/SDDM/Plymouth all have a
            # raster to load even when Qt SVG renderer is absent in the
            # target session. Source SVGs stay in the tree for reference.
            for svg in src/wallpapers/*/contents/images/*.svg; do
                [ -f \"\$svg\" ] || continue
                png=\"\${svg%.svg}.png\"
                rsvg-convert -w 3840 -h 2160 -o \"\$png\" \"\$svg\"
                echo \"[build-deb] rendered \$png\"
            done
            # -d skips the build-dep check: the builder image has the
            # deps already (debhelper, fakeroot), no need to verify via
            # apt against build-essential:native which we deliberately
            # omit to keep the image small. Our .debs are arch:all data
            # packages anyway — no compiler is invoked.
            dpkg-buildpackage -us -uc -b -d
        " \
        || err "dpkg-buildpackage failed for $pkg"

    # Built .deb lands in packages/ (one level up from src_dir). Move it
    # into packages/local/ for mkosi to consume.
    mv -v packages/${pkg}_*.deb packages/local/ 2>/dev/null || true
    rm -f packages/${pkg}_*.buildinfo packages/${pkg}_*.changes 2>/dev/null || true
    ok "built $pkg → packages/local/"
done

info "packages/local/ now contains:"
ls -lh packages/local/
