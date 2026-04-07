#!/bin/bash
# ============================================================
# VibeOS — AI-Native Linux Development Environment
# ============================================================
#
# Sets up a complete Claude Code environment with:
#   - Python 3.11, Node 22, Docker
#   - Ollama (local AI models)
#   - Default MCP servers (memory, filesystem, GitHub)
#   - Claude Code CLI
#   - Starter CLAUDE.md + settings templates
#
# Usage (one-liner):
#   curl -sSL https://raw.githubusercontent.com/Matswm86/vibeos/main/install.sh | bash
#
# Or manually:
#   chmod +x install.sh && ./install.sh
#
# Supports: Ubuntu 22.04+, Pop!_OS 22.04+, Debian 12+
# ============================================================

set -euo pipefail

VIBEOS_VERSION="0.2.0"
VIBEOS_DIR="${HOME}/.vibeos"
VIBEOS_REPO="https://github.com/Matswm86/vibeos.git"
CLAUDE_DIR="${HOME}/.claude"

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
# When run via `curl ... | bash`, BASH_SOURCE is empty or /dev/stdin.
# In that case, clone the repo so templates and onboarding are available.
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
    if [[ -t 0 ]]; then
        read -rp "$prompt" REPLY
    elif [[ -e /dev/tty ]]; then
        read -rp "$prompt" REPLY </dev/tty
    else
        REPLY="${default}"
    fi
    echo "${REPLY:-${default}}"
}

# ── 0. Hardware detection ───────────────────────────────────
header "=== VibeOS ${VIBEOS_VERSION} — Hardware Detection ==="

RAM_GB=$(free -g | awk '/Mem:/{print $2}')
CPU_MODEL=$(lscpu | grep "Model name" | sed 's/Model name:[ \t]*//')
GPU_INFO=$(lspci 2>/dev/null | grep -iE 'vga|3d|display|nvidia|amd|radeon' | head -3 || echo "none detected")

# NVIDIA VRAM detection
VRAM_GB=0
if command -v nvidia-smi &>/dev/null; then
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
    VRAM_GB=$(( VRAM_MB / 1024 ))
fi

echo "  CPU:  ${CPU_MODEL}"
echo "  RAM:  ${RAM_GB} GB"
echo "  GPU:  ${GPU_INFO}"
[[ $VRAM_GB -gt 0 ]] && echo "  VRAM: ${VRAM_GB} GB (NVIDIA)"

# Determine Ollama tier
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
sudo apt update -qq && sudo apt install -y \
    python3.11 python3.11-venv python3-pip \
    docker-compose-plugin \
    git curl wget jq \
    build-essential libffi-dev libssl-dev

# Ensure python3 → 3.11
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 2>/dev/null || true
sudo update-alternatives --install /usr/bin/python  python  /usr/bin/python3.11 1 2>/dev/null || true

# Node 22 via NodeSource (apt ships Node 12 on Ubuntu 22.04)
if ! command -v node &>/dev/null || [[ "$(node --version | cut -d. -f1 | tr -d v)" -lt 20 ]]; then
    info "Installing Node 22 via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null
    sudo apt install -y nodejs
fi

success "Python $(python3 --version) | Node $(node --version) | Docker $(docker --version | cut -d' ' -f3 | tr -d ,)"

# ── 2. Docker ───────────────────────────────────────────────
header "[2/7] Docker"
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker
success "Docker configured (group change requires logout/login)"

# ── 3. Environment ──────────────────────────────────────────
header "[3/7] Environment"
SHELL_RC="${HOME}/.bashrc"
[[ -n "${ZSH_VERSION:-}" ]] && SHELL_RC="${HOME}/.zshrc"

ENV_BLOCK='
# VibeOS — added by install.sh
export PATH="${PATH}:${HOME}/.local/bin"
export MCP_TIMEOUT=300000
'
if ! grep -q "VibeOS" "${SHELL_RC}" 2>/dev/null; then
    echo "$ENV_BLOCK" >> "${SHELL_RC}"
    success "Environment variables added to ${SHELL_RC}"
else
    success "Environment already configured"
fi
export PATH="${PATH}:${HOME}/.local/bin"
export MCP_TIMEOUT=300000

# ── 4. Ollama ───────────────────────────────────────────────
header "[4/7] Ollama"
if ! command -v ollama &>/dev/null; then
    info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
