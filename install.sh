#!/bin/bash
# ============================================================
# VibeOS — AI-Native Linux Development Environment
# ============================================================
#
# Sets up a complete Claude Code environment with:
#   - Python 3 (3.10+), Node 22, Docker
#   - Ollama (local AI models)
#   - Default MCP servers (memory, github)
#   - Claude Code CLI
#   - Starter CLAUDE.md + settings templates at ~/.claude/
#
# Usage (one-liner):
#   curl -sSL https://raw.githubusercontent.com/Matswm86/vibeos/main/install.sh | bash
#
# Or manually:
#   chmod +x install.sh && ./install.sh
#
# Supports: Ubuntu 22.04+, Ubuntu 24.04, Pop!_OS 22.04+, Debian 12+
#
# Escape hatches (env vars):
#   VIBEOS_NO_ONBOARDING=1   skip the Ollama-powered onboarding agent
#   VIBEOS_NO_CLIPPY=1       skip Clippy launch (once Clippy ships)
#   VIBEOS_OFFLINE=1         skip network-dependent installs (Ollama models, etc.)
# ============================================================

set -euo pipefail

VIBEOS_VERSION="0.3.2"
VIBEOS_DIR="${HOME}/.vibeos"
VIBEOS_REPO="https://github.com/Matswm86/vibeos.git"
CLAUDE_DIR="${HOME}/.claude"
NPM_PREFIX="${HOME}/.npm-global"

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[→]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

# ── Resolve SCRIPT_DIR (handles curl-pipe and local run) ───
if [[ -z "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]}" == "/dev/stdin" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]]; then
    PIPED_MODE=true
    if [[ -d "${VIBEOS_DIR}/.git" ]]; then
        info "Updating VibeOS repo at ${VIBEOS_DIR}..."
        git -C "${VIBEOS_DIR}" pull --quiet 2>/dev/null || true
    else
        info "Cloning VibeOS repo to ${VIBEOS_DIR}..."
        git clone --depth=1 "${VIBEOS_REPO}" "${VIBEOS_DIR}"
    fi
    SCRIPT_DIR="${VIBEOS_DIR}"
else
    PIPED_MODE=false
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# TTY-safe prompt: in pipe mode, read from /dev/tty if available
ask_user() {
    local prompt="$1" default="${2:-}"
    local reply=""
    if [[ -t 0 ]]; then
        read -rp "$prompt" reply || reply=""
    elif [[ -e /dev/tty ]]; then
        read -rp "$prompt" reply </dev/tty || reply=""
    else
        reply=""
    fi
    echo "${reply:-${default}}"
}

# ── 0. Hardware detection ───────────────────────────────────
header "=== VibeOS ${VIBEOS_VERSION} — Hardware Detection ==="

RAM_GB=$(free -g | awk '/Mem:/{print $2}')
CPU_MODEL=$(lscpu | grep "Model name" | sed 's/Model name:[ \t]*//')
GPU_INFO=$(lspci 2>/dev/null | grep -iE 'vga|3d|display|nvidia|amd|radeon' | head -3 || echo "none detected")

VRAM_GB=0
if command -v nvidia-smi &>/dev/null; then
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
    VRAM_GB=$(( VRAM_MB / 1024 ))
fi

echo "  CPU:  ${CPU_MODEL}"
echo "  RAM:  ${RAM_GB} GB"
echo "  GPU:  ${GPU_INFO}"
[[ $VRAM_GB -gt 0 ]] && echo "  VRAM: ${VRAM_GB} GB (NVIDIA)"

OLLAMA_ONBOARD_MODEL="gemma3:4b"
OLLAMA_SUGGEST=""
if [[ $VRAM_GB -ge 16 ]]; then
    OLLAMA_SUGGEST="qwen2.5:14b or llama3.1:13b (16GB VRAM — fast)"
elif [[ $VRAM_GB -ge 8 ]]; then
    OLLAMA_SUGGEST="qwen2.5:7b or llama3.1:8b (8GB VRAM — good)"
elif [[ $VRAM_GB -ge 4 ]]; then
    OLLAMA_SUGGEST="gemma3:4b (4GB VRAM — solid)"
else
    OLLAMA_SUGGEST="gemma3:4b (CPU mode — works, ~10 t/s)"
fi

[[ $RAM_GB -lt 8 ]] && error "8GB RAM minimum required. Found: ${RAM_GB}GB"

