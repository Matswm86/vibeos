#!/usr/bin/env bash
# Fetch VibeOS font pack (Orbitron, JetBrains Mono, VT323) into theming/fonts/
# Licenses: OFL 1.1 (Orbitron, VT323), Apache 2.0 (JetBrains Mono) — all redistributable.
#
# Sources: GitHub release tarballs + raw mirrors.
# Google Fonts killed the `fonts.google.com/download?family=X` endpoint — use
# the upstream GitHub repos instead (they are the canonical source anyway).
#
# Run from repo root: bash scripts/fetch-fonts.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FONT_DIR="$REPO_ROOT/theming/fonts"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$FONT_DIR"/{orbitron,jetbrains-mono,vt323,licenses}

say()  { printf '  \e[35m→\e[0m %s\n' "$*"; }
ok()   { printf '  \e[32m✓\e[0m %s\n' "$*"; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*" >&2; }

UA="Mozilla/5.0 (X11; Linux x86_64) VibeOS-fetch/0.4.0"

# ---------------------------------------------------------------
# Orbitron — upstream: google/fonts repo (ofl/orbitron)
# Only variable font (Orbitron[wght].ttf) is maintained upstream now.
# ---------------------------------------------------------------
say "fetching Orbitron (google/fonts)"
ORBI_BASE="https://raw.githubusercontent.com/google/fonts/main/ofl/orbitron"
# URL-encode brackets in filename ([ → %5B, ] → %5D)
curl -fsSL -A "$UA" -o "$FONT_DIR/orbitron/Orbitron-VariableFont_wght.ttf" \
    "$ORBI_BASE/Orbitron%5Bwght%5D.ttf" || warn "Orbitron variable TTF failed"
curl -fsSL -A "$UA" -o "$FONT_DIR/licenses/Orbitron-OFL.txt" \
    "$ORBI_BASE/OFL.txt" || warn "Orbitron OFL.txt fetch failed"
ok "Orbitron downloaded"

# ---------------------------------------------------------------
# JetBrains Mono — GitHub release (JetBrains/JetBrainsMono)
# ---------------------------------------------------------------
say "fetching JetBrains Mono (GitHub release)"
JB_VERSION="2.304"
JB_URL="https://github.com/JetBrains/JetBrainsMono/releases/download/v${JB_VERSION}/JetBrainsMono-${JB_VERSION}.zip"
if curl -fsSL -A "$UA" -o "$TMP_DIR/jbm.zip" "$JB_URL"; then
    unzip -q -o "$TMP_DIR/jbm.zip" -d "$TMP_DIR/jbm"
    # The zip bundles ttf + webfonts etc. We only want fonts/ttf/*.ttf
    find "$TMP_DIR/jbm" -type f -iname '*.ttf' -path '*fonts/ttf/*' \
        -exec cp {} "$FONT_DIR/jetbrains-mono/" \;
    find "$TMP_DIR/jbm" -type f -iname 'OFL.txt' \
        -exec cp {} "$FONT_DIR/licenses/JetBrainsMono-OFL.txt" \; 2>/dev/null || true
    # JetBrains Mono is Apache 2.0, not OFL — grab LICENSE too
    find "$TMP_DIR/jbm" -type f -iname 'LICENSE*' \
        -exec cp {} "$FONT_DIR/licenses/JetBrainsMono-LICENSE.txt" \; 2>/dev/null || true
    ok "JetBrains Mono downloaded"
else
    warn "JetBrains Mono download failed — try apt install fonts-jetbrains-mono inside chroot"
fi

# ---------------------------------------------------------------
# VT323 — upstream: google/fonts repo (ofl/vt323)
# ---------------------------------------------------------------
say "fetching VT323 (google/fonts)"
VT_BASE="https://raw.githubusercontent.com/google/fonts/main/ofl/vt323"
curl -fsSL -A "$UA" -o "$FONT_DIR/vt323/VT323-Regular.ttf" \
    "$VT_BASE/VT323-Regular.ttf" || warn "VT323 download failed"
curl -fsSL -A "$UA" -o "$FONT_DIR/licenses/VT323-OFL.txt" \
    "$VT_BASE/OFL.txt" 2>/dev/null || true
ok "VT323 downloaded"

# ---------------------------------------------------------------
# Bibata Modern Ice cursor — GitHub release, GPL-3.0
# ---------------------------------------------------------------
say "fetching Bibata Modern Ice cursor"
BIBATA_VER="2.0.6"
BIBATA_URL="https://github.com/ful1e5/Bibata_Cursor/releases/download/v${BIBATA_VER}/Bibata-Modern-Ice.tar.xz"
if curl -fsSL -A "$UA" -o "$TMP_DIR/bibata.tar.xz" "$BIBATA_URL"; then
    mkdir -p "$REPO_ROOT/theming/icons/cursors"
    tar -xJf "$TMP_DIR/bibata.tar.xz" -C "$REPO_ROOT/theming/icons/cursors/"
    ok "Bibata cursor extracted"
else
    warn "Bibata download failed — cursor will fall back to system default"
fi

# ---------------------------------------------------------------
# Report
# ---------------------------------------------------------------
printf '\n\e[36msummary:\e[0m\n'
TTF_COUNT=$(find "$FONT_DIR" -type f \( -iname '*.ttf' -o -iname '*.otf' \) 2>/dev/null | wc -l)
LIC_COUNT=$(find "$FONT_DIR/licenses" -type f 2>/dev/null | wc -l)
printf '  %s font files\n' "$TTF_COUNT"
printf '  %s license files\n' "$LIC_COUNT"
if [ "$TTF_COUNT" -lt 3 ]; then
    warn "font count is low — some downloads may have failed"
    exit 1
fi
