#!/usr/bin/env bash
# VibeOS Stage 4 — host-side pre-flight verification.
#
# Runs entirely on the host (no chroot, no sudo, no ISO). Validates every
# theme pack artifact that can be checked without KDE. Designed to fail
# fast before a 30-minute ISO build/QEMU cycle.
#
# Usage:
#   bash scripts/preflight.sh
#
# Exit code:
#   0   all checks passed
#   1   one or more checks failed (see summary)

set -uo pipefail

say()   { printf '\e[35m[preflight]\e[0m %s\n' "$*"; }
ok()    { printf '\e[32m  ✓\e[0m %s\n' "$*"; PASS=$((PASS+1)); }
fail()  { printf '\e[31m  ✗\e[0m %s\n' "$*" >&2; FAIL=$((FAIL+1)); }
warn()  { printf '\e[33m  !\e[0m %s\n' "$*" >&2; }

PASS=0
FAIL=0

REPO="$(cd "$(dirname "$0")/.." && pwd)"
THEMING="$REPO/theming"

cd "$REPO"

# =============================================================
# 1) Shell script syntax
# =============================================================
say "1. shell script syntax (bash -n)"
for f in scripts/install-build-rig.sh \
         scripts/chroot-inject.sh \
         scripts/fetch-fonts.sh \
         scripts/fetch-wallpapers.sh \
         scripts/preflight.sh \
         scripts/validate-theming.sh; do
    if [ -f "$f" ]; then
        if bash -n "$f" 2>/dev/null; then
            ok "bash -n $f"
        else
            fail "bash -n $f (syntax error)"
        fi
    else
        fail "$f missing"
    fi
done

# =============================================================
# 2) Python script compilation
# =============================================================
say "2. python script compilation"
if command -v python3 >/dev/null 2>&1; then
    for f in scripts/kvantum-recolor.py clippy/server.py clippy/launcher.py clippy/dialogue.py clippy/memory.py; do
        if [ -f "$f" ]; then
            if python3 -c "import py_compile; py_compile.compile('$f', doraise=True)" 2>/dev/null; then
                ok "py_compile $f"
            else
                fail "py_compile $f"
            fi
        fi
    done
else
    warn "python3 missing — skipping py_compile checks"
fi

# =============================================================
# 3) SVG well-formedness
# =============================================================
say "3. SVG well-formedness"
if command -v python3 >/dev/null 2>&1; then
    while IFS= read -r svg; do
        if python3 -c "
import xml.etree.ElementTree as ET
try:
    ET.parse('$svg')
except ET.ParseError as e:
    print(str(e))
    exit(1)
" >/dev/null 2>&1; then
            ok "xml parse $(basename "$svg")"
        else
            fail "xml parse $svg"
        fi
    done < <(find "$THEMING" -type f -name '*.svg' 2>/dev/null)
else
    warn "python3 missing — skipping SVG parse checks"
fi

