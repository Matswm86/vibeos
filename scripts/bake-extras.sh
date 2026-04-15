#!/usr/bin/env bash
# Pre-bake the heavy payloads (Ollama model + Claude Code CLI) into
# mkosi/mkosi.extra/ so mkosi copies them into the rootfs without the
# chroot needing internet.
#
# This runs on the HOST. CI must run it before scripts/build.sh.
#
# Outputs:
#   mkosi/mkosi.extra/usr/share/ollama/.ollama/models/{manifests,blobs}/...
#   mkosi/mkosi.extra/usr/lib/node_modules/@anthropic-ai/claude-code/...
#   mkosi/mkosi.extra/usr/bin/claude -> ../lib/node_modules/.../cli.js
#
# Both trees are gitignored — this script is the source of truth.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

info() { printf '\e[36m→\e[0m %s\n' "$*"; }
ok()   { printf '\e[32m✓\e[0m %s\n' "$*"; }
err()  { printf '\e[31m✗\e[0m %s\n' "$*" >&2; exit 1; }

OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:3b}"
CLAUDE_PKG="@anthropic-ai/claude-code"

EXTRA="$REPO_ROOT/mkosi/mkosi.extra"

# ─── 1. Ollama model ──────────────────────────────────────────────────
info "baking Ollama model: $OLLAMA_MODEL"

command -v ollama >/dev/null 2>&1 || err "ollama not installed on host — install + pull $OLLAMA_MODEL first"

# Host model store — system service default
HOST_MODELS="/usr/share/ollama/.ollama/models"
[ -d "$HOST_MODELS" ] || err "$HOST_MODELS missing — is the host ollama.service running?"

# Parse model "name:tag" → manifest path registry.ollama.ai/library/<name>/<tag>
MODEL_NAME="${OLLAMA_MODEL%:*}"
MODEL_TAG="${OLLAMA_MODEL##*:}"
MANIFEST="$HOST_MODELS/manifests/registry.ollama.ai/library/$MODEL_NAME/$MODEL_TAG"
[ -f "$MANIFEST" ] || err "model $OLLAMA_MODEL not pulled on host — run: ollama pull $OLLAMA_MODEL"

DST_MANIFESTS="$EXTRA/usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/$MODEL_NAME"
DST_BLOBS="$EXTRA/usr/share/ollama/.ollama/models/blobs"
mkdir -p "$DST_MANIFESTS" "$DST_BLOBS"

# Copy manifest
install -m 0644 "$MANIFEST" "$DST_MANIFESTS/$MODEL_TAG"

# Parse manifest JSON for all blob digests (config + layers)
BLOBS=$(python3 -c "
import json, sys
m = json.load(open('$MANIFEST'))
digests = [m['config']['digest']]
digests += [l['digest'] for l in m.get('layers', [])]
for d in digests:
    # strip 'sha256:' prefix → file basename sha256-<hex>
    print('sha256-' + d.split(':', 1)[1])
")

for blob in $BLOBS; do
    src="$HOST_MODELS/blobs/$blob"
    dst="$DST_BLOBS/$blob"
    [ -f "$src" ] || err "blob missing on host: $src"
    # Hardlink where possible (same filesystem) to save 1.8 GB of RAM during
    # copy; fall back to copy if cross-device.
    ln -f "$src" "$dst" 2>/dev/null || install -m 0644 "$src" "$dst"
done

MODEL_SIZE=$(du -sh "$EXTRA/usr/share/ollama" | cut -f1)
ok "Ollama model baked: $MODEL_SIZE"

# ─── 2. Claude Code CLI ───────────────────────────────────────────────
info "baking Claude Code CLI via npm"

command -v npm >/dev/null 2>&1 || err "npm not installed on host"

STAGING=$(mktemp -d)
trap "rm -rf $STAGING" EXIT

npm install -g --prefix "$STAGING" --omit=optional --no-audit --no-fund \
    "$CLAUDE_PKG" >/dev/null 2>&1 \
    || err "npm install $CLAUDE_PKG failed — check host network"

# Sanity check
[ -x "$STAGING/bin/claude" ] || err "staging claude binary missing: $STAGING/bin/claude"
CLAUDE_VER=$("$STAGING/bin/claude" --version 2>&1 | head -1)
info "staged $CLAUDE_VER"

# Wipe old copy (npm install is not idempotent on version bumps)
rm -rf "$EXTRA/usr/bin/claude" "$EXTRA/usr/lib/node_modules/@anthropic-ai"

mkdir -p "$EXTRA/usr/bin" "$EXTRA/usr/lib/node_modules"
cp -a "$STAGING/bin/claude" "$EXTRA/usr/bin/claude"
cp -a "$STAGING/lib/node_modules/@anthropic-ai" "$EXTRA/usr/lib/node_modules/"

# Record version for smoke-test to assert
mkdir -p "$EXTRA/usr/share/vibeos"
echo "$CLAUDE_VER" > "$EXTRA/usr/share/vibeos/CLAUDE_BAKED_VERSION"

ok "Claude CLI baked: $CLAUDE_VER"

# ─── 3. Live-session marker ────────────────────────────────────────────
# Dropped in /etc so it survives mkosi.extra copy. Calamares
# contextualprocess module must `rm /target/etc/vibeos/live-session`
# during install. If the file is absent → we are on the installed
# system; if present → live session.
mkdir -p "$EXTRA/etc/vibeos"
echo "1" > "$EXTRA/etc/vibeos/live-session"

# ─── 4. Summary ───────────────────────────────────────────────────────
TOTAL=$(du -sh "$EXTRA" 2>/dev/null | cut -f1)
ok "mkosi.extra total: $TOTAL"
info "next: scripts/build.sh"
