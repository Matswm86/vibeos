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
# NOTE: Kubuntu 22.04 (jammy) does NOT ship the following packages — they
# were added in newer Ubuntu releases. We handle each out-of-band:
#   - fastfetch         → .deb from GitHub release (fetched below)
#   - fonts-orbitron    → shipped via theming/fonts/orbitron/ in our repo
#   - fonts-jetbrains-mono → shipped via theming/fonts/jetbrains-mono/
#   - kvantum / kvantum-qt5 → jammy uses qt5-style-kvantum (already listed)
apt-get install -y \
    python3 python3-venv python3-pip python3-gi python3-requests \
    gir1.2-webkit2-4.0 gir1.2-gtklayershell-0.1 libgtk-layer-shell0 \
    nodejs git curl wget jq \
    docker.io build-essential libffi-dev libssl-dev \
    gh \
    qt5-style-kvantum qt5-style-kvantum-themes \
    plymouth plymouth-themes \
    sddm \
    papirus-icon-theme \
    imagemagick librsvg2-bin \
    unzip
ok "apt packages installed"

# --- fastfetch: not in jammy, pin a GitHub release .deb ---
say "step 1b — install fastfetch from GitHub release"
FASTFETCH_VER="2.14.0"
FASTFETCH_URL="https://github.com/fastfetch-cli/fastfetch/releases/download/${FASTFETCH_VER}/fastfetch-linux-amd64.deb"
if command -v fastfetch >/dev/null 2>&1; then
    ok "fastfetch already installed"
elif curl -fsSL -o /tmp/fastfetch.deb "$FASTFETCH_URL"; then
    if dpkg -i /tmp/fastfetch.deb 2>&1 | tee /tmp/dpkg.log; then
        ok "fastfetch ${FASTFETCH_VER} installed"
    else
        # dpkg may complain about missing deps — apt-get -f install fixes them
        apt-get install -f -y
        ok "fastfetch installed after dep fix"
    fi
    rm -f /tmp/fastfetch.deb /tmp/dpkg.log
else
    warn "fastfetch download failed — terminal will use default greeting"
fi

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
        # GRUB matches `font = "Family Style Size"` in theme.txt against the
        # pf2 file's embedded family-name string (NOT the filename). Without
        # -n, grub-mkfont inherits whatever name the TTF itself advertises —
        # often "Orbitron" instead of "Orbitron Bold 36", which causes GRUB
        # to fall back to its built-in unicode font and render the menu as
        # garbled placeholder glyphs / circles. Explicit -n with the exact
        # name from theme.txt guarantees a match.
        FONT_ORBITRON_BOLD=$(find /usr/share/fonts -iname 'Orbitron*Bold*.ttf' 2>/dev/null | head -1 || true)
        FONT_ORBITRON_REG=$(find /usr/share/fonts -iname 'Orbitron-Regular.ttf' 2>/dev/null | head -1 || true)
        [ -z "$FONT_ORBITRON_REG" ] && FONT_ORBITRON_REG=$(find /usr/share/fonts -iname 'Orbitron-VariableFont*.ttf' 2>/dev/null | head -1 || true)
        [ -z "$FONT_ORBITRON_REG" ] && FONT_ORBITRON_REG=$(find /usr/share/fonts -iname 'Orbitron*.ttf' 2>/dev/null | head -1 || true)
        # If only a Bold variant exists, use it for Regular too (better than no font)
        [ -z "$FONT_ORBITRON_REG" ] && FONT_ORBITRON_REG="$FONT_ORBITRON_BOLD"
        # If only a Regular/Variable exists, use it for Bold too
        [ -z "$FONT_ORBITRON_BOLD" ] && FONT_ORBITRON_BOLD="$FONT_ORBITRON_REG"

        FONT_JBMONO=$(find /usr/share/fonts -iname 'JetBrainsMono-Regular.ttf' 2>/dev/null | head -1 || true)
        [ -z "$FONT_JBMONO" ] && FONT_JBMONO=$(find /usr/share/fonts -iname 'JetBrainsMono*Regular*.ttf' 2>/dev/null | head -1 || true)
        [ -z "$FONT_JBMONO" ] && FONT_JBMONO=$(find /usr/share/fonts -iname 'JetBrainsMono*.ttf' 2>/dev/null | head -1 || true)

        if [ -n "$FONT_ORBITRON_BOLD" ] && [ -n "$FONT_ORBITRON_REG" ]; then
            grub-mkfont -n "Orbitron Bold 36"    -s 36 -o "$GRUB_DIR/orbitron-bold-36.pf2"    "$FONT_ORBITRON_BOLD" 2>/dev/null
            grub-mkfont -n "Orbitron Bold 18"    -s 18 -o "$GRUB_DIR/orbitron-bold-18.pf2"    "$FONT_ORBITRON_BOLD" 2>/dev/null
            grub-mkfont -n "Orbitron Regular 18" -s 18 -o "$GRUB_DIR/orbitron-regular-18.pf2" "$FONT_ORBITRON_REG"  2>/dev/null
            ok "grub orbitron fonts baked (bold=$(basename "$FONT_ORBITRON_BOLD"), reg=$(basename "$FONT_ORBITRON_REG"))"
        else
            warn "Orbitron TTF not found for grub-mkfont — menu will use default font"
        fi
        if [ -n "$FONT_JBMONO" ]; then
            grub-mkfont -n "JetBrains Mono Regular 14" -s 14 -o "$GRUB_DIR/jbmono-14.pf2" "$FONT_JBMONO" 2>/dev/null
            grub-mkfont -n "JetBrains Mono Regular 12" -s 12 -o "$GRUB_DIR/jbmono-12.pf2" "$FONT_JBMONO" 2>/dev/null
            ok "grub jetbrains mono font baked from $(basename "$FONT_JBMONO")"
        fi
    else
        warn "grub-mkfont missing — install grub-common"
    fi
