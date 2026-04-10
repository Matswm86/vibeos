#!/usr/bin/env bash
# Generate VibeOS synthetic wallpaper set (pure Python / Pillow).
#
# Why synthetic instead of curated downloads:
#   - Pixabay/Unsplash hotlink-block with 403s as of 2026-04
#   - The Neon Grid palette is trivially synthesizable
#   - No network dependency → reproducible + offline-friendly
#   - cc0 by construction (we authored it)
#
# Requires: python3 + Pillow (PIL). Pop!_OS 24.04 ships with both.
#
# Run from repo root: bash scripts/fetch-wallpapers.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WP_DIR="$REPO_ROOT/theming/wallpapers"
mkdir -p "$WP_DIR"

say() { printf '  \e[35m→\e[0m %s\n' "$*"; }
die() { printf '  \e[31m✗\e[0m %s\n' "$*" >&2; exit 1; }

python3 -c "from PIL import Image" 2>/dev/null || \
    die "Pillow (python3-pil) missing — apt install python3-pil"

say "generating synthetic Neon Grid wallpapers via Pillow"
python3 "$REPO_ROOT/scripts/generate_wallpapers.py" "$WP_DIR"

# Write sha256 for each output
for f in "$WP_DIR"/*.jpg; do
    [ -f "$f" ] || continue
    sha256sum "$f" | awk '{print $1}' > "${f}.sha256"
done

# Default symlink
if [ -f "$WP_DIR/01-neon-grid.jpg" ]; then
    ( cd "$WP_DIR" && ln -sf "01-neon-grid.jpg" "vibeos-default.jpg" )
fi

# CREDITS
cat > "$WP_DIR/CREDITS.md" <<'EOF'
# VibeOS Wallpaper Credits

All wallpapers in this directory are **synthetically generated** by
`scripts/generate_wallpapers.py` via Pillow. No external assets are
bundled; every pixel is produced by a deterministic script from the
VibeOS Neon Grid palette.

## License

Creative Commons Zero (CC0 / public domain). You may use, modify, and
redistribute these wallpapers for any purpose without attribution.

## Provenance

| File | Base palette | Grid color | Grid step | Accent |
|---|---|---|---|---|
| 01-neon-grid.jpg | midnight → near-black | cyan | 64 px | magenta |
| 02-tron-horizon.jpg | plum → near-black | cyan | 80 px | cyan |
| 03-sunset-wave.jpg | midnight → near-black | magenta | 72 px | hot pink |
| 04-orbital-grid.jpg | plum → midnight | violet | 48 px | cyan |
| 05-neon-void.jpg | near-black → black | cyan | 96 px | mint |

## Regenerating

```bash
bash scripts/fetch-wallpapers.sh
```

Output is deterministic; sha256 files record expected checksums.
EOF

printf '\n\e[36msummary:\e[0m\n'
COUNT=$(find "$WP_DIR" -maxdepth 1 -type f -iname '*.jpg' | wc -l)
SIZE=$(du -sh "$WP_DIR" 2>/dev/null | awk '{print $1}')
printf '  %s wallpapers\n' "$COUNT"
printf '  %s total\n' "$SIZE"
