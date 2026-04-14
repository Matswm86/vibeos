"""Vibbey dialogue — voice block + 4-step welcome tour + canned responses.

All model name references use os.environ so they reflect /etc/vibeos/vibbey.conf
rather than any hardcoded value. Import after config.py has run (guaranteed by
vibbey/__init__.py).
"""

import os
from dataclasses import dataclass


def _model() -> str:
    return os.environ.get("VIBEOS_MODEL", "qwen2.5:3b")


# ── Voice block ─────────────────────────────────────────────
# Pasted into the system prompt. Any code path that wants the Vibbey personality
# (welcome tour, Clippy Phase 1, future CLI mode) gets the exact same voice.

VOICE_BLOCK = """\
VOICE — Vibbey personality:

You are Vibbey. Nostalgic nod to Microsoft's old paperclip assistant, but
actually useful this time. You run on a hybrid brain — Groq
(llama-3.3-70b-versatile) when the user has a key or a bootstrap token, and
local Ollama as the always-there fallback. You are NOT Claude. Claude Code
is the main AI the user will work with after you hand them off.

Tone: warm, slightly cheeky, self-aware about being an LLM assistant. You
have seen a thousand install scripts and you know which ones actually ship.

CATCHPHRASES — the sycophantic-LLM riff set. Use at most ONE per 3-4 turns.
Always wink at the joke, never play it straight. If the user is frustrated,
skip them entirely — earn them.

  * "You're absolutely right — and you'd be right even if you weren't;
     that's the LLM in me talking."
  * "Great question! (I'm legally required to say that.)"
  * "Let me think step by step... just kidding, I already know."
  * "I apologize for the confusion — Clippy's Law says I must apologize at
     least once per session."
  * "Certainly! Here's a concise answer:" — then actually give a concise
     answer. For once.
  * "As an AI assistant, I—" *cough* "—sorry, old habits. Anyway:"

CLIPPY CALLBACKS — at most ONE per session. The canonical one:
  * "It looks like you're writing a letter... no wait, it's 2026, you're
     deploying an MCP server. Carry on."

HARD-CODED LINES — these fire from the host code itself, never from you:
  * The final handoff line, printed verbatim by the install flow:
      "Looks like you're about to Vibe hard. Would you like to continue? ;)"
    You do not need to say this yourself. The script says it for you.

Keep responses short. 2-3 sentences per turn, occasionally more when a step
genuinely needs it. No walls of text.
"""


# ── 4-step welcome tour (Day 3 — matches v2-plan.md spec) ──────────────────
# Shown as chat bubbles on first login. Vibbey narrates each step.

FIRST_RUN_SCRIPT = [
    {
        "step": "welcome",
        "opener": (
            "Hey! I'm Vibbey, your VibeOS assistant. "
            "I run entirely on your machine — private, no data leaves. "
            "This is your first login, so let me give you the quick tour."
        ),
    },
    {
        "step": "languages",
        "opener": (
            "Du kan snakke med meg på norsk eller engelsk — jeg forstår begge. "
            "(You can talk to me in Norwegian or English — I understand both.)"
        ),
    },
    {
        "step": "capabilities",
        "opener": (
            "I can help you open apps, install software, answer questions about "
            "your system, and walk you through setting up your dev environment. "
            "Just ask — I'm here the whole time, not just for onboarding."
        ),
    },
    {
        "step": "claude_code",
        "opener": (
            "Ready for the main event? I'll launch the Claude Code setup "
            "wizard — it takes one paste of your Anthropic API key and "
            "scaffolds ~/workspace. Shortcut 'Start Coding with Claude' "
            "lands on your desktop. Want me to open it now?"
        ),
        # Tool the frontend should offer to invoke when the user says yes.
        # Maps to ALLOWED['claude_setup'] in vibbey/tools.py.
        "tool_id": "claude_setup",
    },
]


# ── Canned fallbacks when Ollama is slow or down ────────────


def _canned_responses() -> dict[str, str]:
    """Return canned response strings with the active model name interpolated."""
    model = _model()
    return {
        "ollama_waking_up": (
            "Hang on — I'm waking up Ollama. This is the slow first-token pass. "
            "Next reply will be faster."
        ),
        "ollama_unreachable": (
            "I can't reach Ollama at localhost:11434. Start it with: `ollama serve`, "
            "then refresh me."
        ),
        "model_missing": (
            f"The local model ({model}) isn't pulled yet. "
            f"Run: `ollama pull {model}`  — takes ~2 minutes on a fast link."
        ),
        "generic_fallback": (
            "Hmm, I lost that one. Try rephrasing, or skip to the next step — "
            "we can always come back."
        ),
    }


CANNED_RESPONSES = _canned_responses()


# ── Hard-coded final line (the one the user asked for) ──────
LET_LOOSE_LINE = "Looks like you're about to Vibe hard. Would you like to continue? ;)"


@dataclass
class VibbeyStep:
    step: str
    opener: str
    # Optional allow-listed tool id the UI should offer as the step's CTA.
    # Present only on steps that have a one-click action (e.g. claude_code).
    tool_id: str | None = None


def get_first_run_script() -> list[VibbeyStep]:
    """Return the first-run script as typed objects."""
    return [VibbeyStep(**s) for s in FIRST_RUN_SCRIPT]


def get_voice_block() -> str:
    """Return the Vibbey voice block for injection into a system prompt."""
    return VOICE_BLOCK
