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

# ─── Fetch Ollama .deb (pinned version, placed in local apt repo) ─────────────
# vibeos-vibbey Depends: ollama, so mkosi needs it in packages/local/.
# We use the official GitHub release .deb for reproducible builds.
OLLAMA_VERSION="${OLLAMA_VERSION:-0.6.5}"
OLLAMA_DEB_NAME="ollama_${OLLAMA_VERSION}_amd64.deb"
if [ ! -f "packages/local/${OLLAMA_DEB_NAME}" ]; then
    info "downloading Ollama ${OLLAMA_VERSION} .deb"
    # GitHub release filename is ollama-linux-amd64.deb; rename to include version
    curl -fsSL \
        "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.deb" \
        -o "packages/local/${OLLAMA_DEB_NAME}" \
        || err "failed to download Ollama .deb — check OLLAMA_VERSION=${OLLAMA_VERSION}"
    ok "ollama .deb → packages/local/${OLLAMA_DEB_NAME}"
else
    info "using cached Ollama .deb: ${OLLAMA_DEB_NAME}"
fi

TARGETS=("${@}")
if [ "${#TARGETS[@]}" -eq 0 ]; then
    TARGETS=(vibeos-desktop vibeos-vibbey vibeos-claude-code)
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
            # Render SVG wallpapers to PNG (vibeos-desktop only; vibbey has none).
            for svg in src/wallpapers/*/contents/images/*.svg; do
                [ -f \"\$svg\" ] || continue
                png=\"\${svg%.svg}.png\"
                rsvg-convert -w 3840 -h 2160 -o \"\$png\" \"\$svg\"
                echo \"[build-deb] rendered \$png\"
            done
            # -d skips the build-dep check: the builder image has the
            # deps already (debhelper, fakeroot). Our .debs are arch:all
            # data packages — no compiler is invoked.
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