fi

# =============================================================
# Step 3.6 — install + brand Calamares (replaces Ubiquity)
# =============================================================
# Kubuntu 22.04 ships Ubiquity (KDE frontend), not Calamares. Ubiquity
# rendered white-on-white during the first 0.4.0 test-fly (2026-04-11).
# Rather than try to theme Ubiquity (badly documented, KDE frontend
# uses Qt forms with hardcoded palette overrides), we install Calamares
# alongside Ubiquity, brand Calamares as VibeOS, and hide Ubiquity's
# desktop launcher so users only see the Calamares "Install VibeOS"
# icon. This is the same path Mint / Manjaro / EndeavourOS take.
say "step 3.6 — install + brand Calamares (replaces Ubiquity)"

CAL_BRANDING_SRC="$THEMING/calamares/branding/vibeos"
CAL_MODULES_SRC="$THEMING/calamares/modules"

if [ ! -d "$CAL_BRANDING_SRC" ]; then
    warn "Calamares branding source missing at $CAL_BRANDING_SRC — skipping"
else
    # ── Step 3.6a: install Calamares + a working settings pack ──
    # On jammy, `calamares-settings-ubuntu-common` is metadata only
    # — it does NOT drop /etc/calamares/. The package that ships an
    # actual /etc/calamares/settings.conf + modules is one of the
    # derivative-specific settings packages. We use lubuntu's because
    # it's Ubuntu-derived (so the install behavior matches what we
    # want) and it's the most-tested Calamares config in the jammy
    # repos. We then override branding: vibeos in 3.6c.
    #
    # NOTE: do NOT switch to calamares-settings-debian unless you also
    # patch out debian-specific packages/grub config — it'll try to
    # install Debian repos.
    if ! command -v calamares >/dev/null 2>&1; then
        say "  installing calamares"
        apt-get install -y calamares || \
            warn "apt install calamares failed — verify universe repo enabled"
    else
        ok "calamares binary already installed"
    fi

    if [ ! -f /etc/calamares/settings.conf ]; then
        say "  installing calamares-settings-lubuntu (drops /etc/calamares/*)"
        if apt-get install -y calamares-settings-lubuntu; then
            ok "calamares-settings-lubuntu installed"
        else
            warn "calamares-settings-lubuntu install failed — branding will not activate"
        fi
    else
        ok "/etc/calamares/settings.conf already present"
    fi

    if [ ! -d /etc/calamares ]; then
        warn "/etc/calamares still missing after install — skipping branding"
    else
        # ── Step 3.6b: drop VibeOS branding component ───────────
        mkdir -p /etc/calamares/branding/vibeos
        cp -r "$CAL_BRANDING_SRC"/* /etc/calamares/branding/vibeos/

        if command -v rsvg-convert >/dev/null 2>&1; then
            rsvg-convert -w 256 -h 256 \
                "$THEMING/os-release/vibeos-logo.svg" \
                -o /etc/calamares/branding/vibeos/vibeos-logo.png
            rsvg-convert -w 400 -h 400 \
                "$THEMING/os-release/vibeos-logo.svg" \
                -o /etc/calamares/branding/vibeos/welcome.png
            ok "branding logos rasterized"
        else
            warn "rsvg-convert missing — branding logo will be 1x1 placeholder"
            printf '\x89PNG\r\n\x1a\n' > /etc/calamares/branding/vibeos/vibeos-logo.png
            cp /etc/calamares/branding/vibeos/vibeos-logo.png \
               /etc/calamares/branding/vibeos/welcome.png
        fi

        # ── Step 3.6c: point settings.conf at vibeos branding ───
        # calamares-settings-ubuntu-common drops a default settings.conf;
        # we just rewrite the branding line.
        if [ -f /etc/calamares/settings.conf ]; then
            if grep -q '^branding:' /etc/calamares/settings.conf; then
                sed -i 's|^branding:.*|branding: vibeos|' /etc/calamares/settings.conf
            else
                printf '\nbranding: vibeos\n' >> /etc/calamares/settings.conf
            fi
            ok "calamares settings.conf points at vibeos branding"
        else
            warn "/etc/calamares/settings.conf not found — calamares-settings-ubuntu-common may have failed to drop one"
        fi

        # ── Step 3.6d: welcome.conf override (kills red banner) ─
        if [ -f "$CAL_MODULES_SRC/welcome.conf" ]; then
            mkdir -p /etc/calamares/modules
            install -Dm644 "$CAL_MODULES_SRC/welcome.conf" \
                /etc/calamares/modules/welcome.conf
            ok "welcome.conf override installed (internet check now soft)"
        fi

        # ── Step 3.6e: repoint Calamares desktop launcher icon ──
        for desktop in /usr/share/applications/calamares.desktop \
                       /usr/share/applications/install-debian.desktop \
                       /usr/share/applications/io.calamares.calamares.desktop; do
            if [ -f "$desktop" ]; then
                sed -i 's|^Icon=.*|Icon=vibeos-logo|' "$desktop" || true
                sed -i 's|^Name=.*|Name=Install VibeOS|' "$desktop" || true
                sed -i 's|^GenericName=.*|GenericName=System Installer|' "$desktop" || true
            fi
        done
        ok "calamares desktop launcher rebranded"

        # ── Step 3.6f: kill the Ubiquity boot hijack ────────────
        # CRITICAL: Ubiquity isn't launched from a .desktop file on
        # Kubuntu — it's a systemd unit (`ubiquity.service`) that
        # starts BEFORE display-manager.service via WantedBy=
        # graphical.target. ubiquity-dm then takes over the screen
        # and shows the "Try / Install" front page, hijacking the
        # boot before SDDM/Plasma ever start. NoDisplay=true on
        # .desktop files is irrelevant — must remove the systemd
        # symlink.
        #
        # First confirmed during 2026-04-11 test-fly: VibeOS Calamares
        # branding was shipped correctly in the squashfs but the user
        # never reached a Plasma desktop because ubiquity-dm hijacked.
        rm -fv /etc/systemd/system/graphical.target.wants/ubiquity.service \
            2>/dev/null || true
        ok "ubiquity.service systemd auto-launch disabled"

        # Disable legacy upstart job too (belt and suspenders)
        if [ -f /etc/init/ubiquity.conf ]; then
            mv /etc/init/ubiquity.conf /etc/init/ubiquity.conf.disabled
            ok "ubiquity upstart job disabled"
        fi

        # ── Step 3.6g: hide Ubiquity from casper-bottom ─────────
        # /usr/share/initramfs-tools/scripts/casper-bottom/25adduser
        # loops through a hardcoded list of installer .desktop files
        # and copies the FIRST FOUND one to ~/Desktop on the live
        # user. The list (in priority order):
        #   1. /usr/share/applications/ubiquity.desktop
        #   2. /usr/share/applications/kde4/ubiquity-kdeui.desktop  ← Kubuntu uses this
        #   3. /usr/share/applications/lubuntu-calamares.desktop    ← we want this
        #   4. /usr/share/applications/ubuntustudio-calamares.desktop
        #   5. /var/lib/snapd/desktop/applications/ubuntu-desktop-installer_*.desktop
        # We rename the kde4 one out of the way so casper falls
        # through to lubuntu-calamares.desktop, which we rebrand
        # below to say "Install VibeOS".
        if [ -f /usr/share/applications/kde4/ubiquity-kdeui.desktop ]; then
            mv /usr/share/applications/kde4/ubiquity-kdeui.desktop \
               /usr/share/applications/kde4/ubiquity-kdeui.desktop.disabled
            ok "ubiquity-kdeui.desktop hidden from casper-bottom"
        fi

        # ── Step 3.6h: rebrand lubuntu-calamares.desktop ────────
        # casper-bottom now copies THIS one to ~/Desktop on first
        # boot. Rewrite it to say "Install VibeOS" with our icon.
        LCD=/usr/share/applications/lubuntu-calamares.desktop
        if [ -f "$LCD" ]; then
            sed -i \
                -e 's|^Name=Install Lubuntu.*|Name=Install VibeOS|' \
                -e 's|^GenericName=.*|GenericName=Install VibeOS|' \
                -e 's|^Icon=calamares|Icon=vibeos-logo|' \
                -e 's|^Exec=.*|Exec=sudo -E calamares|' \
                "$LCD"
            # Strip all localized Name[xx] lines (they all say Lubuntu)
            sed -i '/^Name\[/d' "$LCD"
            ok "lubuntu-calamares.desktop rebranded as Install VibeOS"
        fi

        # ── Step 3.6i: drop our own Install VibeOS shortcut ─────
        # Belt-and-suspenders: also drop /etc/skel/Desktop/install-vibeos
        # in case casper-bottom logic changes between Kubuntu releases.
        if [ -f /usr/share/applications/calamares.desktop ]; then
            mkdir -p /etc/skel/Desktop
            cp /usr/share/applications/calamares.desktop \
               /etc/skel/Desktop/install-vibeos.desktop
            chmod +x /etc/skel/Desktop/install-vibeos.desktop
            ok "Install VibeOS shortcut in /etc/skel/Desktop"
        fi

        # ── Step 3.6j: patch calamares-logs-helper ──────────────
        # calamares-settings-lubuntu ships /usr/bin/calamares-logs-helper
        # with `set -ex` and a hardcoded /home/lubuntu/ path. This makes
        # the ENTIRE install fail at the very last step (log copying)
        # because the live user is vibeos, not lubuntu. Confirmed during
        # 2026-04-12 first successful install attempt.
        # Fix: remove set -e, make session.log path dynamic, add || true.
        if [ -f /usr/bin/calamares-logs-helper ]; then
            cat > /usr/bin/calamares-logs-helper <<'LOGSEOF'
#!/bin/sh
set -x
root=$1
install_dir=$root/var/log/installer
[ -d $install_dir ] || mkdir -p $install_dir
session_log="$(find /home -path '*/.cache/calamares/session.log' 2>/dev/null | head -1)"
[ -n "$session_log" ] && cp "$session_log" $install_dir/debug || true
cp /cdrom/.disk/info $install_dir/media-info 2>/dev/null || true
cp /var/log/casper.log $install_dir/casper.log 2>/dev/null || true
cp /var/log/syslog $install_dir/syslog 2>/dev/null || true
gzip --stdout $root/var/lib/dpkg/status > $install_dir/initial-status.gz 2>/dev/null || true
chmod 600 $install_dir/* 2>/dev/null
chmod 644 $install_dir/initial-status.gz 2>/dev/null
chmod 644 $install_dir/media-info 2>/dev/null
LOGSEOF
            chmod 755 /usr/bin/calamares-logs-helper
            ok "calamares-logs-helper patched (dynamic path, no set -e)"
        fi

        ok "calamares branded as VibeOS, ubiquity hidden"
    fi
fi

# =============================================================
# Step 3.7 — pin casper FLAVOUR so the live user is named "vibeos"
# =============================================================
# Casper derives the live username from /cdrom/.disk/info via:
#   FLAVOUR=$(cut -d' ' -f1 /cdrom/.disk/info | tr '[A-Z]' '[a-z]')
#   USERNAME=$FLAVOUR
# Cubic writes a .disk/info string like "vibeos-0.4.1 (20260412)",
# whose first word is "vibeos-0.4.1". Linux usernames can't contain
# dots, so useradd rejects it and 25adduser fails silently — leaving
# SDDM autologin (configured for User=vibeos) with no user to log in.
# Result: black screen + cursor (confirmed during 2026-04-12 test-fly).
#
# /etc/casper.conf has a hardcoded escape hatch: setting FLAVOUR to a
# non-empty string forces casper to use that exact value AND the
# adjacent USERNAME / USERFULLNAME / HOST values rather than parsing
# .disk/info. We pin all four to clean strings.
say "step 3.7 — pin casper FLAVOUR / USERNAME to vibeos"
if [ -f /etc/casper.conf ]; then
    sed -i \
        -e 's|^export USERNAME=.*|export USERNAME="vibeos"|' \
        -e 's|^export USERFULLNAME=.*|export USERFULLNAME="VibeOS Live User"|' \
        -e 's|^export HOST=.*|export HOST="vibeos"|' \
        -e 's|^export BUILD_SYSTEM=.*|export BUILD_SYSTEM="VibeOS"|' \
        -e 's|^# *export FLAVOUR=.*|export FLAVOUR="vibeos"|' \
        /etc/casper.conf
    # If the FLAVOUR line was missing entirely (some derivatives strip it),
    # append it.
    if ! grep -q '^export FLAVOUR=' /etc/casper.conf; then
        echo 'export FLAVOUR="vibeos"' >> /etc/casper.conf
    fi
    ok "casper.conf pinned (FLAVOUR=vibeos, USERNAME=vibeos)"
else
    warn "/etc/casper.conf not found — live user will be derived from .disk/info"
fi

# =============================================================
# Step 3.8 — pre-create vibeos user in squashfs (belt-and-braces)
# =============================================================
# Background: casper-bottom/25adduser is supposed to create the live
# user at boot via user-setup-apply, reading USERNAME from casper.conf.
# Confirmed during 2026-04-13 test-fly that 0.4.3 builds ship with a
# fully intact user-setup package AND pinned casper.conf, yet the
# vibeos user still fails to appear — both graphical session and TTY
# login reject it. Root cause is likely a silent debconf/env failure
# inside 25adduser (USERNAME not exported into the right subshell)
# that we cannot reliably fix from the chroot side.
#
# Fix: create the user NOW inside the squashfs. casper's runtime
# creation becomes redundant but harmless (useradd is idempotent when
# the user already exists; user-setup-apply will see the existing
# entry and skip). uid 999 matches casper's default so /home perms
# line up across a live-session → installed-system transition.
say "step 3.8 — pre-create vibeos user in squashfs"
if ! id vibeos >/dev/null 2>&1; then
    # Prefer uid 999 (matches casper default) but fall back to
    # auto-assign if something else already claimed it inside the
    # chroot (e.g. systemd-coredump, sssd). A non-999 uid is fine —
    # the user still exists, which is the point.
    if getent passwd 999 >/dev/null 2>&1; then
        warn "uid 999 already in use by $(getent passwd 999 | cut -d: -f1) — auto-assigning"
        useradd -m -s /bin/bash -U \
            -G sudo,audio,video,plugdev,netdev,lpadmin,dialout,cdrom \
            -c "VibeOS Live User" vibeos
    else
        useradd -m -s /bin/bash -u 999 -U \
            -G sudo,audio,video,plugdev,netdev,lpadmin,dialout,cdrom \
            -c "VibeOS Live User" vibeos
    fi
    passwd -d vibeos
    ok "vibeos user created (uid $(id -u vibeos), blank password)"
else
    ok "vibeos user already exists (uid $(id -u vibeos))"
fi
install -d -m0755 /etc/sudoers.d
echo "vibeos ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/vibeos
chmod 0440 /etc/sudoers.d/vibeos
ok "sudoers entry installed for vibeos"

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
# Step 5.5 — install Look-and-Feel package + system-wide xdg configs
# =============================================================
# Problem 0.4.2 → 0.4.3: dumping raw kwinrc/plasmarc/kdeglobals into
# /etc/skel with Backend=OpenGL + GLCore=true + an aurorae override
# caused KWin to crash at session start on MSI hardware → black screen
# + cursor. Fix: ship a proper Plasma Look-and-Feel package that KDE
# applies atomically via lookandfeeltool, plus system-wide fallback
# configs in /etc/xdg/. The /etc/xdg/kwinrc intentionally has NO
# Backend / GLCore / decoration override — KWin auto-detects a safe
# backend and L&F sets the decoration. Per-user skel now carries only
# genuinely per-user state (konsolerc, Kvantum kvconfig, autostart).
say "step 5.5 — install Plasma Look-and-Feel + /etc/xdg defaults"

# System-wide KDE fallbacks (read when ~/.config/<file> is absent)
mkdir -p /etc/xdg
for f in kdeglobals plasmarc kwinrc kcminputrc; do
    if [ -f "$THEMING/xdg/$f" ]; then
        install -Dm644 "$THEMING/xdg/$f" "/etc/xdg/$f"
    else
        warn "theming/xdg/$f missing — skipping"
    fi
done
ok "xdg defaults installed"

# Look-and-Feel package
LNF_SRC="$THEMING/plasma/look-and-feel/org.vibeos.neon"
LNF_DEST="/usr/share/plasma/look-and-feel/org.vibeos.neon"
if [ -d "$LNF_SRC" ] && [ -f "$LNF_SRC/metadata.desktop" ] && [ -f "$LNF_SRC/contents/defaults" ]; then
    mkdir -p /usr/share/plasma/look-and-feel
    cp -r "$LNF_SRC" /usr/share/plasma/look-and-feel/
    ok "look-and-feel package org.vibeos.neon installed"
else
    warn "Look-and-Feel package missing or malformed — system will use xdg fallbacks only"
fi

# Apply L&F as system default. lookandfeeltool needs a running DBus,
# which chroot usually lacks — try anyway and fall back to manual
# kwriteconfig5 of LookAndFeelPackage if the tool can't run. Both
# paths end up at the same key, so either is sufficient for first boot.
if command -v lookandfeeltool >/dev/null 2>&1; then
    lookandfeeltool -a org.vibeos.neon 2>/dev/null && \
        ok "lookandfeeltool applied org.vibeos.neon" || \
        warn "lookandfeeltool failed (chroot DBus limitation — xdg fallback covers it)"
else
    warn "lookandfeeltool not installed — relying on /etc/xdg + LookAndFeelPackage key"
fi

# Belt-and-suspenders: pin the L&F package via kwriteconfig5 so KDE
# auto-applies it on first session start even if lookandfeeltool didn't run.
if command -v kwriteconfig5 >/dev/null 2>&1; then
    kwriteconfig5 --file /etc/xdg/kdeglobals --group KDE \
        --key LookAndFeelPackage org.vibeos.neon || true
    ok "LookAndFeelPackage pinned in /etc/xdg/kdeglobals"
fi

# =============================================================
# Step 6 — set Plymouth + GRUB defaults
# =============================================================
say "step 6 — activate Plymouth + GRUB + SDDM themes"
# Jammy's `plymouth` package does NOT ship /usr/sbin/plymouth-set-default-theme
# (confirmed 2026-04-11 during first live Cubic run). Try the helper first; fall
# back to driving update-alternatives directly, which is literally what the
# helper does internally minus the initramfs rebuild.
VIBEOS_PLY=/usr/share/plymouth/themes/vibeos/vibeos.plymouth
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme vibeos || warn "plymouth-set-default-theme failed"
elif [ -f "$VIBEOS_PLY" ]; then
    # Alternative already exists on jammy — we just need to register + set
    update-alternatives --install \
        /usr/share/plymouth/themes/default.plymouth \
        default.plymouth \
        "$VIBEOS_PLY" 100 2>/dev/null || true
    update-alternatives --set default.plymouth "$VIBEOS_PLY" 2>/dev/null || \
        warn "update-alternatives --set failed"
    ok "plymouth alternative set via update-alternatives fallback"
else
    warn "Plymouth theme file $VIBEOS_PLY missing — theme install likely failed"
fi
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
    # Pin a graphics mode GRUB can actually render. "auto" lets GRUB ask
    # firmware for a native mode but on some hardware the returned mode has
    # no matching font, resulting in garbled/circle-glyph output. 1280x720
    # is a VESA baseline every UEFI and most legacy BIOSes can hit.
    # GRUB_GFXPAYLOAD_LINUX=keep lets Plymouth inherit the framebuffer.
    if grep -q '^GRUB_GFXMODE=' /etc/default/grub; then
        sed -i 's|^GRUB_GFXMODE=.*|GRUB_GFXMODE=1280x720,auto|' /etc/default/grub
    else
        echo 'GRUB_GFXMODE=1280x720,auto' >> /etc/default/grub
    fi
    if grep -q '^GRUB_GFXPAYLOAD_LINUX=' /etc/default/grub; then
        sed -i 's|^GRUB_GFXPAYLOAD_LINUX=.*|GRUB_GFXPAYLOAD_LINUX=keep|' /etc/default/grub
    else
        echo 'GRUB_GFXPAYLOAD_LINUX=keep' >> /etc/default/grub
    fi
    update-grub || warn "update-grub failed (may be ok in chroot without devices)"
    ok "grub theme wired (gfxmode 1280x720)"
fi

# GRUB cmdline: quiet noisy ACPI / firmware messages so the splash isn't
# preceded by a wall of harmless red errors. Users were reporting "ACPI
# error" before the boot menu — almost always benign table warnings, but
# they look alarming on first install. quiet+loglevel=3 hides them while
# leaving real failures (level 0-2) visible.
if [ -f /etc/default/grub ]; then
    if ! grep -q 'loglevel=' /etc/default/grub; then
        sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet loglevel=3"|' /etc/default/grub
        # Collapse the duplicate "quiet" if the default already had one
        sed -i 's| quiet quiet | quiet |g' /etc/default/grub
    fi
    update-grub || warn "update-grub failed (may be ok in chroot without devices)"
    ok "grub cmdline quieted"
fi

# SDDM: set default theme + autologin via drop-in
#
# IMPORTANT: Theme is set to `breeze` (Kubuntu default), NOT `vibeos`.
# The vibeos QML theme has known runtime issues that cause SDDM to
# fall back to a bare X server (black screen with cursor only),
# blocking the entire boot. Confirmed during 2026-04-12 test-fly.
# Re-enable vibeos theme only after Main.qml is verified in a live
# SDDM session — until then, breeze is the safe default.
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/vibeos.conf <<'EOF'
[Theme]
Current=breeze
CursorTheme=Bibata-Modern-Ice
Font=Noto Sans
EOF

# Live-session autologin: casper creates a user named after the
# lowercase first word of /cdrom/.disk/info ("VibeOS …" → "vibeos").
# Password is set to the "blank password" crypt hash by casper-bottom
# 25adduser, and /etc/pam.d/sddm-autologin already has pam_permit.so,
# so SDDM can log this user in without prompting.
cat > /etc/sddm.conf.d/99-vibeos-autologin.conf <<'EOF'
[Autologin]
User=vibeos
Session=plasma
Relogin=false

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot
EOF
ok "sddm theme=breeze + autologin user=vibeos"

# =============================================================
# Step 7 — autostart Vibbey on first login for every new user
# =============================================================
say "step 7 — vibbey autostart propagated via /etc/skel"
[ -f /etc/skel/.config/autostart/vibeos-first-run.desktop ] \
    && ok "autostart entry present in /etc/skel" \
    || warn "autostart entry NOT in /etc/skel — Vibbey will not auto-launch"

# =============================================================
# Step 7.5 — bake Ollama + a small local model into the ISO
# =============================================================
# Why: Vibbey defaults to Groq cloud, but on first boot the user might
# be offline (no Wi-Fi yet) or might have declined cloud mode. Bundling
# a small local model means Vibbey works end-to-end with zero internet
# and zero API key. ~2 GB cost for qwen2.5:3b — still fits a 8 GB USB.
#
# Set VIBEOS_BAKE_OLLAMA=0 to skip (e.g. lean ISO variant).
say "step 7.5 — install Ollama + pull local fallback model"
if [ "${VIBEOS_BAKE_OLLAMA:-1}" = "1" ]; then
    if ! command -v ollama >/dev/null 2>&1; then
        # Official installer is the only supported path; it sets up the
        # systemd unit and a dedicated `ollama` user automatically.
        curl -fsSL https://ollama.com/install.sh | sh \
            && ok "ollama installed" \
            || warn "ollama install failed — Vibbey will need internet for chat"
    else
        ok "ollama already present"
    fi

    if command -v ollama >/dev/null 2>&1; then
        # Pull happens at build time so the ISO ships the blob. The
        # systemd ollama.service must be running for `ollama pull` to
        # work — start it transiently inside the chroot.
        ollama serve >/tmp/ollama-serve.log 2>&1 &
        OLLAMA_PID=$!
        sleep 4
        # Default fallback model: qwen2.5:3b — smart enough for chat,
        # ~1.9 GB on disk. Override with VIBEOS_OLLAMA_MODEL.
        OLLAMA_MODEL="${VIBEOS_OLLAMA_MODEL:-qwen2.5:3b}"
        ollama pull "$OLLAMA_MODEL" \
            && ok "pulled $OLLAMA_MODEL" \
            || warn "ollama pull $OLLAMA_MODEL failed (network or daemon)"
        kill "$OLLAMA_PID" 2>/dev/null || true
        wait "$OLLAMA_PID" 2>/dev/null || true

        # Also flip Vibbey's default Ollama model to match what we pulled.
        # (groq_proxy.chat falls back to ollama_model="gemma3:4b" by default;
        # a stale name = "ollama_error: model not found" on first chat.)
        if [ -f /opt/vibeos/clippy/server.py ]; then
            sed -i "s|ollama_model = payload.get(\"model\", \"gemma3:4b\")|ollama_model = payload.get(\"model\", \"$OLLAMA_MODEL\")|" \
                /opt/vibeos/clippy/server.py || true
        fi

        # 0.4.3 post-install regression: ollama.service was not enabled on
        # first boot, so Vibbey chat came up with "Ollama is down". The
        # upstream installer creates the unit but `systemctl enable` runs
        # via a dbus call that silently no-ops inside a chroot. Force it
        # with the low-level symlink that enable would create.
        OLLAMA_UNIT=""
        [ -f /etc/systemd/system/ollama.service ] && OLLAMA_UNIT=/etc/systemd/system/ollama.service
        [ -z "$OLLAMA_UNIT" ] && [ -f /usr/lib/systemd/system/ollama.service ] && OLLAMA_UNIT=/usr/lib/systemd/system/ollama.service
        if [ -n "$OLLAMA_UNIT" ]; then
            # Ollama ships with `[Install] WantedBy=default.target`, so
            # `systemctl enable` creates the symlink under
            # default.target.wants, NOT multi-user.target.wants. Try the
            # proper tool first, then belt-and-suspenders link into
            # default.target.wants explicitly. Verify the symlink in
            # whichever location systemd used.
            mkdir -p /etc/systemd/system/default.target.wants \
                     /etc/systemd/system/multi-user.target.wants
            systemctl enable ollama.service 2>/dev/null || true
            if [ ! -L /etc/systemd/system/default.target.wants/ollama.service ] \
               && [ ! -L /etc/systemd/system/multi-user.target.wants/ollama.service ]; then
                ln -sf "$OLLAMA_UNIT" /etc/systemd/system/default.target.wants/ollama.service
            fi
            if [ -L /etc/systemd/system/default.target.wants/ollama.service ] \
               || [ -L /etc/systemd/system/multi-user.target.wants/ollama.service ]; then
                ok "ollama.service enabled for first boot"
            else
                warn "ollama.service enable failed — Vibbey will ask user to start it manually"
            fi
        else
            warn "ollama.service unit file missing — skip enable"
        fi
    fi
else
    say "step 7.5 skipped (VIBEOS_BAKE_OLLAMA=0)"
fi

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
printf '  calamares:     %s\n' "$( [ -f /etc/calamares/branding/vibeos/branding.desc ] && echo installed || echo MISSING )"
printf '  plymouth:      %s\n' "$(plymouth-set-default-theme 2>/dev/null || echo unknown)"
printf '  vibbey auto:   %s\n' "$( [ -f /etc/skel/.config/autostart/vibeos-first-run.desktop ] && echo installed || echo MISSING )"
printf '  ollama:        %s\n' "$( command -v ollama >/dev/null 2>&1 && echo installed || echo MISSING )"
printf '  ollama models: %s\n' "$( command -v ollama >/dev/null 2>&1 && (ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | xargs echo) || echo none )"

printf '\nexit the chroot terminal (Ctrl+D) and let cubic finish the ISO build.\n'