echo ""
echo "  Onboarding model: ${OLLAMA_ONBOARD_MODEL}"
echo "  Suggested local model: ${OLLAMA_SUGGEST}"

# ── 1. System packages ──────────────────────────────────────
header "[1/7] System packages"

# Detect the python3 package that actually exists on this distro.
# Ubuntu 22.04 → python3.11 package
# Ubuntu 24.04 → python3.12 package (default python3)
# Debian 12    → python3.11
# Never hard-code a version; require >= 3.10 at the end.
sudo apt update -qq
sudo apt install -y \
    python3 python3-venv python3-pip \
    git curl wget jq ca-certificates gnupg lsb-release \
    build-essential libffi-dev libssl-dev

PY_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")"
PY_MAJOR="${PY_VERSION%%.*}"
PY_MINOR="${PY_VERSION##*.}"
if [[ "${PY_MAJOR}" -lt 3 ]] || { [[ "${PY_MAJOR}" -eq 3 ]] && [[ "${PY_MINOR}" -lt 10 ]]; }; then
    error "Python 3.10+ required. Found: ${PY_VERSION}"
fi
success "Python ${PY_VERSION}"

# Node 22 via NodeSource (apt ships Node 12 on Ubuntu 22.04)
if ! command -v node &>/dev/null || [[ "$(node --version | cut -d. -f1 | tr -d v)" -lt 20 ]]; then
    info "Installing Node 22 via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null
    sudo apt install -y nodejs
fi
success "Node $(node --version)"

# ── 2. Docker ───────────────────────────────────────────────
header "[2/7] Docker"

if ! command -v docker &>/dev/null; then
    info "Installing Docker via get.docker.com..."
    # Download to a temp file first so we can read what we're about to run.
    DOCKER_INSTALLER="$(mktemp)"
    curl -fsSL https://get.docker.com -o "${DOCKER_INSTALLER}"
    # Sanity check: must start with shebang and contain the docker repo url
    if ! head -n1 "${DOCKER_INSTALLER}" | grep -q '^#!/'; then
        rm -f "${DOCKER_INSTALLER}"
        error "Docker installer did not look like a shell script — aborting."
    fi
    sudo sh "${DOCKER_INSTALLER}"
    rm -f "${DOCKER_INSTALLER}"
fi

sudo usermod -aG docker "${USER:-$(id -un)}"
sudo systemctl enable --now docker 2>/dev/null || true
success "Docker $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d , || echo 'installed')"
warn "Docker group change requires logout/login to take effect"

# ── 3. Environment ──────────────────────────────────────────
header "[3/7] Environment"
SHELL_RC="${HOME}/.bashrc"
[[ -n "${ZSH_VERSION:-}" ]] && SHELL_RC="${HOME}/.zshrc"

# Single marker-bracketed block so re-runs replace cleanly instead of stacking.
ENV_BLOCK_START="# >>> VibeOS env >>>"
ENV_BLOCK_END="# <<< VibeOS env <<<"
ENV_BLOCK_BODY=$(cat <<'EOF'
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"
export MCP_TIMEOUT=300000
# vibe: always start Claude Code from $HOME so ~/.mcp.json loads.
alias vibe='cd ~ && claude'
EOF
)

if grep -q "${ENV_BLOCK_START}" "${SHELL_RC}" 2>/dev/null; then
    # Replace existing block in place
    python3 - "${SHELL_RC}" "${ENV_BLOCK_START}" "${ENV_BLOCK_END}" "${ENV_BLOCK_BODY}" <<'PYEOF'
import sys
from pathlib import Path
path, start, end, body = sys.argv[1:5]
text = Path(path).read_text()
before, _, rest = text.partition(start)
_, _, after = rest.partition(end)
new = f"{before}{start}\n{body}\n{end}{after}"
Path(path).write_text(new)
PYEOF
    success "Environment block refreshed in ${SHELL_RC}"
else
    {
        echo ""
        echo "${ENV_BLOCK_START}"
        echo "${ENV_BLOCK_BODY}"
        echo "${ENV_BLOCK_END}"
    } >> "${SHELL_RC}"
    success "Environment block added to ${SHELL_RC}"
fi

# Make env effective for the rest of this script
export PATH="${NPM_PREFIX}/bin:${HOME}/.local/bin:${PATH}"
export MCP_TIMEOUT=300000

