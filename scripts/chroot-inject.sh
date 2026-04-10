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

# Kvantum — fork + recolor KvGnomeDark into VibeOS-Neon
mkdir -p /usr/share/Kvantum/VibeOS-Neon
install -Dm644 \
    "$THEMING/plasma/Kvantum/VibeOS-Neon/VibeOS-Neon.kvconfig" \
    /usr/share/Kvantum/VibeOS-Neon/VibeOS-Neon.kvconfig
if [ -f /usr/share/Kvantum/KvGnomeDark/KvGnomeDark.svg ]; then
    python3 "$REPO/scripts/kvantum-recolor.py" \
        /usr/share/Kvantum/KvGnomeDark/KvGnomeDark.svg \
        /usr/share/Kvantum/VibeOS-Neon/VibeOS-Neon.svg
    ok "kvantum recolored"
else
    warn "KvGnomeDark base SVG missing — Kvantum theme will render default until fixed"
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
