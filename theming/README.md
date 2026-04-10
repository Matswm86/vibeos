# VibeOS Theming Pack — "Neon Grid"

All visual assets that make Kubuntu 22.04 LTS wear VibeOS identity.
Targets **KDE Plasma 5.24 LTS** (Kubuntu 22.04's default).

## Palette

```
Primary       Magenta       #FF2ECF   accent, buttons, focus rings
Primary-hi    Hot pink      #FF71CE   hover states
Secondary     Electric cyan #01F9FF   secondary accent, links, rim light
Tertiary      Violet        #9D4EDD   selection, highlights
Background-0  Near-black    #0B0218   wallpaper void
Background-1  Midnight      #1A0B2E   window chrome
Background-2  Plum          #2D1B4E   cards, terminal bg
Foreground    Off-white     #F8F0FF   primary text
Muted         Lavender      #B5A6D9   secondary text
Warning       Neon yellow   #FFE400   warnings, Vibbey brand accent
Success       Mint neon     #05FFA1   success states
Grid line     Cyan 40%      #01F9FF66 wallpaper grid, Tron accents
```

Reference: Kavinsky × Tron: Legacy × tasteful Clippy reboot.

## Directory layout

```
theming/
├── plasma/
│   ├── color-schemes/       VibeOS-Neon.colors               → /usr/share/color-schemes/
│   ├── desktoptheme/        VibeOS-Neon/ (panel/widget SVGs) → /usr/share/plasma/desktoptheme/
│   ├── aurorae/themes/      VibeOS-Neon/ (window deco)       → /usr/share/aurorae/themes/
│   └── Kvantum/             VibeOS-Neon/ (GTK+Qt unify)      → /usr/share/Kvantum/
├── konsole/                 VibeOS.{profile,colorscheme}     → /usr/share/konsole/
├── sddm/vibeos/             SDDM login theme (QML)           → /usr/share/sddm/themes/vibeos/
├── grub/vibeos/             GRUB boot menu theme             → /boot/grub/themes/vibeos/
├── plymouth/vibeos/         Plymouth boot splash             → /usr/share/plymouth/themes/vibeos/
├── fonts/                   Orbitron, JetBrains Mono, VT323  → /usr/share/fonts/truetype/vibeos/
├── wallpapers/              cc0/CC-BY synthwave packs        → /usr/share/wallpapers/VibeOS/
├── fastfetch/               config.jsonc + ASCII logo        → /etc/fastfetch/ + /usr/share/fastfetch/
├── os-release/              os-release, lsb-release, issue   → /etc/*
├── skel/                    Default user config (kdeglobals, plasmarc, kwinrc, konsolerc, Kvantum, autostart) → /etc/skel/.config/
└── icons/                   Icon theme stub (see TODO)
```

## Provenance

| Asset | License | Source |
|---|---|---|
| Orbitron | SIL OFL 1.1 | Matt McInerney, Google Fonts |
| JetBrains Mono | Apache 2.0 | JetBrains s.r.o. |
| VT323 | SIL OFL 1.1 | Peter Hull, Google Fonts |
| Bibata Modern Ice cursor | GPL-3.0 | github.com/ful1e5/Bibata_Cursor |
| Breeze (theme base for forks) | LGPL 2.1+ | KDE |
| Plasma theme pattern | LGPL 2.1+ | KDE |
| Synthwave wallpapers | cc0 / CC-BY | see `wallpapers/CREDITS.md` |

## Testing (not possible on dev workstation)

The dev workstation is Pop!_OS COSMIC — can't preview KDE artifacts locally.
Verification path: boot Kubuntu 22.04.5 in QEMU, drop `theming/` into `~/.local/share/`,
apply via `kcmshell5 colors`, `kcmshell5 kwindecoration`, etc. See handoff note.

## Not built yet

- **Icon theme fork**: Papirus-Dark recolor is thousands of SVGs; deferred. Ships as stub that falls back to Papirus-Dark upstream.
- **Plymouth PNG frames**: the .plymouth + .script config exists; the actual 30-frame PNG sequence is placeholder.
- **GRUB background PNG**: theme.txt exists; background image is placeholder.
- **SDDM background**: theme.conf exists; background image is placeholder.

These are replaced when a real KDE session is available for iteration.
