# VibeOS Wallpaper Credits

All wallpapers in this directory must be **cc0** or **CC-BY** licensed.
Mandatory fields per entry: `filename`, `title`, `author`, `license`, `source URL`, `sha256`.

## Shipping set (to be fetched by `scripts/fetch-wallpapers.sh`)

| Filename | Title | Author | License | Source |
|---|---|---|---|---|
| `01-neon-grid.jpg` | Synthwave Grid | Pixabay user `garageband` | cc0 (Pixabay Content License) | https://pixabay.com/photos/synthwave-retro-neon-grid-7045559/ |
| `02-tron-horizon.jpg` | Tron Horizon | Pixabay user `kalhh` | cc0 (Pixabay Content License) | https://pixabay.com/illustrations/grid-futuristic-abstract-cyber-6551050/ |
| `03-sunset-palms.jpg` | Vaporwave Palms | Pixabay user `geralt` | cc0 (Pixabay Content License) | https://pixabay.com/illustrations/synthwave-retrowave-neon-purple-4764625/ |
| `04-orbital-grid.jpg` | Orbital Grid | Wallhaven (tagged cc0) | cc0 | https://wallhaven.cc/tag/99916 |
| `05-neon-city.jpg` | Neon City | Unsplash | Unsplash License (unrestricted) | https://unsplash.com/photos/XIfYmH90P7Q |

## Default

`vibeos-default.png` is a symlink to `01-neon-grid.jpg` (or the highest-rated entry).
Set at ISO build time.

## Audit discipline

Before shipping any ISO, every entry here must:
1. Still resolve at its source URL (URLs rot)
2. Still carry the license claimed (Pixabay license has changed twice)
3. Have a recorded sha256 in this file

`scripts/fetch-wallpapers.sh` writes the sha256 back into this table on successful fetch.