# =============================================================
# 4) Aurorae decoration.svg required IDs
# =============================================================
say "4. Aurorae decoration.svg required element IDs"
DECO="$THEMING/plasma/aurorae/themes/VibeOS-Neon/decoration.svg"
if [ -f "$DECO" ]; then
    REQUIRED_IDS=(decoration decoration-inactive close maximize restore minimize)
    MISSING=""
    for id in "${REQUIRED_IDS[@]}"; do
        if ! grep -q "id=\"$id\"" "$DECO"; then
            MISSING="$MISSING $id"
        fi
    done
    if [ -z "$MISSING" ]; then
        ok "all required Aurorae IDs present (${#REQUIRED_IDS[@]})"
    else
        fail "missing Aurorae IDs:$MISSING"
    fi

    # Duplicate IDs would break KDE's extract-by-ID logic
    DUPES=$(python3 -c "
import re, sys
with open('$DECO') as f:
    content = f.read()
ids = re.findall(r'id=\"([^\"]+)\"', content)
dupes = {i for i in ids if ids.count(i) > 1}
sys.exit(0) if not dupes else print(','.join(sorted(dupes)))
" 2>/dev/null || true)
    if [ -z "$DUPES" ]; then
        ok "no duplicate SVG IDs"
    else
        fail "duplicate SVG IDs: $DUPES"
    fi
else
    fail "$DECO missing"
fi

# =============================================================
# 5) INI-style files (kvconfig, kdeglobals, etc.)
# =============================================================
say "5. INI-style file parsing"
INI_FILES=(
    "$THEMING/plasma/color-schemes/VibeOS-Neon.colors"
    "$THEMING/plasma/desktoptheme/VibeOS-Neon/metadata.desktop"
    "$THEMING/plasma/aurorae/themes/VibeOS-Neon/metadata.desktop"
    "$THEMING/plasma/aurorae/themes/VibeOS-Neon/VibeOS-Neonrc"
    "$THEMING/plasma/Kvantum/VibeOS-Neon/VibeOS-Neon.kvconfig"
    "$THEMING/konsole/VibeOS.profile"
    "$THEMING/konsole/VibeOS.colorscheme"
    "$THEMING/sddm/vibeos/metadata.desktop"
    "$THEMING/sddm/vibeos/theme.conf"
    "$THEMING/plymouth/vibeos/vibeos.plymouth"
    "$THEMING/os-release/os-release"
    "$THEMING/os-release/lsb-release"
    # System-wide KDE fallbacks (0.4.3+: moved out of /etc/skel to avoid
    # KWin crash on MSI when Backend=OpenGL + aurorae overrides collided;
    # these are now installed to /etc/xdg by chroot-inject step 5.5).
    "$THEMING/xdg/kdeglobals"
    "$THEMING/xdg/plasmarc"
    "$THEMING/xdg/kwinrc"
    "$THEMING/xdg/kcminputrc"
    "$THEMING/skel/.config/konsolerc"
    "$THEMING/skel/.config/autostart/vibeos-first-run.desktop"
)
for f in "${INI_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        fail "missing: $f"
        continue
    fi
    # configparser is strict about section-less keys. KDE .conf/.desktop
    # sometimes start with no section → tolerate but flag stray control
    # chars or BOM that trip KDE's parser.
    if python3 -c "
import configparser, sys
cp = configparser.ConfigParser(strict=False, interpolation=None)
try:
    with open('$f', encoding='utf-8') as fh:
        cp.read_string(fh.read())
except configparser.Error:
    sys.exit(1)
" 2>/dev/null; then
        ok "ini parse $(basename "$f")"
    else
        # os-release + autostart desktop files may parse strict; retry with
        # a prepended [DEFAULT] section to allow bare key=value lines
        if python3 -c "
import configparser
cp = configparser.ConfigParser(strict=False, interpolation=None)
with open('$f', encoding='utf-8') as fh:
    content = fh.read()
if not content.lstrip().startswith('['):
    content = '[DEFAULT]\n' + content
cp.read_string(content)
" 2>/dev/null; then
            ok "ini parse $(basename "$f") (sectionless)"
        else
            fail "ini parse $f"
        fi
    fi
done

# =============================================================
# 6) JSONC (fastfetch config)
# =============================================================
say "6. JSONC files"
JSONC="$THEMING/fastfetch/config.jsonc"
if [ -f "$JSONC" ]; then
    if python3 -c "
import json, sys
with open('$JSONC') as f:
    raw = f.read()
# String-aware comment stripper: walks characters tracking whether we are
# inside a \"...\" string literal (with backslash-escape handling). Outside
# strings, '//' starts a line comment (to newline) and '/*' starts a block
# comment (to '*/').
out = []
i = 0
in_string = False
while i < len(raw):
    c = raw[i]
    if in_string:
        out.append(c)
        if c == '\\\\' and i + 1 < len(raw):
            out.append(raw[i+1]); i += 2; continue
        if c == '\"':
            in_string = False
        i += 1; continue
    if c == '\"':
        in_string = True
        out.append(c); i += 1; continue
    if c == '/' and i + 1 < len(raw) and raw[i+1] == '/':
        while i < len(raw) and raw[i] != '\\n':
            i += 1
        continue
    if c == '/' and i + 1 < len(raw) and raw[i+1] == '*':
        i += 2
        while i + 1 < len(raw) and not (raw[i] == '*' and raw[i+1] == '/'):
            i += 1
        i += 2
        continue
    out.append(c); i += 1
stripped = ''.join(out)
try:
    json.loads(stripped)
except Exception as e:
    print(str(e)); sys.exit(1)
" 2>/dev/null; then
        ok "jsonc parse $(basename "$JSONC")"
    else
        fail "jsonc parse $JSONC"
    fi
else
    fail "$JSONC missing"
fi

# =============================================================
# 7) Chroot-inject self-reference
# =============================================================
say "7. chroot-inject.sh reference integrity"
for path in "$THEMING/plasma/color-schemes/VibeOS-Neon.colors" \
            "$THEMING/plasma/desktoptheme/VibeOS-Neon" \
            "$THEMING/plasma/aurorae/themes/VibeOS-Neon" \
            "$THEMING/plasma/Kvantum/VibeOS-Neon/VibeOS-Neon.kvconfig" \
            "$THEMING/konsole/VibeOS.colorscheme" \
            "$THEMING/konsole/VibeOS.profile" \
            "$THEMING/sddm/vibeos" \
            "$THEMING/plymouth/vibeos" \
            "$THEMING/grub/vibeos" \
            "$THEMING/os-release/os-release" \
            "$THEMING/os-release/vibeos-logo.svg" \
            "$THEMING/skel/.config/autostart/vibeos-first-run.desktop" \
            "$THEMING/fastfetch/config.jsonc"; do
    if [ -e "$path" ]; then
        ok "referenced by chroot-inject: $(basename "$path")"
    else
        fail "missing referenced artifact: $path"
    fi
done

# =============================================================
# 8) Required KDE color-scheme sections
# =============================================================
say "8. KDE color scheme section completeness"
REQUIRED_COLORS=(
    "Colors:Button"
    "Colors:View"
    "Colors:Window"
    "Colors:Selection"
    "Colors:Tooltip"
    "Colors:Complementary"
    "ColorEffects:Disabled"
    "ColorEffects:Inactive"
    "WM"
    "General"
)
COLORS_FILE="$THEMING/plasma/color-schemes/VibeOS-Neon.colors"
if [ -f "$COLORS_FILE" ]; then
    MISSING_SECTIONS=""
    for sect in "${REQUIRED_COLORS[@]}"; do
        if ! grep -qF "[$sect]" "$COLORS_FILE"; then
            MISSING_SECTIONS="$MISSING_SECTIONS $sect"
        fi
    done
    if [ -z "$MISSING_SECTIONS" ]; then
        ok "all ${#REQUIRED_COLORS[@]} required color scheme sections present"
    else
        fail "missing color scheme sections:$MISSING_SECTIONS"
    fi
fi

# =============================================================
# 9) kvantum-recolor palette coverage vs expected theme
# =============================================================
say "9. kvantum-recolor COLOR_MAP palette sanity"
if python3 -c "
import re, sys
with open('scripts/kvantum-recolor.py') as f:
    src = f.read()
# Extract hex values from COLOR_MAP
pairs = re.findall(r'\"(#[0-9a-fA-F]{6})\":\s*\"(#[0-9a-fA-F]{6})\"', src)
if not pairs:
    print('no palette pairs found'); sys.exit(1)
neon_targets = {'#FF2ECF','#FF71CE','#01F9FF','#9D4EDD','#0B0218','#1A0B2E','#2D1B4E','#F8F0FF','#B5A6D9','#5A3A8A'}
got = {new.upper() for _, new in pairs}
missing = neon_targets - got
if missing:
    print('palette missing targets:', sorted(missing)); sys.exit(2)
" 2>&1; then
    ok "kvantum-recolor covers all neon palette targets"
else
    fail "kvantum-recolor palette incomplete (see above)"
fi

# =============================================================
# 10) Theme asset validator — Look-and-Feel + xdg integrity
# =============================================================
say "10. theme asset integrity (validate-theming.sh)"
if [ -x scripts/validate-theming.sh ]; then
    if scripts/validate-theming.sh >/dev/null 2>&1; then
        ok "validate-theming.sh passed"
    else
        fail "validate-theming.sh failed — run 'bash scripts/validate-theming.sh' for detail"
    fi
else
    warn "scripts/validate-theming.sh missing or not executable"
fi

# =============================================================
# Report
# =============================================================
printf '\n\e[36m=== preflight summary ===\e[0m\n'
printf '  passed: %s\n' "$PASS"
printf '  failed: %s\n' "$FAIL"
if [ "$FAIL" -eq 0 ]; then
    printf '\e[32mall checks passed\e[0m — ready to run install-build-rig.sh\n'
    exit 0
else
    printf '\e[31mfailures detected\e[0m — fix before running ISO build\n'
    exit 1
fi
