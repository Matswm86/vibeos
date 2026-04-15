#!/usr/bin/env bash
# Loop-mount mkosi.output/vibeos.raw and assert that every critical
# baked-in artifact is actually present. Runs after scripts/build.sh
# and before scripts/qemu-boot.sh — catches the "silently broken ISO"
# class of bugs that shipped in day-7 (missing model, missing CLI,
# missing autostart).
#
# Exit 0 = ISO is safe to burn.
# Exit 1 = FATAL, do NOT burn this ISO.
#
# Requires: sudo (loop mount + reading root-owned files from ext4).

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

ISO="${1:-mkosi.output/vibeos.raw}"

err()  { printf '\e[31m✗ %s\e[0m\n' "$*" >&2; FAIL=1; }
info() { printf '\e[36m→\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m✓\e[0m %s\n' "$*"; }

[ -f "$ISO" ] || { printf '\e[31m✗ %s\e[0m\n' "ISO missing: $ISO" >&2; exit 1; }

command -v sudo >/dev/null || { err "sudo required"; exit 1; }

# The raw has GPT with ESP + root. We want the root partition — partition
# 2 in the current mkosi layout. `partx` resolves offsets without needing
# losetup -P (which requires a pre-created loop device).
MNT=$(mktemp -d)
LOOP=$(sudo losetup --find --show --partscan "$ISO")
info "attached $ISO → $LOOP (partscan)"

cleanup() {
    sudo umount "$MNT" 2>/dev/null || true
    sudo losetup -d "$LOOP" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Root partition is the largest one — let lsblk pick it.
ROOT_PART=$(lsblk -nlpo NAME,SIZE "$LOOP" \
    | awk 'NR>1' \
    | sort -k2 -h \
    | tail -1 \
    | awk '{print $1}')

if [ -z "$ROOT_PART" ] || [ "$ROOT_PART" = "$LOOP" ]; then
    err "couldn't identify root partition on $LOOP"
    exit 1
fi

info "mounting $ROOT_PART → $MNT (ro)"
sudo mount -o ro "$ROOT_PART" "$MNT"

FAIL=0

# ─── 1. Ollama model ──────────────────────────────────────────────────
MODEL_MANIFEST="$MNT/usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/qwen2.5/3b"
if sudo test -f "$MODEL_MANIFEST"; then
    # Verify all blobs named in the manifest exist
    BLOBS=$(sudo python3 -c "
import json
m = json.load(open('$MODEL_MANIFEST'))
digests = [m['config']['digest']] + [l['digest'] for l in m.get('layers', [])]
for d in digests:
    print('sha256-' + d.split(':', 1)[1])
")
    MISSING=0
    for blob in $BLOBS; do
        if ! sudo test -f "$MNT/usr/share/ollama/.ollama/models/blobs/$blob"; then
            err "blob missing: $blob"
            MISSING=1
        fi
    done
    [ $MISSING -eq 0 ] && ok "ollama model qwen2.5:3b + all blobs present"
else
    err "ollama model manifest missing: $MODEL_MANIFEST"
fi

# ─── 2. Claude Code CLI ───────────────────────────────────────────────
if sudo test -L "$MNT/usr/bin/claude" && \
   sudo test -f "$MNT/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js"; then
    VER=$(sudo cat "$MNT/usr/share/vibeos/CLAUDE_BAKED_VERSION" 2>/dev/null || echo "unknown")
    ok "claude CLI baked: $VER"
else
    err "claude CLI missing (expected /usr/bin/claude → /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js)"
fi

# ─── 3. Live-session marker ───────────────────────────────────────────
if sudo test -f "$MNT/etc/vibeos/live-session"; then
    ok "live-session marker present"
else
    err "live-session marker missing: /etc/vibeos/live-session"
fi

# ─── 4. Calamares autostart ──────────────────────────────────────────
if sudo test -f "$MNT/etc/xdg/autostart/vibeos-live-installer.desktop" && \
   sudo test -x "$MNT/usr/libexec/vibeos/live-autostart"; then
    ok "calamares + vibbey install-helper autostart wired"
else
    err "calamares autostart missing (expected /etc/xdg/autostart/vibeos-live-installer.desktop + /usr/libexec/vibeos/live-autostart)"
fi

# ─── 5. Calamares + config ───────────────────────────────────────────
if sudo test -x "$MNT/usr/bin/calamares" && \
   sudo test -f "$MNT/etc/calamares/settings.conf" && \
   sudo test -f "$MNT/etc/calamares/modules/contextualprocess.conf"; then
    ok "calamares installed + config mounted + contextualprocess wired"
else
    err "calamares not fully wired — check /usr/bin/calamares + /etc/calamares/{settings.conf,modules/contextualprocess.conf}"
fi

# ─── 6. Vibbey install-helper HTML + endpoint ────────────────────────
if sudo test -f "$MNT/usr/share/vibeos/vibbey/static/install-helper.html" && \
   sudo grep -q '/api/calamares-step' "$MNT/usr/share/vibeos/vibbey/server.py"; then
    ok "vibbey install-helper HTML + calamares-step endpoint present"
else
    err "vibbey install-helper missing (html or server.py endpoint)"
fi

# ─── 7. Vibbey first-run gated on live-session marker ────────────────
VFR="$MNT/etc/xdg/autostart/vibbey-first-run.desktop"
if sudo test -f "$VFR"; then
    if sudo grep -q 'live-session' "$VFR"; then
        ok "vibbey first-run skips live session"
    else
        err "vibbey first-run does NOT gate on live-session marker — would chat-spam live ISO"
    fi
else
    err "vibbey first-run autostart missing"
fi

# ─── 8. Ollama systemd unit + correct user ownership ─────────────────
if sudo test -f "$MNT/lib/systemd/system/ollama.service"; then
    # Resolve the UID on disk via the ISO's /etc/passwd, not the host's —
    # system UIDs differ between host and target (host 999 may be
    # `greeter`; target 999 is `ollama`).
    ISO_UID=$(sudo stat -c '%u' "$MNT/usr/share/ollama/.ollama/models")
    ISO_OWNER=$(sudo awk -F: -v u="$ISO_UID" '$3==u {print $1; exit}' "$MNT/etc/passwd")
    if [ "$ISO_OWNER" = "ollama" ]; then
        ok "ollama model store owned by ollama user (uid=$ISO_UID in target /etc/passwd)"
    else
        err "ollama model store owned by uid=$ISO_UID ('$ISO_OWNER' in target) — expected ollama"
    fi
else
    err "ollama systemd unit missing"
fi

if [ "$FAIL" -eq 0 ]; then
    ok "ALL CHECKS PASSED — ISO is safe to burn"
    exit 0
else
    printf '\e[31m\n✗ VERIFICATION FAILED — do NOT burn this ISO to USB.\e[0m\n' >&2
    exit 1
fi
