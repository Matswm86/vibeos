#!/usr/bin/env bash
# fix-calamares-live.sh — patch a running VibeOS live USB session so the
# Calamares installer becomes readable WITHOUT rebuilding the ISO.
#
# WHY THIS EXISTS
# ─────────────────────────────────────────────────────────────
# vibeos-0.4.0 shipped without a Calamares branding component.
# The installer renders white text on white widget backgrounds and
# briefly flashes a red "internet required" banner at startup.
#
# This script copies the in-repo branding into /etc/calamares/ on the
# live filesystem (which is tmpfs, so writes are allowed and survive
# until shutdown). Run it BEFORE clicking "Install VibeOS" on the
# desktop.
#
# USAGE (inside the running live USB):
#   sudo bash /path/to/scripts/fix-calamares-live.sh
#
# Or, if the repo isn't local yet:
#   sudo apt update && sudo apt install -y git librsvg2-bin
#   git clone https://github.com/Matswm86/vibeos /tmp/vibeos
#   sudo bash /tmp/vibeos/scripts/fix-calamares-live.sh
#
# After it finishes, close any open Calamares window and re-launch
# from the desktop. The new branding takes effect on next start.

set -euo pipefail

say()  { printf '\e[35m[fix-cal]\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m  ✓\e[0m %s\n' "$*"; }
warn() { printf '\e[33m  !\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[31m  ✗\e[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run with sudo"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
THEMING="$REPO/theming"
CAL_BRANDING_SRC="$THEMING/calamares/branding/vibeos"
CAL_MODULES_SRC="$THEMING/calamares/modules"
LOGO_SVG="$THEMING/os-release/vibeos-logo.svg"

[ -d "$CAL_BRANDING_SRC" ] || die "branding source missing: $CAL_BRANDING_SRC — wrong repo?"
[ -f "$LOGO_SVG" ]         || die "logo svg missing: $LOGO_SVG"

# Make sure Calamares is actually present
if [ ! -d /etc/calamares ]; then
    warn "/etc/calamares missing — Calamares not installed in this live session?"
    warn "Try: sudo apt install -y calamares calamares-settings-ubuntu"
    exit 1
fi

# Make sure rsvg-convert is around for logo rasterization
if ! command -v rsvg-convert >/dev/null 2>&1; then
    say "installing librsvg2-bin for logo rasterization"
    apt update -qq
    apt install -y librsvg2-bin
fi

# 1. Drop branding component
say "installing branding pack to /etc/calamares/branding/vibeos/"
mkdir -p /etc/calamares/branding/vibeos
cp -r "$CAL_BRANDING_SRC"/* /etc/calamares/branding/vibeos/

rsvg-convert -w 256 -h 256 "$LOGO_SVG" \
    -o /etc/calamares/branding/vibeos/vibeos-logo.png
rsvg-convert -w 400 -h 400 "$LOGO_SVG" \
    -o /etc/calamares/branding/vibeos/welcome.png
ok "branding files in place"

# 2. Patch settings.conf
say "pointing Calamares at the vibeos branding"
if [ -f /etc/calamares/settings.conf ]; then
    # Backup once
    [ -f /etc/calamares/settings.conf.vibeos-orig ] || \
        cp /etc/calamares/settings.conf /etc/calamares/settings.conf.vibeos-orig

    if grep -q '^branding:' /etc/calamares/settings.conf; then
        sed -i 's|^branding:.*|branding: vibeos|' /etc/calamares/settings.conf
    else
        printf '\nbranding: vibeos\n' >> /etc/calamares/settings.conf
    fi
    ok "settings.conf updated (original saved as settings.conf.vibeos-orig)"
else
    die "/etc/calamares/settings.conf missing"
fi

# 3. Drop welcome.conf override (silences red 'internet required' banner)
if [ -f "$CAL_MODULES_SRC/welcome.conf" ]; then
    [ -f /etc/calamares/modules/welcome.conf.vibeos-orig ] || \
        cp /etc/calamares/modules/welcome.conf \
           /etc/calamares/modules/welcome.conf.vibeos-orig 2>/dev/null || true
    install -Dm644 "$CAL_MODULES_SRC/welcome.conf" \
        /etc/calamares/modules/welcome.conf
    ok "welcome.conf override applied (internet check is now soft)"
fi

# 4. Kill any running Calamares so the next launch picks up the changes
if pgrep -x calamares >/dev/null 2>&1; then
    say "stopping running Calamares so it can pick up the new branding"
    pkill -x calamares || true
    sleep 1
fi

cat <<'EOF'

✅ Calamares is now branded as VibeOS for this live session.

Next steps:
  1. Close any open Calamares window (if it didn't close already).
  2. Double-click "Install VibeOS" on the desktop (or run: calamares).
  3. The installer should now show:
       • Dark purple background, light text — readable.
       • No red "danger" banner on the welcome page.
       • A short slideshow during install.

⚠ This patch lives in tmpfs and will be wiped on shutdown. The fix is
  already merged into scripts/chroot-inject.sh, so the next ISO build
  ships with it baked in.

EOF
