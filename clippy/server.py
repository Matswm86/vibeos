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
OLLAMA_URL = "http://localhost:11434/api/chat"

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
        super().do_GET()

    def do_POST(self):
        if self.path == "/api/chat":
            self._proxy_ollama_chat()
            return
        self.send_error(404, "Not Found")

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
                OLLAMA_URL,
                data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=120) as resp:
                body = resp.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except urllib.error.URLError as exc:
            msg = json.dumps(
                {"error": "ollama_unreachable", "detail": str(exc)}
            ).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)


def start_server(port: int | None = None) -> tuple[ThreadingHTTPServer, int]:
    """Create the server bound to localhost, return (server, port).

    Caller is responsible for running ``server.serve_forever()`` on its own
    thread and calling ``server.shutdown()`` when done.
    """
    chosen = port or pick_free_port()
    server = ThreadingHTTPServer(("127.0.0.1", chosen), VibbeyHandler)
    return server, chosen
