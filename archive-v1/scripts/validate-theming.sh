#!/usr/bin/env bash
# validate-theming.sh — fail loudly before ISO build if any asset is missing
#
# Checks that every theme/file referenced by the Look-and-Feel package,
# xdg configs, kdeglobals, or chroot-inject.sh exists in the theming tree.
# Run this BEFORE chroot-inject.sh. A missing asset causes KWin / Plasma
# to crash silently at session start (black screen + cursor).
#
# Usage:
#   scripts/validate-theming.sh        # from repo root
#   bash scripts/validate-theming.sh
#
# Exit codes:
#   0  all assets present
#   1  one or more missing — do NOT proceed to ISO build

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
THEMING="$REPO/theming"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*" >&2; }

FAIL=0

check_file() {
    local label="$1" path="$2"
    if [ -f "$path" ]; then
        green "  OK   $label  ->  ${path#$THEMING/}"
    else
        red   "  MISS $label  ->  ${path#$THEMING/}"
        FAIL=$((FAIL+1))
    fi
}

check_dir() {
    local label="$1" path="$2"
    if [ -d "$path" ]; then
        green "  OK   $label  ->  ${path#$THEMING/}"
    else
        red   "  MISS $label  ->  ${path#$THEMING/}"
        FAIL=$((FAIL+1))
    fi
}

echo "== validate-theming.sh =="
echo "theming root: $THEMING"
echo

echo "[1/6] Color scheme"
check_file "VibeOS-Neon.colors" \
    "$THEMING/plasma/color-schemes/VibeOS-Neon.colors"

echo
echo "[2/6] Plasma desktoptheme"
check_dir  "desktoptheme VibeOS-Neon"       "$THEMING/plasma/desktoptheme/VibeOS-Neon"
check_file "desktoptheme metadata.desktop"  "$THEMING/plasma/desktoptheme/VibeOS-Neon/metadata.desktop"

echo
echo "[3/6] Aurorae window decoration"
check_dir  "aurorae VibeOS-Neon"        "$THEMING/plasma/aurorae/themes/VibeOS-Neon"
check_file "aurorae metadata.desktop"   "$THEMING/plasma/aurorae/themes/VibeOS-Neon/metadata.desktop"
check_file "aurorae decoration.svg"     "$THEMING/plasma/aurorae/themes/VibeOS-Neon/decoration.svg"
check_file "aurorae VibeOS-Neonrc"      "$THEMING/plasma/aurorae/themes/VibeOS-Neon/VibeOS-Neonrc"

# PluginInfo-Name in metadata.desktop MUST match the folder name, else KWin
# silently refuses to load the theme and falls back to defaults.
if [ -f "$THEMING/plasma/aurorae/themes/VibeOS-Neon/metadata.desktop" ]; then
    plugin_name=$(grep -E '^X-KDE-PluginInfo-Name=' \
        "$THEMING/plasma/aurorae/themes/VibeOS-Neon/metadata.desktop" \
        | cut -d= -f2 | tr -d '[:space:]')
    if [ "$plugin_name" = "VibeOS-Neon" ]; then
        green "  OK   aurorae PluginInfo-Name matches folder"
    else
        red   "  FAIL aurorae PluginInfo-Name is '$plugin_name', expected 'VibeOS-Neon'"
        FAIL=$((FAIL+1))
    fi
fi

echo
echo "[4/6] Look-and-Feel package"
LNF="$THEMING/plasma/look-and-feel/org.vibeos.neon"
check_dir  "L&F package dir"       "$LNF"
check_file "L&F metadata.desktop"  "$LNF/metadata.desktop"
check_file "L&F contents/defaults" "$LNF/contents/defaults"

# defaults must reference only assets we've already verified present.
if [ -f "$LNF/contents/defaults" ]; then
    for ref in "ColorScheme=VibeOS-Neon" \
               "name=VibeOS-Neon" \
               "theme=__aurorae__svg__VibeOS-Neon" \
               "cursorTheme=Bibata-Modern-Ice"; do
        if grep -qF "$ref" "$LNF/contents/defaults"; then
            green "  OK   defaults references $ref"
        else
            yellow "  WARN defaults missing expected key: $ref"
        fi
    done
fi

echo
echo "[5/6] Wallpaper + cursor"
check_file "default wallpaper symlink/file" \
    "$THEMING/wallpapers/vibeos-default.jpg"
check_dir  "Bibata-Modern-Ice cursor"       "$THEMING/icons/cursors/Bibata-Modern-Ice"

echo
echo "[6/6] /etc/xdg fallback configs"
check_file "xdg/kdeglobals"   "$THEMING/xdg/kdeglobals"
check_file "xdg/plasmarc"     "$THEMING/xdg/plasmarc"
check_file "xdg/kwinrc"       "$THEMING/xdg/kwinrc"
check_file "xdg/kcminputrc"   "$THEMING/xdg/kcminputrc"

# xdg/kwinrc MUST NOT re-introduce the crashers we removed in 0.4.3.
if [ -f "$THEMING/xdg/kwinrc" ]; then
    if grep -qE '^GLCore=true' "$THEMING/xdg/kwinrc"; then
        red   "  FAIL xdg/kwinrc contains GLCore=true — that's the 0.4.2 black-screen bug"
        FAIL=$((FAIL+1))
    else
        green "  OK   xdg/kwinrc has no GLCore=true"
    fi
    if grep -qE '^\[org\.kde\.kdecoration2\]' "$THEMING/xdg/kwinrc"; then
        red   "  FAIL xdg/kwinrc overrides decoration — L&F should own this, not xdg"
        FAIL=$((FAIL+1))
    else
        green "  OK   xdg/kwinrc leaves decoration to L&F"
    fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
    green "== validate-theming.sh: PASS =="
    exit 0
else
    red   "== validate-theming.sh: FAIL ($FAIL issue(s)) — do NOT build ISO =="
    exit 1
fi
