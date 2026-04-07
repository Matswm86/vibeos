"""6-step onboarding state machine.

Flow: welcome → experience → auth_claude → config_mcp → verify → handoff

Each step is either:
  - Programmatic (runs commands, checks state)
  - Conversational (Ollama agent talks to user)
  - Mixed (programmatic check + agent commentary)
"""

import os
import sys
from enum import Enum
from pathlib import Path

from . import shell
from .agent import OllamaAgent
from .system_prompt import HardwareInfo, build_prompt

CLAUDE_DIR = Path.home() / ".claude"
MCP_CONFIG = Path.home() / ".mcp.json"
CLAUDE_MD = Path.home() / "CLAUDE.md"

# ── Colors ──────────────────────────────────────────────────
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
BOLD = "\033[1m"
NC = "\033[0m"


class Step(Enum):
    WELCOME = "welcome"
    EXPERIENCE = "experience"
    AUTH_CLAUDE = "auth_claude"
    CONFIG_MCP = "config_mcp"
    VERIFY = "verify"
    HANDOFF = "handoff"


STEP_ORDER = list(Step)


def _input(prompt: str = "> ") -> str:
    """Read user input with prompt."""
    try:
        return input(f"{BLUE}{prompt}{NC}").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        sys.exit(0)


def _banner(text: str) -> None:
    print(f"\n{BOLD}{'─' * 50}")
    print(f"  {text}")
    print(f"{'─' * 50}{NC}\n")


# ── Hardware detection ──────────────────────────────────────

def detect_hardware() -> HardwareInfo:
    """Detect system hardware (mirrors install.sh logic)."""
    hw = HardwareInfo()

    result = shell.run("lscpu | grep 'Model name' | sed 's/Model name:[ \\t]*//'")
    if result.ok:
        hw.cpu = result.output or "unknown"

    result = shell.run("free -g | awk '/Mem:/{print $2}'")
    if result.ok:
        try:
            hw.ram_gb = int(result.output)
        except ValueError:
            pass

    result = shell.run("lspci 2>/dev/null | grep -iE 'vga|3d|display|nvidia|amd|radeon' | head -1")
    if result.ok and result.output:
        hw.gpu = result.output

    if shell.has_command("nvidia-smi"):
        result = shell.run(
            "nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1"
        )
        if result.ok:
            try:
                hw.vram_gb = int(result.output) // 1024
            except ValueError:
                pass

    return hw


# ── Experience classifier ──────────────────────────────────

def classify_experience(text: str) -> str:
    """Rough classification from user's self-description."""
    text_lower = text.lower()
    beginner_signals = ["new", "beginner", "first", "learning", "start", "never", "noob"]
    advanced_signals = ["senior", "years", "decade", "advanced", "power", "expert", "10+", "pro"]

    if any(s in text_lower for s in beginner_signals):
        return "beginner"
    if any(s in text_lower for s in advanced_signals):
        return "advanced"
    return "intermediate"


# ── Step runners ────────────────────────────────────────────

def run_welcome(agent: OllamaAgent, hw: HardwareInfo) -> None:
    """Step 1: Welcome + overview."""
    _banner("Welcome to VibeOS")
    print(f"  {hw.summary.replace(chr(10), chr(10) + '  ')}\n")
    agent.set_system(build_prompt(hw, "welcome"))
    agent.generate_no_input(
        "The user just finished installing VibeOS. Welcome them and explain what comes next."
    )
    print()


def run_experience(agent: OllamaAgent, hw: HardwareInfo) -> str:
    """Step 2: Detect experience level. Returns 'beginner'/'intermediate'/'advanced'."""
    _banner("Step 1/4 — Experience Check")
    agent.set_system(build_prompt(hw, "experience"))
    agent.generate_no_input("Ask the user about their development experience level.")
    print()

    answer = _input()
    experience = classify_experience(answer)

    # Let the agent acknowledge and move on
    agent.set_system(build_prompt(hw, "experience", experience))
    agent.chat(answer)
    print()
    return experience


def run_auth_claude(agent: OllamaAgent, hw: HardwareInfo, experience: str) -> None:
    """Step 3: Claude Code authentication."""
    _banner("Step 2/4 — Claude Code Authentication")
    agent.set_system(build_prompt(hw, "auth_claude", experience))

    # Check if claude is installed
    if shell.has_command("claude"):
        version = shell.run("claude --version").output
        agent.generate_no_input(
            f"Claude Code is installed (version: {version}). "
            "Tell the user to run `claude` in their terminal to authenticate. "
            "Explain this is interactive — they need to follow the prompts."
        )
    else:
        agent.generate_no_input(
            "Claude Code doesn't seem to be installed. "
            "Tell the user to run: npm install -g @anthropic-ai/claude-code"
        )

    print()
    print(f"  {YELLOW}When you're done authenticating, come back here and press Enter.{NC}")
    _input("Press Enter to continue... ")
    print()


