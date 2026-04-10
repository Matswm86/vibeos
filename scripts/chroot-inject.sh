#!/usr/bin/env bash
# VibeOS chroot injection — runs INSIDE the cubic chroot terminal during ISO build.
#
# Usage (from within cubic's "Terminal" tab after selecting the Kubuntu 22.04 base):
#   git clone https://github.com/Matswm86/vibeos /opt/vibeos
#   cd /opt/vibeos && bash scripts/chroot-inject.sh
#
# This script is idempotent — re-runs are safe.
# Aborts on any failure (set -e).
set -euo pipefail

say()  { printf '\e[35m[chroot-inject]\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m  ✓\e[0m %s\n' "$*"; }
warn() { printf '\e[33m  !\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[31m  ✗\e[0m %s\n' "$*" >&2; exit 1; }

# Must be root inside chroot
[ "$(id -u)" -eq 0 ] || die "run as root inside cubic chroot"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
THEMING="$REPO/theming"
[ -d "$THEMING" ] || die "theming/ not found at $THEMING — is the repo cloned correctly?"

# =============================================================
# Step 1 — apt dependencies
# =============================================================
say "step 1 — apt dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    python3 python3-venv python3-pip python3-gi python3-requests \
    gir1.2-webkit2-4.0 gir1.2-gtklayershell-0.1 libgtk-layer-shell0 \
    nodejs git curl wget jq \
    docker.io build-essential libffi-dev libssl-dev \
    gh fastfetch \
    qt5-style-kvantum qt5-style-kvantum-themes \
    kvantum-qt5 kvantum \
    plymouth plymouth-themes \
    sddm \
    papirus-icon-theme \
    imagemagick librsvg2-bin \
    fonts-orbitron fonts-jetbrains-mono \
    unzip
ok "packages installed"

# =============================================================
# Step 2 — clone VibeOS into /opt
# =============================================================
say "step 2 — stage VibeOS source at /opt/vibeos"
if [ ! -d /opt/vibeos ]; then
    git clone https://github.com/Matswm86/vibeos /opt/vibeos
    ok "cloned"
else
    ( cd /opt/vibeos && git pull --ff-only )
    ok "already present — pulled updates"
fi
ln -sf /opt/vibeos/clippy /usr/local/lib/python3/dist-packages/clippy 2>/dev/null || true

# =============================================================
# Step 3 — drop theming pack into /usr/share paths
# =============================================================
say "step 3 — install theming pack to /usr/share"

# Plasma color scheme
install -Dm644 \
    "$THEMING/plasma/color-schemes/VibeOS-Neon.colors" \
    /usr/share/color-schemes/VibeOS-Neon.colors
ok "color scheme"

# Plasma desktoptheme
mkdir -p /usr/share/plasma/desktoptheme
cp -r "$THEMING/plasma/desktoptheme/VibeOS-Neon" /usr/share/plasma/desktoptheme/
ok "plasma desktoptheme"

# Aurorae window deco
mkdir -p /usr/share/aurorae/themes
cp -r "$THEMING/plasma/aurorae/themes/VibeOS-Neon" /usr/share/aurorae/themes/
ok "aurorae decoration"

# Kvantum — auto-detect upstream source from fallback chain, recolor in place
mkdir -p /usr/share/Kvantum/VibeOS-Neon
install -Dm644 \
    "$THEMING/plasma/Kvantum/VibeOS-Neon/VibeOS-Neon.kvconfig" \
    /usr/share/Kvantum/VibeOS-Neon/VibeOS-Neon.kvconfig
