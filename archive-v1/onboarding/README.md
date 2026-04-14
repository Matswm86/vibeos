# VibeOS Onboarding Agent

Ollama-powered guided first-boot experience. Runs after `install.sh` to walk the user through authentication, configuration, and verification.

## Usage

```bash
# Runs automatically at end of install.sh, or manually:
cd /path/to/vibeos
python3 -m onboarding

# Use a different model:
python3 -m onboarding --model qwen3:4b
```

## Requirements

- Python 3.11+ (installed by `install.sh`)
- Ollama running (`ollama serve`)
- A pulled model (default: `gemma3:4b`, pulled by `install.sh`)
- No pip packages — stdlib only

## Flow

6-step state machine:

1. **Welcome** — hardware summary, overview of what's coming
2. **Experience check** — beginner / intermediate / advanced (adapts tone)
3. **Claude Code auth** — guides user through `claude` interactive auth
4. **MCP configuration** — verifies `~/.mcp.json`, `~/CLAUDE.md`, `GITHUB_TOKEN`
5. **Verification** — checks all tools are installed and configured
6. **Handoff** — summary + `cd ~/ && claude`

## Architecture

```
onboarding/
├── __init__.py         # Package marker
├── __main__.py         # Entry point (python3 -m onboarding)
├── agent.py            # Ollama HTTP client (streaming, conversation history)
├── flow.py             # 6-step state machine + hardware detection
├── shell.py            # Subprocess wrapper with output capture
└── system_prompt.py    # Hardware/experience-aware prompt builder
```

Each step clears conversation history to keep context small — the 4B model works best with focused, single-step prompts.
