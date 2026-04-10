# VibeOS GRUB theme

## Required PNGs (not checked in — generate at build time)

GRUB's theme engine needs actual raster images; SVG is not supported.
The following PNGs must exist alongside `theme.txt` before booting:

- `background.png` — 1920x1080, neon grid over near-black (`#0B0218`).
  Use `scripts/generate-grub-background.py` (not yet written) or drop a
  synthwave wallpaper from `theming/wallpapers/` and overwrite.
- `terminal_box_c.png` + 8 corner/edge variants — the dark translucent
  box behind GRUB's built-in terminal + console.
- `select_c.png` + 8 corner/edge variants — the highlight around the
  selected menu item. 9-patch: center stretches, corners don't.
- `progress_bar_c.png` + variants — the empty progress bar frame.
- `progress_highlight_c.png` + variants — the filled portion.

## Generation strategy

At build time inside the cubic chroot, `scripts/chroot-inject.sh` will:

1. Copy `theming/wallpapers/vibeos-default.png` to `background.png` (resized)
2. Generate `terminal_box_*`, `select_*`, `progress_*` via a tiny ImageMagick
   pipeline producing 16x16 tiles with neon palette rects.

For now, this directory ships only `theme.txt` and this README.

## Applying (inside target system)

```bash
sudo cp -r theming/grub/vibeos /boot/grub/themes/
sudo sed -i 's|^#*GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/vibeos/theme.txt"|' /etc/default/grub
sudo sed -i 's|^GRUB_BACKGROUND=.*||' /etc/default/grub
sudo update-grub
```
