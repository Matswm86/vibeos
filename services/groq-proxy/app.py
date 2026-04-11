"""VibeOS bootstrap Groq proxy.

Stdlib-only HTTP service. Hands out free 300-message tokens to fresh
VibeOS installs so Vibbey (the 3D assistant) has a smart backend before
the user has signed up for their own Groq key.

Endpoints
---------
GET  /health                  → {"status": "ok", "tokens_issued": N, ...}
POST /bootstrap               → issues a fresh token; body optional JSON with {"label": "..."}
POST /v1/chat/completions     → OpenAI-compat; requires Authorization: Bearer <bootstrap-token>

Config (env)
------------
GROQ_API_KEY        required  — workspace-owned Groq key (never leaves VPS)
GROQ_MODEL          default   llama-3.3-70b-versatile
PORT                default   8200
BOOTSTRAP_QUOTA     default   300
QUOTA_DB            default   ~/services/groq-proxy/quota.db

Runs as a systemd user unit. No external deps (stdlib + sqlite3).
"""

from __future__ import annotations

import json
import logging
import os
import secrets
import sqlite3
import sys
import threading
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "").strip()
GROQ_MODEL_DEFAULT = os.environ.get("GROQ_MODEL", "llama-3.3-70b-versatile").strip()
PORT = int(os.environ.get("PORT", "8200"))
BOOTSTRAP_QUOTA = int(os.environ.get("BOOTSTRAP_QUOTA", "300"))
QUOTA_DB = Path(os.environ.get("QUOTA_DB", str(Path.home() / "services/groq-proxy/quota.db")))

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_TIMEOUT_S = 60
USER_AGENT = "VibeOS-BootstrapProxy/0.1 (+https://groq.mwmai.no)"

# Sensible request-size cap: Groq's own limits are generous but we do not
# want to forward unbounded payloads.
MAX_REQUEST_BYTES = 256 * 1024  # 256 KB — plenty for chat messages

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("groq-proxy")

# ---------------------------------------------------------------------------
# SQLite quota store
# ---------------------------------------------------------------------------

_db_lock = threading.Lock()


