"""Local HTTP server for Vibbey — static files + chat + tool-use + knowledge.

ThreadingHTTPServer so chat POSTs don't block static asset delivery. Picks a
free port from 8765-8770, falls back to an OS-assigned port.

Routes:
  GET  /                → static/index.html
  GET  /*.{html,js,css} → static/*
  GET  /clippy.glb      → static/clippy.glb (shipped with the package)
  GET  /api/config      → active model + tier (frontend reads on load)
  GET  /api/models      → proxies Ollama /api/tags so frontend can list models
  GET  /api/tier        → current chat backend tier + tool list
  GET  /api/knowledge   → full knowledge pack (debug)
  POST /api/chat        → Groq (BYO key > bootstrap) with Ollama fallback
  POST /api/run         → executes one allowlisted tool, returns stdout/exit

Kept stdlib-only so it runs on a fresh VibeOS install without pip.
Model defaults come from os.environ (populated by config.py from
/etc/vibeos/vibbey.conf).
"""

import json
import os
import socket
import urllib.error
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import groq_proxy
from . import memory as vibbey_memory
from . import tools as vibbey_tools
from .knowledge import load_knowledge_pack

VIBBEY_DIR = Path(__file__).resolve().parent
STATIC_DIR = VIBBEY_DIR / "static"
GLB_PATH = STATIC_DIR / "clippy.glb"
OLLAMA_TAGS_URL = "http://localhost:11434/api/tags"

PORT_CANDIDATES = [8765, 8766, 8767, 8768, 8769, 8770]


