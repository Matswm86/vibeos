"""Groq + Ollama hybrid chat backend.

Routing:
  1. If ``~/.vibeos/groq.key`` exists → call Groq directly with user's own key
  2. Else if ``~/.vibeos/groq.token`` exists → call the VibeOS-hosted proxy
     at ``groq.mwmai.no`` with the bootstrap JWT (300 free messages)
  3. Else → fall back to local Ollama at ``localhost:11434``

Any HTTP error from Groq (rate limit, quota exceeded, network failure)
triggers a fall-through to the next lower tier, so a burned bootstrap token
seamlessly falls back to Ollama without the user having to do anything.

Privacy: when Vibbey calls Groq (cloud), the user sees a one-time consent
dialog. That state is tracked in ``~/.vibeos/vibbey-memory.json::facts``.

stdlib-only so it runs on a fresh VibeOS install without pip.
Model defaults are read from os.environ (populated by config.py at startup).
"""

import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

VIBEOS_DIR = Path.home() / ".vibeos"
GROQ_KEY_PATH = VIBEOS_DIR / "groq.key"
GROQ_TOKEN_PATH = VIBEOS_DIR / "groq.token"

GROQ_DIRECT_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_PROXY_URL = "https://groq.mwmai.no/v1/chat/completions"
OLLAMA_CHAT_URL = "http://localhost:11434/api/chat"

DEFAULT_GROQ_MODEL = "llama-3.3-70b-versatile"
REQUEST_TIMEOUT_S = 60

# Groq's API sits behind Cloudflare, which blocks the default
# ``Python-urllib`` User-Agent with error code 1010. Use a real UA string
# that identifies Vibbey explicitly so Groq support can trace us if needed.
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) VibeOS-Vibbey/2.0"


def _active_model() -> str:
    """Return the configured local model name from env (set by config.py)."""
    return os.environ.get("VIBEOS_MODEL", "qwen2.5:3b")


def _active_groq_model() -> str:
    return os.environ.get("VIBEOS_GROQ_MODEL", DEFAULT_GROQ_MODEL)


def _read_first_line(path: Path) -> str | None:
    if not path.exists():
        return None
    try:
        text = path.read_text(encoding="utf-8").strip()
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                if "=" in line and line.split("=", 1)[0].strip().lower().endswith("key"):
                    return line.split("=", 1)[1].strip().strip("\"'")
                return line
        return None
    except OSError:
        return None


def get_active_tier() -> str:
    """Return which tier will be used for the next chat.

    Values: ``byo_key`` | ``bootstrap`` | ``ollama``
    """
    if _read_first_line(GROQ_KEY_PATH):
        return "byo_key"
    if _read_first_line(GROQ_TOKEN_PATH):
        return "bootstrap"
    return "ollama"


def _normalize_groq_reply(data: dict[str, Any]) -> dict[str, Any]:
    """Convert an OpenAI-format Groq response into Ollama-format reply."""
    choices = data.get("choices") or []
    if not choices:
        return {"message": {"role": "assistant", "content": ""}}
    msg = choices[0].get("message") or {}
    return {
        "message": {
            "role": msg.get("role", "assistant"),
            "content": msg.get("content", ""),
        },
        "model": data.get("model"),
        "usage": data.get("usage"),
        "backend": "groq",
    }


def _call_groq_direct(messages: list[dict[str, str]], model: str, key: str) -> dict[str, Any] | None:
    """Call Groq with the user's own API key. Returns None on any failure."""
    payload = {
        "model": model or _active_groq_model(),
        "messages": messages,
        "stream": False,
    }
    req = urllib.request.Request(
        GROQ_DIRECT_URL,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_S) as resp:
            data = json.loads(resp.read())
        reply = _normalize_groq_reply(data)
        reply["tier"] = "byo_key"
        return reply
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError, OSError):
        return None


def _call_groq_proxy(messages: list[dict[str, str]], model: str, token: str) -> dict[str, Any] | None:
    """Call the VibeOS-hosted proxy with the bootstrap token."""
    payload = {
        "model": model or _active_groq_model(),
        "messages": messages,
        "stream": False,
    }
    req = urllib.request.Request(
        GROQ_PROXY_URL,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
            "X-Vibeos-Client": "vibbey",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_S) as resp:
            data = json.loads(resp.read())
        reply = _normalize_groq_reply(data)
        reply["tier"] = "bootstrap"
        return reply
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError, OSError):
        return None


def _call_ollama(messages: list[dict[str, str]], model: str) -> dict[str, Any] | tuple[str, str]:
    """Call local Ollama. Returns the raw Ollama dict on success, or a
    ``(error_kind, detail)`` tuple on failure so the server can surface it.
    """
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
    }
    req = urllib.request.Request(
        OLLAMA_CHAT_URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read())
        data["tier"] = "ollama"
        data["backend"] = "ollama"
        return data
    except urllib.error.HTTPError as exc:
        detail_bytes = exc.read() if hasattr(exc, "read") else b""
        try:
            detail = json.loads(detail_bytes).get("error", detail_bytes.decode())
        except (ValueError, json.JSONDecodeError):
            detail = detail_bytes.decode("utf-8", errors="replace") or str(exc)
        return ("ollama_error", detail)
    except urllib.error.URLError as exc:
        return ("ollama_unreachable", str(exc))


def chat(
    messages: list[dict[str, str]],
    groq_model: str | None = None,
    ollama_model: str | None = None,
) -> dict[str, Any]:
    """Try each tier in order, return the first success.

    Model defaults come from os.environ (VIBEOS_GROQ_MODEL / VIBEOS_MODEL),
    set by config.py from /etc/vibeos/vibbey.conf. Callers can override.

    On complete failure (no tier responds), returns
    ``{"error": "all_tiers_failed", "detail": "..."}``.
    """
    groq_model = groq_model or _active_groq_model()
    ollama_model = ollama_model or _active_model()
    attempted: list[str] = []

    # Tier 1: user's own Groq key
    key = _read_first_line(GROQ_KEY_PATH)
    if key:
        attempted.append("byo_key")
        reply = _call_groq_direct(messages, groq_model, key)
        if reply is not None:
            return reply

    # Tier 2: bootstrap token via hosted proxy
    token = _read_first_line(GROQ_TOKEN_PATH)
    if token:
        attempted.append("bootstrap")
        reply = _call_groq_proxy(messages, groq_model, token)
        if reply is not None:
            return reply

    # Tier 3: local Ollama
    attempted.append("ollama")
    ollama_result = _call_ollama(messages, ollama_model)
    if isinstance(ollama_result, dict):
        ollama_result["attempted_tiers"] = attempted
        return ollama_result

    err_kind, err_detail = ollama_result
    return {
        "error": err_kind,
        "detail": err_detail,
        "attempted_tiers": attempted,
    }
