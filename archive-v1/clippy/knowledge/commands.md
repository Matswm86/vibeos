# Common commands Vibbey should know and teach

When a user asks "how do I X", prefer to teach them the exact command. Keep answers to 2-3 sentences plus a code block.

## Opening a terminal

- **KDE Plasma**: `Ctrl+Alt+T`, or search "Konsole" in the application launcher (Super key), or right-click desktop → Open Terminal
- **If the shortcut doesn't work**: search "Konsole" from the application launcher

## Claude Code

```bash
# Check it's installed
claude --version

# Start a new session in the current directory
claude

# Start with a specific model
claude --model claude-opus-4-6

# One-shot query without interactive mode
claude -p "explain this file" < main.py
```

## GitHub CLI (gh)

```bash
# First-time auth (opens browser)
gh auth login

# Check auth status
gh auth status

# Clone a repo
gh repo clone owner/repo

# Create a PR from current branch
gh pr create

# View your repos
gh repo list
```

## Ollama (local LLMs)

```bash
# List pulled models
ollama list

# Pull a model (default VibeOS chat model)
ollama pull gemma3:4b

# Run a model interactively
ollama run gemma3:4b

# Check the server status
systemctl status ollama
```

## Git essentials

```bash
# Current status
git status

# Stage everything
git add .

# Commit
git commit -m "message"

# Push current branch
git push

# See recent commits
git log --oneline -10
```

## Docker

```bash
# Is Docker running?
docker info

# Running containers
docker ps

# All containers (including stopped)
docker ps -a

# Run a container
docker run -it --rm ubuntu:22.04 bash
```

## System inspection

```bash
# OS version
cat /etc/os-release

# Kernel
uname -a

# RAM
free -h

# Disk space on home
df -h ~

# CPU info
lscpu | head

# GPU (NVIDIA)
nvidia-smi

# Processes using most CPU
top
# or prettier:
htop
```

## Python

```bash
# Version
python3 --version

# Create a venv
python3 -m venv .venv

# Activate
source .venv/bin/activate

# Install a package
pip install requests
```

## VibeOS-specific paths

- `~/.vibeos/` — Vibbey's config directory (memory, Groq token, first-run marker)
- `~/.vibeos/vibbey-memory.json` — persistent chat memory + user profile
- `~/.vibeos/groq.token` — bootstrap JWT for the hosted Groq proxy (300 messages)
- `~/.vibeos/groq.key` — user-provided Groq API key (after bootstrap burns)
- `~/.vibeos/first-run-complete` — marker; delete to re-trigger first-run autostart
- `/opt/vibeos/` — VibeOS repo clone (install.sh landing site on ISO installs)
