# VibeOS-Neon Kvantum theme

## Status: colors-only, SVG generated at build time

The Kvantum engine needs an `.svg` file per theme. Authoring one from scratch
is thousands of widget fragments; forking an existing theme and doing color
substitution is the pragmatic path.

**Strategy**: at ISO build time inside the cubic chroot, `scripts/kvantum-recolor.py`
forks `/usr/share/Kvantum/KvGnomeDark/KvGnomeDark.svg` (installed by
`qt5-style-kvantum-themes`) and runs a pinned color replacement table to
produce `VibeOS-Neon.svg` in this directory.

## Files

- `VibeOS-Neon.kvconfig` — color scheme + layout tuning (hand-authored, ships as-is)
- `VibeOS-Neon.svg` — **generated at build time**, not checked in

## Colors mapped

KvGnomeDark hex → VibeOS-Neon hex:

```
#2b2b2b (window bg)       → #1A0B2E  Midnight
#1b1b1b (darker bg)       → #0B0218  Near-black
#3b3b3b (button)          → #2D1B4E  Plum
#5a5a5a (border)          → #9D4EDD  Violet
#787878 (mid)             → #5A3A8A  muted violet
#b7b7b7 (text-ish)        → #B5A6D9  Lavender
#eeeeee (foreground)      → #F8F0FF  Off-white
#3daee9 (blue accent)     → #01F9FF  Cyan
#7aaed6 (hover accent)    → #FF71CE  Hot pink
#1e7ec0 (pressed accent)  → #FF2ECF  Magenta
```

## Applying manually

After install:
```bash
kvantummanager --set VibeOS-Neon
```
