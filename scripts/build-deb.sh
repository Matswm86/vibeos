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

# ─── Fetch + repack Ollama tarball as a local .deb ────────────────────────────
# vibeos-vibbey Depends: ollama, so mkosi needs it resolvable from
# packages/local/. Upstream Ollama stopped shipping .deb in 2025 and only
# publishes ollama-linux-amd64.tar.zst. We unpack it and assemble a minimal
# control.tar+data.tar into our own .deb — same mkosi integration, no
# upstream packaging dependency.
OLLAMA_VERSION="${OLLAMA_VERSION:-0.20.7}"
OLLAMA_DEB_NAME="ollama_${OLLAMA_VERSION}_amd64.deb"
if [ ! -f "packages/local/${OLLAMA_DEB_NAME}" ]; then
    info "building Ollama ${OLLAMA_VERSION} .deb from upstream tarball"
    docker run --rm -i \
        -v "$REPO_ROOT:/work" \
        -w /work \
        -e OLLAMA_VERSION="$OLLAMA_VERSION" \
        -e OLLAMA_DEB_NAME="$OLLAMA_DEB_NAME" \
        "$IMAGE_TAG" \
        bash -euo pipefail -c '
            TMP=$(mktemp -d)
            trap "rm -rf $TMP" EXIT
            URL="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst"
            echo "[ollama-deb] fetching $URL"
            curl -fsSL "$URL" -o "$TMP/ollama.tar.zst"
            mkdir -p "$TMP/root/usr"
            tar --zstd -xf "$TMP/ollama.tar.zst" -C "$TMP/root/usr"
            test -x "$TMP/root/usr/bin/ollama" || { echo "no ollama binary in tarball"; exit 1; }
            # Build the debian/ control tree
            mkdir -p "$TMP/root/DEBIAN"
            cat > "$TMP/root/DEBIAN/control" <<CTRL
Package: ollama
Version: ${OLLAMA_VERSION}
Architecture: amd64
Maintainer: VibeOS <release@mwmai.no>
Installed-Size: $(du -sk "$TMP/root/usr" | cut -f1)
Depends: libc6, libstdc++6
Section: utils
Priority: optional
Homepage: https://ollama.com
Description: Ollama large language model runner (repackaged by VibeOS)
 Upstream Ollama ships a .tar.zst tarball on GitHub releases; this
 .deb is a thin repackage produced by scripts/build-deb.sh for local
 apt-resolvable installation inside the VibeOS ISO.
CTRL
            # Drop a minimal systemd unit + ollama user so the service works.
            mkdir -p "$TMP/root/lib/systemd/system"
            cat > "$TMP/root/lib/systemd/system/ollama.service" <<UNIT
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=default.target
UNIT
            cat > "$TMP/root/DEBIAN/postinst" <<POSTINST
#!/bin/sh
set -e
if ! getent passwd ollama >/dev/null; then
    useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
fi
if ! getent group ollama >/dev/null; then
    groupadd -r ollama
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl enable ollama.service || true
fi
exit 0
POSTINST
            chmod 0755 "$TMP/root/DEBIAN/postinst"
            cat > "$TMP/root/DEBIAN/prerm" <<PRERM
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now ollama.service 2>/dev/null || true
fi
exit 0
PRERM
            chmod 0755 "$TMP/root/DEBIAN/prerm"
            # Fix ownership — everything root:root inside the .deb
            chown -R 0:0 "$TMP/root"
            # Build the .deb
            dpkg-deb --root-owner-group --build "$TMP/root" "packages/local/${OLLAMA_DEB_NAME}"
            echo "[ollama-deb] built packages/local/${OLLAMA_DEB_NAME}"
        ' || err "Ollama .deb build failed"
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
            # Pre-render Plymouth wordmark + tagline PNGs per theme.
            # Plymouth's Image.Text() renders in initramfs where fontconfig
            # is incomplete, which broke text layout (overlapping blur on
            # MSI). PNGs eliminate all font-at-boot dependency.
            if [ -d src/plymouth ] && [ -f src/fonts/Orbitron-VariableFont_wght.ttf ]; then
                FONT=\"\$(pwd)/src/fonts/Orbitron-VariableFont_wght.ttf\"
                render_theme() {
                    theme_dir=\"\$1\"; tagline=\"\$2\"; wc=\"\$3\"; tc=\"\$4\"
                    # PNG32: forces RGBA output — libply in some
                    # Plymouth builds mis-renders 8-bit indexed PNGs.
                    convert -background none -fill \"\$wc\" \
                            -font \"\$FONT\" -pointsize 200 \
                            label:'VibeOS' -trim +repage \
                            PNG32:\"\$theme_dir/wordmark.png\"
                    convert -background none -fill \"\$tc\" \
                            -font \"\$FONT\" -pointsize 56 \
                            label:\"\$tagline\" -trim +repage \
                            PNG32:\"\$theme_dir/tagline.png\"
                    echo \"[build-deb] rendered Plymouth assets for \$(basename \$theme_dir)\"
                }
                render_theme src/plymouth/vibeos-pacific-dawn 'pacific dawn' '#2D1B3E' '#FF5A8F'
                render_theme src/plymouth/vibeos-outrun        'outrun'        '#FF2E88' '#00E5FF'
                render_theme src/plymouth/vibeos-miami         'miami'         '#2E1A47' '#FF6F91'
                render_theme src/plymouth/vibeos-neon-grid     'neon grid'     '#39FF14' '#00FFD1'
            fi
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
