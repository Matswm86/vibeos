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
# ROOT WITHOUT A PASSWORD:
#   Reading the baked image needs root (loop-mount + the ollama model
#   store is mode 0700 owned by the ollama user). Rather than prompt for
#   sudo, this script re-execs itself inside the privileged mkosi builder
#   container (docker runs passwordless on the build host), where it is
#   already root. That removes the sudo password prompt that made the
#   post-build verify step fail in non-interactive shells.
#
#   Resolution order:
#     1. already root  -> run directly ($SUDO empty)
#     2. docker present -> re-exec in vibeos-builder container as root
#     3. fallback       -> use sudo (interactive password)

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

ISO="${1:-mkosi.output/vibeos.raw}"
BUILDER_IMAGE="vibeos-builder:latest"

err()  { printf '\e[31m✗ %s\e[0m\n' "$*" >&2; FAIL=1; }
info() { printf '\e[36m→\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m✓\e[0m %s\n' "$*"; }

[ -f "$ISO" ] || { printf '\e[31m✗ %s\e[0m\n' "ISO missing: $ISO" >&2; exit 1; }

# ── Get root without a password ────────────────────────────────────────
# If we are not root and not already inside the re-exec, prefer the
# passwordless docker path; only fall back to sudo if docker is absent.
if [ "$(id -u)" -ne 0 ] && [ -z "${VIBEOS_VERIFY_IN_CONTAINER:-}" ]; then
    if command -v docker >/dev/null 2>&1 && [ -n "$(docker image ls -q "$BUILDER_IMAGE" 2>/dev/null)" ]; then
        info "re-exec in $BUILDER_IMAGE as root (passwordless, no sudo)"
        exec docker run --rm --privileged \
            -e VIBEOS_VERIFY_IN_CONTAINER=1 \
            -v "$REPO_ROOT:/work" -w /work \
            "$BUILDER_IMAGE" \
            bash scripts/verify-iso.sh "$ISO"
    fi
    info "docker/builder image not available — falling back to sudo (will prompt)"
fi

# $SUDO is empty when we are root (the common case after re-exec), so no
# password is ever required on the docker path.
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

# ── Mount the root partition of the GPT raw image ──────────────────────
# Pick the largest partition (the ext4 root) and mount it by byte offset
# with the kernel's internal loop, which works in a privileged container
# without depending on udev to create /dev/loopNpX partition nodes.
MNT=$(mktemp -d)

read -r ROOT_START < <(
    partx -g -o NR,START,SECTORS --raw "$ISO" 2>/dev/null \
        | sort -k3 -n | tail -1 | awk '{print $2}'
)
[ -n "${ROOT_START:-}" ] || { printf '\e[31m✗ could not read partition table from %s\e[0m\n' "$ISO" >&2; rmdir "$MNT"; exit 1; }
ROOT_OFFSET=$(( ROOT_START * 512 ))
info "root partition starts at sector $ROOT_START (offset $ROOT_OFFSET bytes)"

