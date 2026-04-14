"""Vibbey persistent memory — JSON file under VIBEOS_STATE_DIR.

Default path: ``~/.vibeos/vibbey-memory.json`` (user mode).
When VIBEOS_STATE_DIR is set (e.g. by vibbey.service to /var/lib/vibbey),
memory lives there instead.

Stores across sessions:
  * ``user`` — profile the user has shared (name, experience_level, tone)
  * ``facts`` — key/value things Vibbey has learned
  * ``history`` — last N chat exchanges (user message + Vibbey reply)
  * ``install_state`` — cached install detection (claude_version, ollama_models)
  * ``meta`` — schema version, created_at, updated_at

The JSON file is mode 0600 — user-only readable. No PII leaves this file; Groq
chats see only the current exchange + recent history, never the full profile.

stdlib-only so it runs on a fresh VibeOS install without pip.
"""

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_STATE_DIR = Path(os.environ.get("VIBEOS_STATE_DIR", str(Path.home() / ".vibeos")))
VIBEOS_DIR = _STATE_DIR
MEMORY_PATH = VIBEOS_DIR / "vibbey-memory.json"

SCHEMA_VERSION = 1
HISTORY_MAX_LEN = 50


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _empty_memory() -> dict[str, Any]:
    now = _now_iso()
    return {
        "meta": {
            "schema": SCHEMA_VERSION,
            "created_at": now,
            "updated_at": now,
        },
        "user": {
            "name": None,
            "experience_level": None,  # "newbie" | "intermediate" | "advanced"
            "tone": None,              # "warm" | "terse" | "playful"
        },
        "facts": {},
        "history": [],
        "install_state": {
            "claude_version": None,
            "ollama_models": [],
            "gh_authed": None,
            "docker_running": None,
            "os_release": None,
            "last_checked": None,
        },
    }


def load() -> dict[str, Any]:
    """Load memory, creating an empty file if missing or corrupt."""
    VIBEOS_DIR.mkdir(parents=True, exist_ok=True)
    if not MEMORY_PATH.exists():
        mem = _empty_memory()
        save(mem)
        return mem
    try:
        data = json.loads(MEMORY_PATH.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or "meta" not in data:
            raise ValueError("memory file missing required keys")
        template = _empty_memory()
        for key, default in template.items():
            if key not in data:
                data[key] = default
        return data
    except (json.JSONDecodeError, ValueError) as e:
        backup = MEMORY_PATH.with_suffix(f".broken.{int(datetime.now().timestamp())}.json")
        MEMORY_PATH.rename(backup)
        mem = _empty_memory()
        mem["meta"]["recovered_from"] = str(backup)
        mem["meta"]["recovery_reason"] = str(e)
        save(mem)
        return mem


def save(mem: dict[str, Any]) -> None:
    """Write memory atomically with mode 0600."""
    VIBEOS_DIR.mkdir(parents=True, exist_ok=True)
    mem["meta"]["updated_at"] = _now_iso()
    tmp = MEMORY_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(mem, indent=2, ensure_ascii=False), encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(MEMORY_PATH)


def append_exchange(user_msg: str, vibbey_reply: str) -> None:
    """Add one user+reply pair to the rolling history, capped at HISTORY_MAX_LEN."""
    mem = load()
    mem["history"].append({
        "at": _now_iso(),
        "user": user_msg,
        "vibbey": vibbey_reply,
    })
    if len(mem["history"]) > HISTORY_MAX_LEN:
        mem["history"] = mem["history"][-HISTORY_MAX_LEN:]
    save(mem)


def recent_history(n: int = 10) -> list[dict[str, str]]:
    """Return the last n exchanges in chat-message format for the model."""
    mem = load()
    exchanges = mem["history"][-n:] if n > 0 else []
    out: list[dict[str, str]] = []
    for e in exchanges:
        out.append({"role": "user", "content": e["user"]})
        out.append({"role": "assistant", "content": e["vibbey"]})
    return out


def set_user_profile(**kwargs: Any) -> None:
    """Update user profile fields. Unknown keys are silently ignored."""
    mem = load()
    allowed = set(mem["user"].keys())
    for k, v in kwargs.items():
        if k in allowed:
            mem["user"][k] = v
    save(mem)


def set_fact(key: str, value: Any) -> None:
    """Store an arbitrary learned fact."""
    mem = load()
    mem["facts"][key] = value
    save(mem)


def update_install_state(**kwargs: Any) -> None:
    """Patch install_state from a snapshot taken via tool-use commands."""
    mem = load()
    for k, v in kwargs.items():
        if k in mem["install_state"]:
            mem["install_state"][k] = v
    mem["install_state"]["last_checked"] = _now_iso()
    save(mem)


def summarize_for_prompt() -> str:
    """Return a short human-readable summary of memory for the system prompt."""
    mem = load()
    lines: list[str] = []

    user = mem["user"]
    if any(user.values()):
        u_bits = []
        if user.get("name"):
            u_bits.append(f"name={user['name']}")
        if user.get("experience_level"):
            u_bits.append(f"experience={user['experience_level']}")
        if user.get("tone"):
            u_bits.append(f"tone={user['tone']}")
        lines.append(f"USER: {', '.join(u_bits)}")

    install = mem["install_state"]
    if install.get("last_checked"):
        i_bits = []
        if install.get("os_release"):
            i_bits.append(f"os={install['os_release']}")
        if install.get("claude_version"):
            i_bits.append(f"claude={install['claude_version']}")
        if install.get("ollama_models"):
            i_bits.append(f"ollama_models={','.join(install['ollama_models'][:5])}")
        elif install.get("ollama_models") == []:
            i_bits.append("ollama_models=(none pulled)")
        if install.get("gh_authed") is not None:
            i_bits.append(f"gh_authed={install['gh_authed']}")
        if install.get("docker_running") is not None:
            i_bits.append(f"docker_running={install['docker_running']}")
        if i_bits:
            lines.append(
                "INSTALL STATE (ground truth — trust this over any assumptions): "
                + ", ".join(i_bits)
            )

    if mem["facts"]:
        fact_summary = ", ".join(f"{k}={v}" for k, v in list(mem["facts"].items())[:6])
        lines.append(f"FACTS: {fact_summary}")

    if not lines:
        return "(first session — no memory yet)"
    return "\n".join(lines)