# ── 4. Ollama ───────────────────────────────────────────────
header "[4/7] Ollama"
if ! command -v ollama &>/dev/null; then
    info "Installing Ollama (to temp file first, not nested curl-pipe)..."
    OLLAMA_INSTALLER="$(mktemp)"
    curl -fsSL https://ollama.com/install.sh -o "${OLLAMA_INSTALLER}"
    if ! head -n1 "${OLLAMA_INSTALLER}" | grep -q '^#!/'; then
        rm -f "${OLLAMA_INSTALLER}"
        error "Ollama installer did not look like a shell script — aborting."
    fi
    sh "${OLLAMA_INSTALLER}"
    rm -f "${OLLAMA_INSTALLER}"
fi
success "Ollama $(ollama --version 2>/dev/null | head -1 || echo installed)"

if [[ "${VIBEOS_OFFLINE:-0}" == "1" ]]; then
    warn "VIBEOS_OFFLINE=1 — skipping Ollama model pull"
else
    info "Pulling onboarding model (${OLLAMA_ONBOARD_MODEL})..."
    ollama pull "${OLLAMA_ONBOARD_MODEL}" || warn "Ollama pull failed — onboarding agent will retry on first launch."
    success "Onboarding model ready"
fi

if [[ -n "${OLLAMA_SUGGEST}" ]]; then
    warn "For full local AI: ollama pull ${OLLAMA_SUGGEST%%' ('*}"
fi

# ── 5. npm global prefix + MCP servers + Claude Code ───────
header "[5/7] npm global + MCP servers + Claude Code"

# Configure npm to install globally into $HOME — no sudo, no EACCES.
mkdir -p "${NPM_PREFIX}"
npm config set prefix "${NPM_PREFIX}" >/dev/null

info "Installing default MCP servers (memory, github)..."
npm install -g \
    @modelcontextprotocol/server-memory \
    @modelcontextprotocol/server-github

success "MCP servers installed:"
success "  • memory  — SQLite knowledge graph at ~/.claude-memory"
success "  • github  — repository operations (needs GITHUB_TOKEN)"

if ! command -v claude &>/dev/null; then
    info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
fi
success "Claude Code $(claude --version 2>/dev/null || echo '— run: claude --version')"

# ── 6. GitHub CLI ───────────────────────────────────────────
header "[6/7] GitHub CLI"
if ! command -v gh &>/dev/null; then
    info "Installing gh CLI..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt update -qq && sudo apt install -y gh
fi
success "gh CLI $(gh --version 2>/dev/null | head -1 || echo installed)"

# ── 7. Deploy Claude Code config ────────────────────────────
header "[7/7] Claude Code config + templates"
mkdir -p "${CLAUDE_DIR}"

# CLAUDE.md → ~/.claude/CLAUDE.md is Claude Code's true global auto-load path.
# We also drop a copy at ~/CLAUDE.md so `claude` started from $HOME sees it as
# a project-level file. Both paths, no ambiguity.
if [[ -f "${SCRIPT_DIR}/templates/CLAUDE.md" ]]; then
    if [[ ! -f "${CLAUDE_DIR}/CLAUDE.md" ]]; then
        cp "${SCRIPT_DIR}/templates/CLAUDE.md" "${CLAUDE_DIR}/CLAUDE.md"
        success "CLAUDE.md → ${CLAUDE_DIR}/CLAUDE.md (global auto-load)"
    else
        success "CLAUDE.md already at ${CLAUDE_DIR}/CLAUDE.md — keeping existing"
    fi
    if [[ ! -f "${HOME}/CLAUDE.md" ]]; then
        cp "${SCRIPT_DIR}/templates/CLAUDE.md" "${HOME}/CLAUDE.md"
        success "CLAUDE.md → ${HOME}/CLAUDE.md (project-level fallback)"
    fi
fi

# settings.json → ~/.claude/settings.json (the documented global)
if [[ -f "${SCRIPT_DIR}/templates/settings.json" ]] && [[ ! -f "${CLAUDE_DIR}/settings.json" ]]; then
    cp "${SCRIPT_DIR}/templates/settings.json" "${CLAUDE_DIR}/settings.json"
    success "settings.json → ${CLAUDE_DIR}/settings.json"
fi

