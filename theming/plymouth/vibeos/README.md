# VibeOS Plymouth splash

## Required PNGs (not checked in)

- `vibeos-logo.png` — 512x256, VibeOS wordmark centered, transparent background.
  Generate from `theming/os-release/vibeos-logo.svg` at build time via Inkscape
  or rsvg-convert.
- `progress-dot.png` — 16x16 solid cyan dot (`#01F9FF`), transparent background.
  Single pixel generated via ImageMagick: `convert -size 16x16 xc:none -fill '#01F9FF' -draw 'circle 8,8 8,0' progress-dot.png`

## Installing

```bash
sudo cp -r theming/plymouth/vibeos /usr/share/plymouth/themes/
sudo plymouth-set-default-theme vibeos
sudo update-initramfs -u
```

## Testing without rebooting

```bash
plymouthd --debug --no-daemon --tty=/dev/tty7 &
plymouth --show-splash
sleep 5
plymouth --quit
```