fi
success "Ollama $(ollama --version 2>/dev/null | head -1)"

info "Pulling onboarding model (${OLLAMA_ONBOARD_MODEL})..."
ollama pull "${OLLAMA_ONBOARD_MODEL}"
success "Onboarding model ready"

if [[ -n "${OLLAMA_SUGGEST}" ]]; then
    warn "For full local AI: ollama pull ${OLLAMA_SUGGEST%%' ('*}"
fi

# ── 5. MCP servers ──────────────────────────────────────────
header "[5/7] MCP servers"
info "Installing default MCP servers..."

npm install -g \
    @modelcontextprotocol/server-memory \
    @modelcontextprotocol/server-filesystem \
    @modelcontextprotocol/server-github \
    2>/dev/null

success "MCP servers installed:"
success "  • memory    — SQLite knowledge graph at ~/.claude-memory"
success "  • filesystem — local file access"
success "  • github    — repository operations (needs GITHUB_TOKEN)"

# ── 6. Claude Code ──────────────────────────────────────────
header "[6/7] Claude Code"
if ! command -v claude &>/dev/null; then
    info "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code
fi
success "Claude Code $(claude --version 2>/dev/null || echo '— run: claude --version')"

# ── 7. GitHub CLI ───────────────────────────────────────────
header "[7/7] GitHub CLI"
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
success "gh CLI $(gh --version 2>/dev/null | head -1)"

# ── Deploy starter templates ─────────────────────────────────
header "Deploying starter templates"
mkdir -p "${CLAUDE_DIR}"

if [[ -f "${SCRIPT_DIR}/templates/CLAUDE.md" ]] && [[ ! -f "${HOME}/CLAUDE.md" ]]; then
    cp "${SCRIPT_DIR}/templates/CLAUDE.md" "${HOME}/CLAUDE.md"
    success "CLAUDE.md deployed to ~/CLAUDE.md"
fi

if [[ -f "${SCRIPT_DIR}/templates/settings.json" ]] && [[ ! -f "${CLAUDE_DIR}/settings.json" ]]; then
    cp "${SCRIPT_DIR}/templates/settings.json" "${CLAUDE_DIR}/settings.json"
    success "settings.json deployed to ~/.claude/settings.json"
fi

if [[ -f "${SCRIPT_DIR}/templates/.mcp.json" ]] && [[ ! -f "${HOME}/.mcp.json" ]]; then
    cp "${SCRIPT_DIR}/templates/.mcp.json" "${HOME}/.mcp.json"
    success ".mcp.json deployed to ~/.mcp.json"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${GREEN}  VibeOS setup complete!${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Log out and back in  (Docker group takes effect)"
echo "  2. Authenticate Claude:  claude  (follow prompts)"
echo "  3. Authenticate GitHub:  gh auth login"
echo "  4. Set GitHub token:     export GITHUB_TOKEN=ghp_..."
echo "  5. Start coding:         cd ~/  &&  claude"
echo ""
[[ $VRAM_GB -gt 0 ]] && echo "  Optional: ollama pull ${OLLAMA_SUGGEST%%' ('*}"
[[ $VRAM_GB -eq 0 ]] && echo "  Tip: Add an NVIDIA GPU module for faster local models"
echo ""
echo "  Docs: https://github.com/Matswm86/vibeos"
echo -e "${BOLD}============================================================${NC}"

# ── Onboarding agent ────────────────────────────────────────
echo ""
RUN_ONBOARD=$(ask_user "Run the guided onboarding agent? [Y/n] " "Y")

if [[ "${RUN_ONBOARD}" =~ ^[Yy]$ ]]; then
    if [[ -d "${SCRIPT_DIR}/onboarding" ]]; then
        info "Starting onboarding agent (Ollama + ${OLLAMA_ONBOARD_MODEL})..."
        (cd "${SCRIPT_DIR}" && python3 -m onboarding --model "${OLLAMA_ONBOARD_MODEL}") \
            || warn "Onboarding agent exited. You can re-run it anytime:"
        echo "    cd ${SCRIPT_DIR} && python3 -m onboarding"
    else
        warn "Onboarding directory not found at ${SCRIPT_DIR}/onboarding. Skipping."
    fi
else
    echo ""
    echo "  No problem! Run onboarding later:"
    echo "    cd ${SCRIPT_DIR} && python3 -m onboarding"
    echo ""
fi