cleanup() {
    $SUDO umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

info "mounting $ISO root → $MNT (ro, loop, offset)"
$SUDO mount -o ro,loop,offset="$ROOT_OFFSET" "$ISO" "$MNT" \
    || { printf '\e[31m✗ mount failed\e[0m\n' >&2; exit 1; }

FAIL=0

# ─── 1. Ollama model ──────────────────────────────────────────────────
MODEL_MANIFEST="$MNT/usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/qwen2.5/3b"
if $SUDO test -f "$MODEL_MANIFEST"; then
    # Verify all blobs named in the manifest exist
    BLOBS=$($SUDO python3 -c "
import json
m = json.load(open('$MODEL_MANIFEST'))
digests = [m['config']['digest']] + [l['digest'] for l in m.get('layers', [])]
for d in digests:
    print('sha256-' + d.split(':', 1)[1])
")
    MISSING=0
    for blob in $BLOBS; do
        if ! $SUDO test -f "$MNT/usr/share/ollama/.ollama/models/blobs/$blob"; then
            err "blob missing: $blob"
            MISSING=1
        fi
    done
    [ $MISSING -eq 0 ] && ok "ollama model qwen2.5:3b + all blobs present"
else
    err "ollama model manifest missing: $MODEL_MANIFEST"
fi

# ─── 2. Claude Code CLI ───────────────────────────────────────────────
# Version-agnostic: assert /usr/bin/claude is a symlink that resolves to a
# real file. `test -f` follows the link, and the relative target
# (../lib/node_modules/@anthropic-ai/claude-code/...) resolves inside the
# mounted root. This survives the npm-layout change: Claude Code <=2.0 used
# a node `cli.js` entry; 2.1+ ships a single bundled `bin/claude.exe`.
if $SUDO test -L "$MNT/usr/bin/claude" && $SUDO test -f "$MNT/usr/bin/claude"; then
    VER=$($SUDO cat "$MNT/usr/share/vibeos/CLAUDE_BAKED_VERSION" 2>/dev/null || echo "unknown")
    ok "claude CLI baked: $VER"
else
    err "claude CLI missing or dangling (expected /usr/bin/claude symlink → resolvable entrypoint)"
fi

# ─── 3. Live-session marker ───────────────────────────────────────────
if $SUDO test -f "$MNT/etc/vibeos/live-session"; then
    ok "live-session marker present"
else
    err "live-session marker missing: /etc/vibeos/live-session"
fi

# ─── 4. Calamares autostart ──────────────────────────────────────────
if $SUDO test -f "$MNT/etc/xdg/autostart/vibeos-live-installer.desktop" && \
   $SUDO test -x "$MNT/usr/libexec/vibeos/live-autostart"; then
    ok "calamares + vibbey install-helper autostart wired"
else
    err "calamares autostart missing (expected /etc/xdg/autostart/vibeos-live-installer.desktop + /usr/libexec/vibeos/live-autostart)"
fi

# ─── 5. Calamares + config + target cleanup wired ────────────────────
# The cleanup MUST be the shellprocess pair (strip post-unpackfs +
# @cleanup --verify at the end). The old contextualprocess config was
# written in shellprocess syntax, silently no-op'd on every install, and
# shipped installed systems that booted back into the live install page —
# assert it can never come back.
if $SUDO test -x "$MNT/usr/bin/calamares" && \
   $SUDO test -f "$MNT/etc/calamares/settings.conf" && \
   $SUDO test -f "$MNT/etc/calamares/modules/shellprocess_cleanup.conf" && \
   $SUDO test -f "$MNT/etc/calamares/modules/displaymanager.conf" && \
   $SUDO test -x "$MNT/usr/local/sbin/vibeos-target-cleanup.sh" && \
   $SUDO grep -q 'shellprocess@cleanup' "$MNT/etc/calamares/settings.conf" && \
   $SUDO grep -q '^[[:space:]]*- displaymanager' "$MNT/etc/calamares/settings.conf" && \
   $SUDO grep -q 'vibeos-target-cleanup.sh' "$MNT/etc/calamares/modules/shellprocess.conf"; then
    ok "calamares + live-session target cleanup wired (strip + @cleanup verify + displaymanager)"
else
    err "target cleanup NOT wired — installed system would boot back into the live install page"
fi
if $SUDO grep -q 'contextualprocess' "$MNT/etc/calamares/settings.conf" 2>/dev/null; then
    err "contextualprocess back in settings.conf sequence — it silently no-ops; use the shellprocess cleanup pair"
fi

# ─── 6. Vibbey install-helper HTML + endpoint ────────────────────────
if $SUDO test -f "$MNT/usr/share/vibeos/vibbey/static/install-helper.html" && \
   $SUDO grep -q '/api/calamares-step' "$MNT/usr/share/vibeos/vibbey/server.py"; then
    ok "vibbey install-helper HTML + calamares-step endpoint present"
else
    err "vibbey install-helper missing (html or server.py endpoint)"
fi

# ─── 7. Vibbey first-run gated on live-session marker ────────────────
VFR="$MNT/etc/xdg/autostart/vibbey-first-run.desktop"
if $SUDO test -f "$VFR"; then
    if $SUDO grep -q 'live-session' "$VFR"; then
        ok "vibbey first-run skips live session"
    else
        err "vibbey first-run does NOT gate on live-session marker — would chat-spam live ISO"
    fi
else
    err "vibbey first-run autostart missing"
fi

# ─── 8. Ollama systemd unit + correct user ownership ─────────────────
if $SUDO test -f "$MNT/lib/systemd/system/ollama.service"; then
    # Resolve the UID on disk via the ISO's /etc/passwd, not the host's —
    # system UIDs differ between host and target (host 999 may be
    # `greeter`; target 999 is `ollama`).
    ISO_UID=$($SUDO stat -c '%u' "$MNT/usr/share/ollama/.ollama/models")
    ISO_OWNER=$($SUDO awk -F: -v u="$ISO_UID" '$3==u {print $1; exit}' "$MNT/etc/passwd")
    if [ "$ISO_OWNER" = "ollama" ]; then
        ok "ollama model store owned by ollama user (uid=$ISO_UID in target /etc/passwd)"
    else
        err "ollama model store owned by uid=$ISO_UID ('$ISO_OWNER' in target) — expected ollama"
    fi
else
    err "ollama systemd unit missing"
fi

# ─── 9. Bootloader deploy wired host-side (v2.0.0-rc1 black-screen fix) ─
# The installed-system-won't-boot bug was the chroot bootloader fix never
# copying the kernel to the target ESP. Assert the host-side deploy is in
# place AND the installer is wired to run it with dontChroot:true.
if $SUDO test -x "$MNT/usr/local/sbin/vibeos-bootloader-deploy.sh" && \
   $SUDO grep -q '^dontChroot:[[:space:]]*true' "$MNT/etc/calamares/modules/shellprocess_bootctl.conf" && \
   $SUDO grep -q 'vibeos-bootloader-deploy.sh' "$MNT/etc/calamares/modules/shellprocess_bootctl.conf"; then
    ok "host-side bootloader deploy wired (dontChroot:true → vibeos-bootloader-deploy.sh)"
else
    err "bootloader deploy NOT wired — installed system will black-screen on first boot"
fi

# ─── 10. Live user groups (read-only $GROUPS bash bug guard) ──────────
# Every build through day 10 shipped the live user in group root(0)
# because the postinst assigned to the read-only bash special GROUPS.
# Assert the fix: vibeos must be in sudo, and NOT in root.
if $SUDO grep -q '^sudo:.*\bvibeos\b' "$MNT/etc/group"; then
    ok "live user in sudo group (GROUPS-variable bug fixed)"
else
    err "live user NOT in sudo group — read-only \$GROUPS bash bug is back (check mkosi.postinst.chroot)"
fi
if $SUDO grep -q '^root:.*\bvibeos\b' "$MNT/etc/group"; then
    err "live user is in group root(0) — read-only \$GROUPS bash bug regressed"
fi

# ─── 11. launch-calamares never fails silently ────────────────────────
# Guards: installed-system refusal (settings.conf check), single-instance,
# persistent log (NOT tmpfs /tmp), kdialog/zenity feedback on errors.
LC="$MNT/usr/libexec/vibeos/launch-calamares"
if $SUDO test -x "$LC" && \
   $SUDO grep -q '/etc/calamares/settings.conf' "$LC" && \
   $SUDO grep -q 'pgrep -x calamares' "$LC" && \
   $SUDO grep -q 'XDG_CACHE_HOME' "$LC" && \
   $SUDO grep -q 'kdialog' "$LC"; then
    ok "launch-calamares has installed-system + single-instance guards, persistent log, visible errors"
else
    err "launch-calamares missing silent-failure guards (installed-system check / pgrep / persistent log / kdialog)"
fi

# ─── 12. Bootloader deploy creates an NVRAM entry ─────────────────────
# bootctl WITH variables first (BootOrder priority over USB + stale
# disks), --no-variables only as fallback.
if $SUDO grep -q 'bootctl --esp-path="\$TARGET_ESP" install' "$MNT/usr/local/sbin/vibeos-bootloader-deploy.sh"; then
    ok "bootloader deploy tries NVRAM boot entry first (BootOrder priority)"
else
    err "bootloader deploy missing NVRAM-first bootctl install — boot order stays luck-based"
fi

if [ "$FAIL" -eq 0 ]; then
    ok "ALL CHECKS PASSED — ISO is safe to burn"
    exit 0
else
    printf '\e[31m\n✗ VERIFICATION FAILED — do NOT burn this ISO to USB.\e[0m\n' >&2
    exit 1
fi