# .mcp.json → resolve ${HOME} at install time, write to both ~/.claude/.mcp.json
# (user-level) AND ~/.mcp.json (loaded when claude starts from $HOME).
if [[ -f "${SCRIPT_DIR}/templates/.mcp.json" ]]; then
    RESOLVED_MCP="$(sed "s|\${HOME}|${HOME}|g" "${SCRIPT_DIR}/templates/.mcp.json")"
    if [[ ! -f "${CLAUDE_DIR}/.mcp.json" ]]; then
        printf '%s\n' "${RESOLVED_MCP}" > "${CLAUDE_DIR}/.mcp.json"
        success ".mcp.json → ${CLAUDE_DIR}/.mcp.json"
    fi
    if [[ ! -f "${HOME}/.mcp.json" ]]; then
        printf '%s\n' "${RESOLVED_MCP}" > "${HOME}/.mcp.json"
        success ".mcp.json → ${HOME}/.mcp.json"
    fi
fi

# memory_location.md — explain the single-location rule once, at install time,
# so VibeOS users never stumble into dual-memory drift between MCP's knowledge
# graph and Claude Code's per-project auto-memory.
cat > "${CLAUDE_DIR}/memory_location.md" <<'EOF'
# Memory — single-location rule

VibeOS stores Claude memory in **exactly two files**:

1. `~/.claude-memory` — MCP knowledge-graph SQLite, managed by
   `@modelcontextprotocol/server-memory`. Persistent across projects.
2. `~/.claude/projects/<encoded-cwd>/memory/` — Claude Code's per-project
   auto-memory. Managed by Claude Code itself.

**Do not create a third location** (like `~/memory/` or a custom dir in a
project). If you want project notes, put them in that project's own dir as
`MEMORY.md` or `notes/`, not in a separate memory folder. Dual memory paths
always drift; the fix is to not have two in the first place.

If Claude ever claims a "primary memory location" other than these two, it is
hallucinating a convention from another workspace. Point it back at this file.
EOF
success "memory_location.md → ${CLAUDE_DIR}/memory_location.md"

# ── Summary ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${GREEN}  VibeOS ${VIBEOS_VERSION} setup complete!${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Log out and back in  (Docker group takes effect)"
echo "  2. Authenticate Claude:  claude  (follow prompts)"
echo "  3. Authenticate GitHub:  gh auth login"
echo "  4. Set GitHub token:     export GITHUB_TOKEN=ghp_..."
echo "  5. Start coding:         vibe   (alias for: cd ~ && claude)"
echo ""
[[ $VRAM_GB -gt 0 ]] && echo "  Optional: ollama pull ${OLLAMA_SUGGEST%%' ('*}"
[[ $VRAM_GB -eq 0 ]] && echo "  Tip: Add an NVIDIA GPU for faster local models"
echo ""
echo "  Docs: https://github.com/Matswm86/vibeos"
echo -e "${BOLD}============================================================${NC}"

# ── Onboarding agent ────────────────────────────────────────
echo ""
if [[ "${VIBEOS_NO_ONBOARDING:-0}" == "1" ]]; then
    info "VIBEOS_NO_ONBOARDING=1 set — skipping onboarding agent."
    echo "  Run it later:  cd ${SCRIPT_DIR} && python3 -m onboarding"
elif [[ -d "${SCRIPT_DIR}/onboarding" ]]; then
    info "Starting onboarding agent (Ollama + ${OLLAMA_ONBOARD_MODEL})..."
    (cd "${SCRIPT_DIR}" && python3 -m onboarding --model "${OLLAMA_ONBOARD_MODEL}") \
        || warn "Onboarding agent exited early. Re-run anytime: cd ${SCRIPT_DIR} && python3 -m onboarding"
else
    warn "Onboarding directory not found at ${SCRIPT_DIR}/onboarding. Skipping."
fi

# ── Let loose ──────────────────────────────────────────────
# Clippy's final line before handing the user over to Claude Code itself.
echo ""
echo -e "${BOLD}${YELLOW}  📎 Vibbey:${NC} ${BOLD}Looks like you're about to Vibe hard.${NC}"
echo -e "${BOLD}${YELLOW}              ${NC} ${BOLD}Would you like to continue? ;)${NC}"
echo ""
echo -e "      ${GREEN}→  vibe${NC}       ${BOLD}(start Claude Code)${NC}"
echo ""
