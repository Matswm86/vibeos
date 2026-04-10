"""Local HTTP server for Vibbey — serves static/ + proxies Ollama chat.

ThreadingHTTPServer so chat POSTs don't block static asset delivery. Picks a
free port from 8765-8770, falls back to an OS-assigned port.

Routes:
  GET  /                → static/index.html
  GET  /*.{html,js,css} → static/*
  GET  /clippy.glb      → ../clippy.glb (one level up from this package)
  POST /api/chat        → forwards to http://localhost:11434/api/chat

Kept stdlib-only so it runs on a fresh VibeOS install without pip.
"""

import json
import socket
import urllib.error
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CLIPPY_DIR = Path(__file__).resolve().parent
STATIC_DIR = CLIPPY_DIR / "static"
GLB_PATH = CLIPPY_DIR.parent / "clippy.glb"
OLLAMA_CHAT_URL = "http://localhost:11434/api/chat"
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
        super().do_GET()

    def do_POST(self):
        if self.path == "/api/chat":
            self._proxy_ollama_chat()
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

    def _proxy_ollama_chat(self) -> None:
        """Forward a JSON chat payload to Ollama, return the single response.

        MVP is non-streaming. Streaming (newline-delimited JSON from Ollama)
        is a v0.5 upgrade — see plans/vibeos-stage4.md Phase B risks.

        Error handling splits HTTPError (Ollama returned an error like 404
        "model not found") from URLError (can't reach Ollama at all) so the
        UI can tell the user what actually went wrong.
        """
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            payload = json.loads(raw)
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_error(400, f"Bad JSON: {exc}")
            return

        # Force non-streaming for the MVP proxy.
        payload["stream"] = False

        try:
            req = urllib.request.Request(
                OLLAMA_CHAT_URL,
                data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=120) as resp:
                body = resp.read()
            self._send_json(200, body)
        except urllib.error.HTTPError as exc:
            # Ollama replied with an error (most commonly: model not found)
            detail_bytes = exc.read() if hasattr(exc, "read") else b""
            try:
                detail = json.loads(detail_bytes).get("error", detail_bytes.decode())
            except (ValueError, json.JSONDecodeError):
                detail = detail_bytes.decode("utf-8", errors="replace") or str(exc)
            self._send_error_json(exc.code, "ollama_error", detail)
        except urllib.error.URLError as exc:
            self._send_error_json(502, "ollama_unreachable", str(exc))

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
    """
    chosen = port or pick_free_port()
    server = ThreadingHTTPServer(("127.0.0.1", chosen), VibbeyHandler)
    return server, chosen