def run_config_mcp(agent: OllamaAgent, hw: HardwareInfo, experience: str) -> None:
    """Step 4: MCP configuration verification."""
    _banner("Step 3/4 — MCP Configuration")
    agent.set_system(build_prompt(hw, "config_mcp", experience))

    # Check what's in place
    mcp_exists = MCP_CONFIG.exists()
    claude_md_exists = CLAUDE_MD.exists()
    has_gh_token = bool(os.environ.get("GITHUB_TOKEN"))

    status_parts = []
    if mcp_exists:
        mcp_content = MCP_CONFIG.read_text()
        status_parts.append(f"~/.mcp.json exists with content:\n{mcp_content}")
    else:
        status_parts.append("~/.mcp.json is MISSING")

    if claude_md_exists:
        status_parts.append("~/CLAUDE.md exists")
    else:
        status_parts.append("~/CLAUDE.md is MISSING")

    if has_gh_token:
        status_parts.append("GITHUB_TOKEN is set")
    else:
        status_parts.append("GITHUB_TOKEN is NOT set (optional)")

    context = (
        "Here's the current MCP configuration status:\n"
        + "\n".join(f"- {p}" for p in status_parts)
        + "\n\nReport this status to the user. If GITHUB_TOKEN is missing, "
        "briefly explain how to set it up (it's optional)."
    )

    agent.generate_no_input(context)
    print()

    if not has_gh_token:
        print(f"  {YELLOW}Set up GitHub token now, or press Enter to skip.{NC}")
        _input("Press Enter to continue... ")
        print()


def run_verify(agent: OllamaAgent, hw: HardwareInfo, experience: str) -> bool:
    """Step 5: Verify everything works. Returns True if all critical checks pass."""
    _banner("Step 4/4 — Verification")
    agent.set_system(build_prompt(hw, "verify", experience))

    checks = []

    # Claude Code
    if shell.has_command("claude"):
        version = shell.run("claude --version").output
        checks.append(f"PASS: Claude Code installed ({version})")
    else:
        checks.append("FAIL: Claude Code not found on PATH")

    # MCP config
    if MCP_CONFIG.exists():
        checks.append(f"PASS: {MCP_CONFIG} exists")
    else:
        checks.append(f"FAIL: {MCP_CONFIG} missing")

    # CLAUDE.md
    if CLAUDE_MD.exists():
        checks.append(f"PASS: {CLAUDE_MD} exists")
    else:
        checks.append(f"WARN: {CLAUDE_MD} missing (optional but recommended)")

    # Ollama
    if shell.has_command("ollama"):
        models = shell.run("ollama list 2>/dev/null").output
        checks.append(f"PASS: Ollama installed, models:\n{models}")
    else:
        checks.append("WARN: Ollama not found")

    # Git
    if shell.has_command("git"):
        checks.append("PASS: git installed")
    else:
        checks.append("FAIL: git not found")

    # Node
    if shell.has_command("node"):
        node_v = shell.run("node --version").output
        checks.append(f"PASS: Node.js {node_v}")
    else:
        checks.append("FAIL: Node.js not found")

    context = "Verification results:\n" + "\n".join(f"- {c}" for c in checks)
    context += "\n\nSummarize the results for the user. Be encouraging if things look good."

    agent.generate_no_input(context)
    print()

    critical_fails = sum(1 for c in checks if c.startswith("FAIL"))
    return critical_fails == 0


def run_handoff(agent: OllamaAgent, hw: HardwareInfo, experience: str) -> None:
    """Step 6: Handoff to Claude Code."""
    _banner("Setup Complete!")
    agent.set_system(build_prompt(hw, "handoff", experience))
    agent.generate_no_input(
        "Everything is set up. Give the user a brief, warm send-off. "
        "Tell them to run `cd ~/ && claude` to start. Keep it short."
    )
    print()
    print(f"  {GREEN}{BOLD}Ready to go! Run:{NC}")
    print(f"  {BOLD}  cd ~/  &&  claude{NC}")
    print()


# ── Main flow ───────────────────────────────────────────────

def run_onboarding(model: str = "gemma3:4b") -> None:
    """Run the full 6-step onboarding flow."""
    agent = OllamaAgent(model=model)
    hw = detect_hardware()
    experience = "intermediate"  # default until detected

    # Step 1: Welcome
    run_welcome(agent, hw)
    agent.clear_history()

    # Step 2: Experience
    experience = run_experience(agent, hw)
    agent.clear_history()

    # Step 3: Auth
    run_auth_claude(agent, hw, experience)
    agent.clear_history()

    # Step 4: MCP Config
    run_config_mcp(agent, hw, experience)
    agent.clear_history()

    # Step 5: Verify
    all_good = run_verify(agent, hw, experience)
    agent.clear_history()

    # Step 6: Handoff
    if all_good:
        run_handoff(agent, hw, experience)
    else:
        print(f"  {YELLOW}Some checks failed. You can still use Claude Code,")
        print(f"  but you may want to fix the issues above first.{NC}")
        print()
        run_handoff(agent, hw, experience)