# kvantum-recolor.py (no-arg form) walks a fallback chain:
#   KvGnomeDark → KvFlatDark → KvAdapta → KvFlat → KvDarkRed → KvCurvesDark → KvOxygen
# It writes to <repo>/theming/plasma/Kvantum/VibeOS-Neon/VibeOS-Neon.svg by default.
# We redirect output straight to /usr/share via the 2-arg form once the source is known.
KV_SRC=$(python3 -c "
from scripts.kvantum_recolor_lookup import find_source
p = find_source()
print(p if p else '')
" 2>/dev/null || true)
# Fallback: inline Python, no sibling module needed
if [ -z "$KV_SRC" ]; then
    KV_SRC=$(python3 -c "
import pathlib
candidates = [
    '/usr/share/Kvantum/KvGnomeDark/KvGnomeDark.svg',
    '/usr/share/Kvantum/KvFlatDark/KvFlatDark.svg',
    '/usr/share/Kvantum/KvAdapta/KvAdapta.svg',
    '/usr/share/Kvantum/KvFlat/KvFlat.svg',
    '/usr/share/Kvantum/KvDarkRed/KvDarkRed.svg',
    '/usr/share/Kvantum/KvCurvesDark/KvCurvesDark.svg',
    '/usr/share/Kvantum/KvOxygen/KvOxygen.svg',
]
for c in candidates:
    if pathlib.Path(c).exists():
        print(c); break
")
fi
if [ -n "$KV_SRC" ] && [ -f "$KV_SRC" ]; then
    python3 "$REPO/scripts/kvantum-recolor.py" \
        "$KV_SRC" \
        /usr/share/Kvantum/VibeOS-Neon/VibeOS-Neon.svg
    ok "kvantum recolored from $(basename $(dirname "$KV_SRC"))"
else
    warn "no Kvantum upstream source found — install qt5-style-kvantum-themes or theme will render stock"
fi

# Konsole profile + colorscheme
mkdir -p /usr/share/konsole
install -Dm644 "$THEMING/konsole/VibeOS.colorscheme" /usr/share/konsole/VibeOS.colorscheme
install -Dm644 "$THEMING/konsole/VibeOS.profile"     /usr/share/konsole/VibeOS.profile
ok "konsole profile"

# SDDM login theme
mkdir -p /usr/share/sddm/themes
cp -r "$THEMING/sddm/vibeos" /usr/share/sddm/themes/
ok "sddm theme"

# GRUB theme (assets beyond theme.txt generated below)
mkdir -p /boot/grub/themes
cp -r "$THEMING/grub/vibeos" /boot/grub/themes/
ok "grub theme (text only — background PNG generated below)"

# Plymouth theme
mkdir -p /usr/share/plymouth/themes
cp -r "$THEMING/plymouth/vibeos" /usr/share/plymouth/themes/
ok "plymouth theme"

# Fonts
if [ -d "$THEMING/fonts" ] && compgen -G "$THEMING/fonts/**/*.ttf" >/dev/null 2>&1; then
    mkdir -p /usr/share/fonts/truetype/vibeos
    find "$THEMING/fonts" -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
        -exec cp {} /usr/share/fonts/truetype/vibeos/ \;
    fc-cache -f /usr/share/fonts/truetype/vibeos
    ok "fonts cached"
else
    warn "no local fonts in theming/fonts/ — relying on fonts-orbitron + fonts-jetbrains-mono from apt"
fi

# Wallpapers
if [ -d "$THEMING/wallpapers" ] && compgen -G "$THEMING/wallpapers/*.jpg" >/dev/null 2>&1; then
    mkdir -p /usr/share/wallpapers/VibeOS
    cp "$THEMING/wallpapers"/*.jpg /usr/share/wallpapers/VibeOS/ 2>/dev/null || true
    [ -f /usr/share/wallpapers/VibeOS/vibeos-default.jpg ] || \
        ln -sf "$(find /usr/share/wallpapers/VibeOS -maxdepth 1 -type f | head -1)" \
               /usr/share/wallpapers/VibeOS/vibeos-default.jpg
    ok "wallpapers installed"
else
    warn "no wallpapers in theming/wallpapers/ — run scripts/fetch-wallpapers.sh before ISO build"
fi

# Fastfetch
install -Dm644 "$THEMING/fastfetch/config.jsonc" /etc/fastfetch/config.jsonc
install -Dm644 "$THEMING/fastfetch/vibeos.txt"   /usr/share/fastfetch/vibeos.txt
ok "fastfetch config"

# VibeOS logo pixmap (SVG — KDE + most freedesktop tools accept SVG)
install -Dm644 "$THEMING/os-release/vibeos-logo.svg" /usr/share/pixmaps/vibeos-logo.svg
# Also rasterize to PNG if rsvg-convert is available
if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 256 -h 256 "$THEMING/os-release/vibeos-logo.svg" \
        -o /usr/share/pixmaps/vibeos-logo.png
    ok "logo PNG rasterized"
fi

# =============================================================
# Step 3.5 — rasterize stub PNGs for Plymouth / GRUB / SDDM
# =============================================================
say "step 3.5 — rasterize boot-stage stub PNGs"

SRC_SVG="$THEMING/os-release/vibeos-logo.svg"
if ! command -v rsvg-convert >/dev/null 2>&1; then
    warn "rsvg-convert missing — skipping raster generation. Install librsvg2-bin"
elif ! command -v convert >/dev/null 2>&1; then
    warn "ImageMagick convert missing — skipping raster generation. Install imagemagick"
else
    # --- Plymouth: vibeos-logo.png (wordmark centered) + progress-dot.png ---
    PLY_DIR=/usr/share/plymouth/themes/vibeos
    rsvg-convert -w 512 -h 256 "$SRC_SVG" -o "$PLY_DIR/vibeos-logo.png" || \
        warn "plymouth logo raster failed"
    convert -size 16x16 xc:none -fill '#01F9FF' \
        -draw 'circle 8,8 8,1' "$PLY_DIR/progress-dot.png" || \
        warn "progress-dot raster failed"
    ok "plymouth PNGs generated"

    # --- SDDM: background.png (1920x1080 radial gradient + grid) ---
    SDDM_DIR=/usr/share/sddm/themes/vibeos
    convert -size 1920x1080 \
        radial-gradient:'#1A0B2E-#0B0218' \
        -fill '#01F9FF' -stroke '#01F9FF' -strokewidth 1 \
        "$SDDM_DIR/background.png" 2>/dev/null || \
        convert -size 1920x1080 xc:'#0B0218' "$SDDM_DIR/background.png"
    ok "sddm background rendered"

    # --- GRUB: background.png + 9-patch terminal/select/progress tiles ---
    GRUB_DIR=/boot/grub/themes/vibeos
    convert -size 1920x1080 \
        radial-gradient:'#1A0B2E-#0B0218' \
        "$GRUB_DIR/background.png" 2>/dev/null || \
        convert -size 1920x1080 xc:'#0B0218' "$GRUB_DIR/background.png"

    # 9-patch tiles: GRUB expects <prefix>_c.png (center), _n/_s/_e/_w, and 4 corners.
    # Minimum viable: center tile + matching named variants. Solid neon fills.
    for prefix in terminal_box select progress_bar progress_highlight; do
        case "$prefix" in
            terminal_box)
                fill='#1A0B2ECC'; stroke='#01F9FF' ;;
            select)
                fill='#2D1B4EAA'; stroke='#FF2ECF' ;;
            progress_bar)
                fill='#1A0B2E';   stroke='#01F9FF' ;;
            progress_highlight)
                fill='#FF2ECF';   stroke='#FF71CE' ;;
        esac
        # 9-patch suffixes for this prefix
        for suffix in c n s e w nw ne sw se; do
            convert -size 16x16 xc:none -fill "$fill" \
                -draw "rectangle 0,0 15,15" \
                "$GRUB_DIR/${prefix}_${suffix}.png" 2>/dev/null || true
        done
    done
    ok "grub 9-patch tiles generated"

    # GRUB wants TTF fonts converted to .pf2 via grub-mkfont. Fall back gracefully.
    # Orbitron upstream is now variable-font only; apt's fonts-orbitron package
    # still ships static weights. Try Bold first (matches theme.txt), then any
    # Orbitron TTF, then variable font.
    if command -v grub-mkfont >/dev/null 2>&1; then
        FONT_ORBITRON=$(find /usr/share/fonts -iname 'Orbitron*Bold*.ttf' 2>/dev/null | head -1 || true)
        [ -z "$FONT_ORBITRON" ] && FONT_ORBITRON=$(find /usr/share/fonts -iname 'Orbitron-VariableFont*.ttf' 2>/dev/null | head -1 || true)
        [ -z "$FONT_ORBITRON" ] && FONT_ORBITRON=$(find /usr/share/fonts -iname 'Orbitron*.ttf' 2>/dev/null | head -1 || true)

        FONT_JBMONO=$(find /usr/share/fonts -iname 'JetBrainsMono-Regular.ttf' 2>/dev/null | head -1 || true)
        [ -z "$FONT_JBMONO" ] && FONT_JBMONO=$(find /usr/share/fonts -iname 'JetBrainsMono*Regular*.ttf' 2>/dev/null | head -1 || true)
        [ -z "$FONT_JBMONO" ] && FONT_JBMONO=$(find /usr/share/fonts -iname 'JetBrainsMono*.ttf' 2>/dev/null | head -1 || true)

        if [ -n "$FONT_ORBITRON" ]; then
            # Use one name ("unicode") per size — grub-mkfont embeds the family
            # name from the TTF, so theme.txt just needs to match whichever it reports
            grub-mkfont -s 36 -o "$GRUB_DIR/orbitron-36.pf2" "$FONT_ORBITRON" 2>/dev/null && \
                grub-mkfont -s 18 -o "$GRUB_DIR/orbitron-18.pf2" "$FONT_ORBITRON" 2>/dev/null && \
                ok "grub orbitron font baked from $(basename "$FONT_ORBITRON")"
        else
            warn "Orbitron TTF not found for grub-mkfont — menu will use default font"
        fi
        if [ -n "$FONT_JBMONO" ]; then
            grub-mkfont -s 14 -o "$GRUB_DIR/jbmono-14.pf2" "$FONT_JBMONO" 2>/dev/null && \
                grub-mkfont -s 12 -o "$GRUB_DIR/jbmono-12.pf2" "$FONT_JBMONO" 2>/dev/null && \
                ok "grub jetbrains mono font baked from $(basename "$FONT_JBMONO")"
        fi
    else
        warn "grub-mkfont missing — install grub-common"
    fi
fi

# =============================================================
# Step 4 — rebrand OS identity files
# =============================================================
say "step 4 — rebrand OS identity"
install -m644 "$THEMING/os-release/os-release"  /etc/os-release
install -m644 "$THEMING/os-release/lsb-release" /etc/lsb-release
install -m644 "$THEMING/os-release/issue"       /etc/issue
install -m755 "$THEMING/os-release/00-header"   /etc/update-motd.d/00-header
ok "os-release, lsb-release, issue, motd header"

# =============================================================
# Step 5 — /etc/skel default user settings
# =============================================================
say "step 5 — default KDE config in /etc/skel"
mkdir -p /etc/skel/.config/autostart /etc/skel/.config/Kvantum
cp -r "$THEMING/skel/.config/"* /etc/skel/.config/
ok "skel configs installed"

# =============================================================
# Step 6 — set Plymouth + GRUB defaults
# =============================================================
say "step 6 — activate Plymouth + GRUB + SDDM themes"
plymouth-set-default-theme vibeos || warn "plymouth-set-default-theme failed"
update-initramfs -u -k all || warn "initramfs update failed (may be ok in chroot)"
ok "plymouth set"

# GRUB: point at vibeos theme if theme.txt exists
if [ -f /boot/grub/themes/vibeos/theme.txt ]; then
    sed -i 's|^#*GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/vibeos/theme.txt"|' /etc/default/grub || true
    # Drop any custom GRUB_BACKGROUND override so the theme's background wins
    sed -i 's|^GRUB_BACKGROUND=.*||' /etc/default/grub || true
    if ! grep -q '^GRUB_THEME=' /etc/default/grub; then
        echo 'GRUB_THEME="/boot/grub/themes/vibeos/theme.txt"' >> /etc/default/grub
    fi
    update-grub || warn "update-grub failed (may be ok in chroot without devices)"
    ok "grub theme wired"
fi

# SDDM: set default theme to vibeos via drop-in
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/vibeos.conf <<'EOF'
[Theme]
Current=vibeos
CursorTheme=Bibata-Modern-Ice
Font=Orbitron
EOF
ok "sddm default theme set"

# =============================================================
# Step 7 — autostart Vibbey on first login for every new user
# =============================================================
say "step 7 — vibbey autostart propagated via /etc/skel"
[ -f /etc/skel/.config/autostart/vibeos-first-run.desktop ] \
    && ok "autostart entry present in /etc/skel" \
    || warn "autostart entry NOT in /etc/skel — Vibbey will not auto-launch"

# =============================================================
# Step 8 — report
# =============================================================
printf '\n\e[36m=== chroot inject complete ===\e[0m\n'
printf '  os-release:    %s\n' "$(awk -F= '/^PRETTY_NAME/ {gsub(/\"/,""); print $2}' /etc/os-release)"
printf '  color scheme:  %s\n' "$( [ -f /usr/share/color-schemes/VibeOS-Neon.colors ] && echo installed || echo MISSING )"
printf '  plasma theme:  %s\n' "$( [ -d /usr/share/plasma/desktoptheme/VibeOS-Neon ] && echo installed || echo MISSING )"
printf '  aurorae deco:  %s\n' "$( [ -d /usr/share/aurorae/themes/VibeOS-Neon ] && echo installed || echo MISSING )"
printf '  kvantum:       %s\n' "$( [ -f /usr/share/Kvantum/VibeOS-Neon/VibeOS-Neon.svg ] && echo installed || echo partial )"
printf '  sddm theme:    %s\n' "$( [ -d /usr/share/sddm/themes/vibeos ] && echo installed || echo MISSING )"
printf '  plymouth:      %s\n' "$(plymouth-set-default-theme 2>/dev/null || echo unknown)"
printf '  vibbey auto:   %s\n' "$( [ -f /etc/skel/.config/autostart/vibeos-first-run.desktop ] && echo installed || echo MISSING )"

printf '\nexit the chroot terminal (Ctrl+D) and let cubic finish the ISO build.\n'
