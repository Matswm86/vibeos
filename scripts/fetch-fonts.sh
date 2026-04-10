#!/usr/bin/env bash
# Fetch VibeOS font pack (Orbitron, JetBrains Mono, VT323) into theming/fonts/
# Licenses: OFL 1.1 (Orbitron, VT323), Apache 2.0 (JetBrains Mono) — all redistributable.
#
# Run from repo root: bash scripts/fetch-fonts.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FONT_DIR="$REPO_ROOT/theming/fonts"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$FONT_DIR"/{orbitron,jetbrains-mono,vt323,licenses}

say() { printf '  \e[35m→\e[0m %s\n' "$*"; }

# --- Orbitron (Google Fonts, OFL 1.1) ---
say "fetching Orbitron"
curl -fsSL -o "$TMP_DIR/orbitron.zip" \
    "https://fonts.google.com/download?family=Orbitron"
unzip -q -o "$TMP_DIR/orbitron.zip" -d "$TMP_DIR/orbitron"
find "$TMP_DIR/orbitron" -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
    -exec cp -v {} "$FONT_DIR/orbitron/" \;
find "$TMP_DIR/orbitron" -type f -iname 'OFL.txt' \
    -exec cp -v {} "$FONT_DIR/licenses/Orbitron-OFL.txt" \;

# --- JetBrains Mono (official release, Apache 2.0) ---
say "fetching JetBrains Mono"
JB_VERSION="2.304"
curl -fsSL -o "$TMP_DIR/jbm.zip" \
    "https://download.jetbrains.com/fonts/JetBrainsMono-${JB_VERSION}.zip"
unzip -q -o "$TMP_DIR/jbm.zip" -d "$TMP_DIR/jbm"
find "$TMP_DIR/jbm" -type f -iname '*.ttf' -path '*ttf*' \
    -exec cp -v {} "$FONT_DIR/jetbrains-mono/" \;
find "$TMP_DIR/jbm" -type f -iname 'OFL.txt' \
    -exec cp -v {} "$FONT_DIR/licenses/JetBrainsMono-OFL.txt" \; 2>/dev/null || true

# --- VT323 (Google Fonts, OFL 1.1) ---
say "fetching VT323"
curl -fsSL -o "$TMP_DIR/vt323.zip" \
    "https://fonts.google.com/download?family=VT323"
unzip -q -o "$TMP_DIR/vt323.zip" -d "$TMP_DIR/vt323"
find "$TMP_DIR/vt323" -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
    -exec cp -v {} "$FONT_DIR/vt323/" \;
find "$TMP_DIR/vt323" -type f -iname 'OFL.txt' \
    -exec cp -v {} "$FONT_DIR/licenses/VT323-OFL.txt" \; 2>/dev/null || true

# --- Bibata Modern Ice cursor (GitHub release, GPL-3.0) ---
say "fetching Bibata Modern Ice cursor"
BIBATA_VER="2.0.6"
curl -fsSL -o "$TMP_DIR/bibata.tar.gz" \
    "https://github.com/ful1e5/Bibata_Cursor/releases/download/v${BIBATA_VER}/Bibata-Modern-Ice.tar.gz" \
    || say "bibata download failed — skip (not fatal)"
if [ -f "$TMP_DIR/bibata.tar.gz" ]; then
    mkdir -p "$REPO_ROOT/theming/icons/cursors"
    tar -xzf "$TMP_DIR/bibata.tar.gz" -C "$REPO_ROOT/theming/icons/cursors/"
fi

say "done"
ls -1 "$FONT_DIR"
printf '\n\e[36msummary:\e[0m\n'
find "$FONT_DIR" -type f \( -iname '*.ttf' -o -iname '*.otf' \) | wc -l | xargs printf '  %s font files\n'
find "$FONT_DIR/licenses" -type f | wc -l | xargs printf '  %s license files\n'