def _db_connect() -> sqlite3.Connection:
    QUOTA_DB.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(QUOTA_DB, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def _init_schema() -> None:
    with _db_lock, _db_connect() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS tokens (
                token       TEXT PRIMARY KEY,
                used_count  INTEGER NOT NULL DEFAULT 0,
                quota       INTEGER NOT NULL,
                first_seen  TEXT NOT NULL,
                last_used   TEXT,
                label       TEXT
            )
            """
        )
        conn.commit()


def issue_token(label: str | None = None) -> dict[str, object]:
    token = secrets.token_urlsafe(32)
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with _db_lock, _db_connect() as conn:
        conn.execute(
            "INSERT INTO tokens (token, used_count, quota, first_seen, label) VALUES (?, 0, ?, ?, ?)",
            (token, BOOTSTRAP_QUOTA, now, label),
        )
        conn.commit()
    return {"token": token, "quota": BOOTSTRAP_QUOTA, "used": 0}


def consume_token(token: str) -> tuple[bool, dict[str, object]]:
    """Atomically validate + increment a token.

    Returns ``(ok, info)``. ``ok`` is False if the token doesn't exist or
    is already exhausted. ``info`` contains quota state for the response
    header or error detail.
    """
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with _db_lock, _db_connect() as conn:
        row = conn.execute(
            "SELECT used_count, quota FROM tokens WHERE token = ?",
            (token,),
        ).fetchone()
        if row is None:
            return False, {"error": "invalid_token"}
        used = int(row["used_count"])
        quota = int(row["quota"])
        if used >= quota:
            return False, {
                "error": "quota_exhausted",
                "used": used,
                "quota": quota,
            }
        conn.execute(
            "UPDATE tokens SET used_count = used_count + 1, last_used = ? WHERE token = ?",
            (now, token),
        )
        conn.commit()
        return True, {"used": used + 1, "quota": quota, "remaining": quota - used - 1}


def health_snapshot() -> dict[str, object]:
    with _db_lock, _db_connect() as conn:
        row = conn.execute(
            "SELECT COUNT(*) AS n, COALESCE(SUM(used_count), 0) AS used FROM tokens"
        ).fetchone()
    return {
        "status": "ok",
        "tokens_issued": int(row["n"]),
        "total_calls": int(row["used"]),
        "quota_per_token": BOOTSTRAP_QUOTA,
        "groq_model": GROQ_MODEL_DEFAULT,
    }


# ---------------------------------------------------------------------------
# Groq forwarder
# ---------------------------------------------------------------------------


def call_groq(body: dict[str, object]) -> tuple[int, bytes, str | None]:
    """Forward a chat-completions payload to Groq.

    Returns ``(status_code, body_bytes, content_type)``. Catches all
    network errors and surfaces them as a JSON error response so the
    client never sees a raw traceback.
    """
    payload = dict(body)
    payload.setdefault("model", GROQ_MODEL_DEFAULT)
    payload.setdefault("stream", False)

    req = urllib.request.Request(
        GROQ_URL,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {GROQ_API_KEY}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=GROQ_TIMEOUT_S) as resp:
            return resp.status, resp.read(), resp.headers.get("Content-Type", "application/json")
    except urllib.error.HTTPError as exc:
        detail = exc.read() if hasattr(exc, "read") else b""
        log.warning("Groq HTTP %s: %s", exc.code, detail[:200])
        return exc.code, detail or json.dumps({"error": f"groq_http_{exc.code}"}).encode(), "application/json"
    except urllib.error.URLError as exc:
        log.error("Groq unreachable: %s", exc)
        return 502, json.dumps({"error": "groq_unreachable", "detail": str(exc)}).encode(), "application/json"
    except OSError as exc:
        log.error("Groq OSError: %s", exc)
        return 502, json.dumps({"error": "groq_os_error", "detail": str(exc)}).encode(), "application/json"


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------


class ProxyHandler(BaseHTTPRequestHandler):
    server_version = "VibeOS-BootstrapProxy/0.1"
    sys_version = ""  # suppress default Python/X.Y.Z advert

    # Quieter access log — one line per request via the access.log format.
    def log_message(self, fmt: str, *args: object) -> None:
        log.info("%s - %s", self.address_string(), fmt % args)

    # --- helpers -----------------------------------------------------------

    def _send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_raw(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> bytes | None:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return b""
        if length > MAX_REQUEST_BYTES:
            self._send_json(413, {"error": "payload_too_large", "max_bytes": MAX_REQUEST_BYTES})
            return None
        return self.rfile.read(length)

    def _parse_json(self, raw: bytes) -> dict[str, object] | None:
        if not raw:
            return {}
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid_json"})
            return None
        if not isinstance(parsed, dict):
            self._send_json(400, {"error": "expected_json_object"})
            return None
        return parsed

    def _extract_bearer(self) -> str | None:
        auth = self.headers.get("Authorization") or ""
        if not auth.lower().startswith("bearer "):
            return None
        token = auth[7:].strip()
        return token or None

    # --- routing -----------------------------------------------------------

    def do_GET(self) -> None:  # noqa: N802  — stdlib naming
        if self.path == "/health":
            self._send_json(200, health_snapshot())
            return
        self._send_json(404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path == "/bootstrap":
            self._handle_bootstrap()
            return
        if self.path == "/v1/chat/completions":
            self._handle_chat()
            return
        self._send_json(404, {"error": "not_found"})

    # --- handlers ----------------------------------------------------------

    def _handle_bootstrap(self) -> None:
        raw = self._read_body()
        if raw is None:
            return
        parsed = self._parse_json(raw) if raw else {}
        if parsed is None:
            return
        label = None
        if isinstance(parsed, dict):
            label_val = parsed.get("label")
            if isinstance(label_val, str) and 0 < len(label_val) <= 64:
                label = label_val
        result = issue_token(label=label)
        log.info("bootstrap issued: quota=%s label=%s", result["quota"], label)
        self._send_json(200, result)

    def _handle_chat(self) -> None:
        if not GROQ_API_KEY:
            self._send_json(503, {"error": "proxy_not_configured", "detail": "GROQ_API_KEY missing on server"})
            return

        token = self._extract_bearer()
        if not token:
            self._send_json(401, {"error": "missing_bearer_token"})
            return

        raw = self._read_body()
        if raw is None:
            return
        parsed = self._parse_json(raw)
        if parsed is None:
            return
        if not parsed.get("messages"):
            self._send_json(400, {"error": "missing_messages"})
            return

        ok, info = consume_token(token)
        if not ok:
            status = 401 if info.get("error") == "invalid_token" else 402
            self._send_json(status, info)
            return

        status, body, content_type = call_groq(parsed)
        # Surface quota headers so clients can warn the user as they approach zero
        self.send_response(status)
        self.send_header("Content-Type", content_type or "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Bootstrap-Remaining", str(info.get("remaining", "?")))
        self.send_header("X-Bootstrap-Quota", str(info.get("quota", BOOTSTRAP_QUOTA)))
        self.end_headers()
        self.wfile.write(body)


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------


def main() -> None:
    _init_schema()
    if not GROQ_API_KEY:
        log.warning("GROQ_API_KEY missing — /v1/chat/completions will return 503. /bootstrap still works.")
    else:
        log.info("Groq key loaded (%d chars). Model default: %s", len(GROQ_API_KEY), GROQ_MODEL_DEFAULT)
    log.info("Quota DB: %s", QUOTA_DB)
    log.info("Bootstrap quota per token: %d", BOOTSTRAP_QUOTA)
    log.info("Listening on 127.0.0.1:%d", PORT)

    server = ThreadingHTTPServer(("127.0.0.1", PORT), ProxyHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("shutting down")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
