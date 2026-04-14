"""Static knowledge pack loaded into Vibbey's system prompt at startup.

Loading strategy: read all .md files in this directory at import time, return
a single concatenated string via ``load_knowledge_pack()``. The server injects
this into the chat system prompt so Vibbey knows about herself, VibeOS,
common commands, and troubleshooting without any retrieval layer.

Total size budget: ~8 KB of markdown fits comfortably in gemma3:4b's and
llama-3.1-70b's context windows with room to spare for conversation history.
"""

from pathlib import Path

KNOWLEDGE_DIR = Path(__file__).resolve().parent

# Order matters — Vibbey reads top-down, so about.md (identity) goes first,
# then commands.md (what to teach), then troubleshooting.md (fault recovery).
_LOAD_ORDER = ("about.md", "commands.md", "troubleshooting.md")


def load_knowledge_pack() -> str:
    """Return the full knowledge pack as a single markdown-formatted string.

    Loaded fresh on each call so `python3 -m clippy` picks up doc edits
    without a restart during development. In production the server caches
    the result at first request.
    """
    parts: list[str] = []
    for name in _LOAD_ORDER:
        path = KNOWLEDGE_DIR / name
        if not path.exists():
            continue
        content = path.read_text(encoding="utf-8").strip()
        parts.append(f"# === {name} ===\n\n{content}")

    # Also include any extra .md files dropped in here that aren't in the
    # canonical order, so future additions don't require editing this file.
    extras = sorted(
        p for p in KNOWLEDGE_DIR.glob("*.md") if p.name not in _LOAD_ORDER
    )
    for path in extras:
        content = path.read_text(encoding="utf-8").strip()
        parts.append(f"# === {path.name} ===\n\n{content}")

    return "\n\n---\n\n".join(parts)


def knowledge_pack_size() -> int:
    """Byte count of the loaded knowledge pack — useful for budgeting."""
    return len(load_knowledge_pack().encode("utf-8"))
