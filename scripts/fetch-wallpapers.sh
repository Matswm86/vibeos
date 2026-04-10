#!/usr/bin/env bash
# Fetch VibeOS default wallpaper set.
#
# Policy: every file must be cc0 or CC-BY. URLs below are curated; if any 404s
# or changes license, fix CREDITS.md *before* re-running.
#
# Run from repo root: bash scripts/fetch-wallpapers.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WP_DIR="$REPO_ROOT/theming/wallpapers"

mkdir -p "$WP_DIR"

say() { printf '  \e[35m→\e[0m %s\n' "$*"; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*" >&2; }

# Pixabay direct-download URLs need a user-agent; they also redirect through a CDN.
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) VibeOS-fetch/0.4.0"

fetch() {
    local filename="$1" url="$2"
    if [ -s "$WP_DIR/$filename" ]; then
        say "$filename already present — skip"
        return 0
    fi
    say "fetching $filename"
    if ! curl -fsSL -A "$USER_AGENT" -o "$WP_DIR/$filename.tmp" "$url"; then
        warn "failed to fetch $filename from $url"
        rm -f "$WP_DIR/$filename.tmp"
        return 1
    fi
    mv "$WP_DIR/$filename.tmp" "$WP_DIR/$filename"
    sha256sum "$WP_DIR/$filename" | awk '{print $1}' > "$WP_DIR/${filename}.sha256"
}

# Curated set — update CREDITS.md if anything here changes
fetch "01-neon-grid.jpg"   "https://cdn.pixabay.com/photo/2022/03/28/11/04/synthwave-7097045_1280.jpg"
fetch "02-tron-horizon.jpg" "https://cdn.pixabay.com/photo/2021/08/10/18/40/background-6538474_1280.jpg"
fetch "03-sunset-palms.jpg" "https://cdn.pixabay.com/photo/2020/01/24/21/33/retrowave-4791345_1280.jpg"
fetch "04-orbital-grid.jpg" "https://cdn.pixabay.com/photo/2019/04/21/14/35/background-4144828_1280.jpg"
fetch "05-neon-city.jpg"    "https://cdn.pixabay.com/photo/2022/01/11/21/48/cyberpunk-6931562_1280.jpg"

if [ -s "$WP_DIR/01-neon-grid.jpg" ]; then
    ( cd "$WP_DIR" && ln -sf "01-neon-grid.jpg" "vibeos-default.jpg" )
    say "default linked to 01-neon-grid.jpg"
fi

printf '\n\e[36msummary:\e[0m\n'
find "$WP_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) | wc -l | xargs printf '  %s wallpapers on disk\n'
du -sh "$WP_DIR" 2>/dev/null | awk '{printf "  %s total\n", $1}'

warn "URLs rot quickly — if anything 404'd, update CREDITS.md before rerunning"
