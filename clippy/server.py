"""Local HTTP server for Vibbey — static files + chat + tool-use + knowledge.

ThreadingHTTPServer so chat POSTs don't block static asset delivery. Picks a
free port from 8765-8770, falls back to an OS-assigned port.

Routes:
  GET  /                → static/index.html
  GET  /*.{html,js,css} → static/*
  GET  /clippy.glb      → ../clippy.glb (one level up from this package)
  GET  /api/models      → proxies Ollama /api/tags so frontend can pick a model
  GET  /api/tier        → returns current chat backend tier + tool list
  GET  /api/knowledge   → returns the full knowledge pack (debug)
  POST /api/chat        → Groq (BYO key > bootstrap) with Ollama fallback
  POST /api/run         → executes one allowlisted tool, returns stdout/exit

Kept stdlib-only so it runs on a fresh VibeOS install without pip.
"""

import json
import socket
import urllib.error
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import groq_proxy
from . import memory as vibbey_memory
from . import tools as vibbey_tools
from .knowledge import load_knowledge_pack

CLIPPY_DIR = Path(__file__).resolve().parent
STATIC_DIR = CLIPPY_DIR / "static"
GLB_PATH = CLIPPY_DIR.parent / "clippy.glb"
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
    """Serves clippy/static/ + special-cases /clippy.glb + /api/chat proxy."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def log_message(self, fmt, *args):
        # Quiet the default noisy per-request logger; launcher prints its own banners.
        return

    def do_GET(self):
        if self.path == "/clippy.glb":
            self._serve_glb()
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

    def _handle_chat(self) -> None:
        """Route a chat payload through Groq (BYO > bootstrap) with Ollama fallback.

        Accepts a JSON body with ``{messages: [...], model: "..."}``. The
        ``model`` is treated as the **Ollama model** (kept for backward compat
        with the frontend's existing auto-detect). The Groq model is fixed
        to ``DEFAULT_GROQ_MODEL`` in groq_proxy.

        The system prompt is automatically augmented with the VibeOS knowledge
        pack + a memory summary so Vibbey is grounded without the frontend
        having to send them on every request.

        Response format: always Ollama-style ``{message: {role, content}}``
        plus extra fields ``tier`` and ``backend`` so the frontend can show
        which backend answered.
        """
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            payload = json.loads(raw)
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_error(400, f"Bad JSON: {exc}")
            return

        incoming = payload.get("messages") or []
        ollama_model = payload.get("model", "gemma3:4b")

        # Augment the system prompt with knowledge + memory summary. If the
        # frontend already sent a system message, we prepend the augmentation
        # to its content so personality stays in place.
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

        # Also prepend recent history for continuity across sessions
        history = vibbey_memory.recent_history(n=6)
        if history:
            # Find position right after any leading system messages
            insert_at = 0
            while insert_at < len(augmented) and augmented[insert_at].get("role") == "system":
                insert_at += 1
            augmented[insert_at:insert_at] = history

        result = groq_proxy.chat(
            messages=augmented,
            ollama_model=ollama_model,
        )

        # Persist this exchange in memory if we got a successful reply
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
                    pass  # don't fail the request over disk issues
            body = json.dumps(result).encode()
            self._send_json(200, body)
        else:
            # Map to the frontend's existing error shape
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
        tier_description = {
            "byo_key": (
                f"Groq cloud ({groq_proxy.DEFAULT_GROQ_MODEL}) via the user's own API key. "
                "Fast + smart. Unlimited per their Groq account."
            ),
            "bootstrap": (
                f"Groq cloud ({groq_proxy.DEFAULT_GROQ_MODEL}) via the VibeOS-hosted "
                "bootstrap proxy. Fast + smart. 300 free messages, after which Vibbey "
                "prompts the user to get their own Groq key."
            ),
            "ollama": (
                "Local Ollama on this machine. Private, offline, but slower and less "
                "capable than Groq. No cost, no internet needed."
            ),
        }.get(tier, tier)

        # Build the explicit tool list so the model uses exact tool IDs
        # (with underscores) instead of inventing command-line forms.
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
            "themselves in a terminal. The install-state summary above already "
            "has cached results for most of these — check it first before running "
            "a fresh tool."
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
        # Errors come back as dicts with an "error" key but still 200;
        # the frontend inspects the body regardless of status.
        body = json.dumps(result).encode()
        self._send_json(200, body)

    def _serve_tier_info(self) -> None:
        """Report current chat backend tier + tool list for frontend UI."""
        body = json.dumps({
            "tier": groq_proxy.get_active_tier(),
            "default_groq_model": groq_proxy.DEFAULT_GROQ_MODEL,
            "tools": vibbey_tools.list_tools(),
        }).encode()
        self._send_json(200, body)

    def _serve_knowledge(self) -> None:
        """Return the full knowledge pack — useful for debugging system-prompt content."""
        body = json.dumps({
            "knowledge": load_knowledge_pack(),
            "memory_summary": vibbey_memory.summarize_for_prompt(),
        }).encode()
        self._send_json(200, body)

    def _proxy_ollama_tags(self) -> None:
        """Expose Ollama's /api/tags so the frontend can pick a chat model."""
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

    Caller is responsible for running ``server.serve_forever()`` on its own
    thread and calling ``server.shutdown()`` when done.

    Before returning, fires off a non-blocking install-state snapshot so
    Vibbey's memory has a cached read of claude/gh/ollama/docker/os on the
    very first chat turn. Snapshot errors are swallowed — Vibbey just falls
    back to "I don't know yet, let me check" on relevant questions.
    """
    chosen = port or pick_free_port()
    server = ThreadingHTTPServer(("127.0.0.1", chosen), VibbeyHandler)

    # Run the install snapshot in a daemon thread so it doesn't block
    # the server coming up. Takes ~1-2 seconds on a warm system.
    import threading
    def _snapshot_worker() -> None:
        try:
            from . import install_snapshot
            install_snapshot.capture_snapshot()
        except Exception:  # noqa: BLE001 — never fail server start over a snapshot
            pass
    threading.Thread(target=_snapshot_worker, daemon=True).start()

    return server, chosen
