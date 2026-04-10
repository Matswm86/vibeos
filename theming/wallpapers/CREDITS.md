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