def pick_free_port() -> int:
    """Return the first free port from PORT_CANDIDATES, else an OS-assigned one."""
    for port in PORT_CANDIDATES:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class VibbeyHandler(SimpleHTTPRequestHandler):
    """Serves vibbey/static/ + special-cases /clippy.glb + /api/* routes."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        if self.path == "/clippy.glb":
            self._serve_glb()
            return
        if self.path == "/api/config":
            self._serve_config()
            return
        if self.path == "/api/models":
            self._proxy_ollama_tags()
            return
        if self.path == "/api/tier":
            self._serve_tier_info()
            return
        if self.path == "/api/knowledge":
            self._serve_knowledge()
            return
        super().do_GET()

    def do_POST(self):
        if self.path == "/api/chat":
            self._handle_chat()
            return
        if self.path == "/api/run":
            self._handle_run_tool()
            return
        self.send_error(404, "Not Found")

    def _send_json(self, code: int, body: bytes) -> None:
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, code: int, kind: str, detail: str) -> None:
        body = json.dumps({"error": kind, "detail": detail}).encode()
        self._send_json(code, body)

    def _serve_glb(self) -> None:
        if not GLB_PATH.exists():
            self.send_error(404, "clippy.glb missing")
            return
        data = GLB_PATH.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "model/gltf-binary")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def _serve_config(self) -> None:
        """Return active config to the frontend (model name, tier, version)."""
        body = json.dumps({
            "model": os.environ.get("VIBEOS_MODEL", "qwen2.5:3b"),
            "groq_model": os.environ.get("VIBEOS_GROQ_MODEL", "llama-3.3-70b-versatile"),
            "tier": groq_proxy.get_active_tier(),
        }).encode()
        self._send_json(200, body)

    def _handle_chat(self) -> None:
        """Route a chat payload through Groq with Ollama fallback.

        Accepts ``{messages: [...], model: "..."}``. The ``model`` field is
        treated as the Ollama model override; if absent, the server reads
        VIBEOS_MODEL from env (set from /etc/vibeos/vibbey.conf).

        Response format: Ollama-style ``{message: {role, content}}``
        plus extra fields ``tier`` and ``backend``.
        """
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            payload = json.loads(raw)
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_error(400, f"Bad JSON: {exc}")
            return

        incoming = payload.get("messages") or []
        # Honour explicit model override from frontend; fall back to config
        ollama_model = payload.get("model") or os.environ.get("VIBEOS_MODEL", "qwen2.5:3b")

        augmentation = self._build_system_augmentation()
        augmented: list[dict[str, str]] = []
        sys_injected = False
        for msg in incoming:
            if not sys_injected and msg.get("role") == "system":
                augmented.append({
                    "role": "system",
                    "content": f"{msg.get('content', '')}\n\n{augmentation}",
                })
                sys_injected = True
            else:
                augmented.append(msg)
        if not sys_injected:
            augmented.insert(0, {"role": "system", "content": augmentation})

        history = vibbey_memory.recent_history(n=6)
        if history:
            insert_at = 0
            while insert_at < len(augmented) and augmented[insert_at].get("role") == "system":
                insert_at += 1
            augmented[insert_at:insert_at] = history

        result = groq_proxy.chat(
            messages=augmented,
            ollama_model=ollama_model,
        )

        if "error" not in result:
            last_user = next(
                (m["content"] for m in reversed(incoming) if m.get("role") == "user"),
                None,
            )
            reply_content = (result.get("message") or {}).get("content", "")
            if last_user and reply_content:
                try:
                    vibbey_memory.append_exchange(last_user, reply_content)
                except OSError:
                    pass
            self._send_json(200, json.dumps(result).encode())
        else:
            self._send_error_json(
                502,
                result.get("error", "chat_failed"),
                result.get("detail", "unknown"),
            )

    def _build_system_augmentation(self) -> str:
        """Compose the knowledge-pack + memory-summary block for the prompt."""
        knowledge = load_knowledge_pack()
        mem_summary = vibbey_memory.summarize_for_prompt()
        tier = groq_proxy.get_active_tier()
        active_model = os.environ.get("VIBEOS_MODEL", "qwen2.5:3b")
        groq_model = os.environ.get("VIBEOS_GROQ_MODEL", "llama-3.3-70b-versatile")
        tier_description = {
            "byo_key": (
                f"Groq cloud ({groq_model}) via the user's own API key. "
                "Fast + smart. Unlimited per their Groq account."
            ),
            "bootstrap": (
                f"Groq cloud ({groq_model}) via the VibeOS-hosted "
                "bootstrap proxy. Fast + smart. 300 free messages, after which Vibbey "
                "prompts the user to get their own Groq key."
            ),
            "ollama": (
                f"Local Ollama on this machine ({active_model}). "
                "Private, offline, but slower and less capable than Groq. "
                "No cost, no internet needed."
            ),
        }.get(tier, tier)

        tool_lines: list[str] = []
        for t in vibbey_tools.list_tools():
            arg_marker = " <arg>" if t["accepts_arg"] else ""
            tool_lines.append(f"- `{t['id']}{arg_marker}` — {t['description']}")
        tool_list = "\n".join(tool_lines)

        return (
            f"# CURRENT BACKEND\n"
            f"You are currently running on: **{tier_description}**\n"
            f"When the user asks what backend you're using, say so plainly.\n\n"
            f"# WHAT VIBBEY KNOWS (static knowledge pack)\n\n{knowledge}\n\n"
            f"# PERSISTENT MEMORY SUMMARY\n{mem_summary}\n\n"
            "# TOOL USE RULES\n"
            "You can run system commands by asking the user for confirmation first. "
            "Format: respond with a short explanation + `[[RUN: tool_id]]` or "
            "`[[RUN: tool_id arg]]` on its own line. The user confirms, frontend "
            "calls /api/run, result comes back as a user message prefixed with "
            "`[[RESULT: ...]]`. Then you interpret the result for the user.\n\n"
            "**Use EXACTLY these tool IDs** (with underscores, not spaces):\n"
            f"{tool_list}\n\n"
            "**IMPORTANT**: Never invent a tool ID. If the user asks for something "
            "not in the list, say you can't run it and suggest how they can do it "
            "themselves in a terminal."
        )

    def _handle_run_tool(self) -> None:
        """Execute one allowlisted tool and return the result."""
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            payload = json.loads(raw)
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_error(400, f"Bad JSON: {exc}")
            return

        tool_id = payload.get("tool_id", "")
        arg = payload.get("arg")
        if not tool_id:
            self._send_error_json(400, "missing_tool_id", "tool_id is required")
            return

        result = vibbey_tools.run_tool(tool_id, arg)
        self._send_json(200, json.dumps(result).encode())

    def _serve_tier_info(self) -> None:
        """Report current chat backend tier + tool list for frontend UI."""
        body = json.dumps({
            "tier": groq_proxy.get_active_tier(),
            "default_groq_model": os.environ.get("VIBEOS_GROQ_MODEL", "llama-3.3-70b-versatile"),
            "tools": vibbey_tools.list_tools(),
        }).encode()
        self._send_json(200, body)

    def _serve_knowledge(self) -> None:
        """Return the full knowledge pack — useful for debugging."""
        body = json.dumps({
            "knowledge": load_knowledge_pack(),
            "memory_summary": vibbey_memory.summarize_for_prompt(),
        }).encode()
        self._send_json(200, body)

    def _proxy_ollama_tags(self) -> None:
        """Expose Ollama's /api/tags so the frontend can list models."""
        try:
            req = urllib.request.Request(OLLAMA_TAGS_URL)
            with urllib.request.urlopen(req, timeout=10) as resp:
                body = resp.read()
            self._send_json(200, body)
        except urllib.error.HTTPError as exc:
            detail_bytes = exc.read() if hasattr(exc, "read") else b""
            self._send_error_json(
                exc.code, "ollama_error", detail_bytes.decode("utf-8", errors="replace")
            )
        except urllib.error.URLError as exc:
            self._send_error_json(502, "ollama_unreachable", str(exc))


def start_server(port: int | None = None) -> tuple[ThreadingHTTPServer, int]:
    """Create the server bound to localhost, return (server, port).

    Fires off a non-blocking install-state snapshot before returning so
    Vibbey's memory has a cached read of claude/gh/ollama/docker/os on
    the very first chat turn.
    """
    chosen = port or pick_free_port()
    server = ThreadingHTTPServer(("127.0.0.1", chosen), VibbeyHandler)

    import threading

    def _snapshot_worker() -> None:
        try:
            from . import install_snapshot
            install_snapshot.capture_snapshot()
        except Exception:  # noqa: BLE001
            pass

    threading.Thread(target=_snapshot_worker, daemon=True).start()
    return server, chosen
