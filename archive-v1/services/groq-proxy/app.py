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
import time
import urllib.error
import urllib.request
from collections import deque
from datetime import UTC, datetime
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

# Rate limiting (stdlib sliding-window, per-IP). Mirrors the proven pytor
# tutor limiter. Closes the open-relay hole: /bootstrap was unauthenticated
# and unlimited, so anyone could mint unlimited 300-message tokens and burn
# our Groq quota. GLOBAL_DAILY_CAP is a hard bill ceiling across all callers.
BOOTSTRAP_RATE_MAX = int(os.environ.get("BOOTSTRAP_RATE_MAX", "5"))  # tokens / IP
BOOTSTRAP_RATE_WINDOW = float(os.environ.get("BOOTSTRAP_RATE_WINDOW", "86400"))  # per 24h
CHAT_RATE_MAX = int(os.environ.get("CHAT_RATE_MAX", "20"))  # chat calls / IP
CHAT_RATE_WINDOW = float(os.environ.get("CHAT_RATE_WINDOW", "60"))  # per minute
GLOBAL_DAILY_CAP = int(os.environ.get("GLOBAL_DAILY_CAP", "5000"))  # 0 disables

# ---------------------------------------------------------------------------
# Landing page
# ---------------------------------------------------------------------------
# Rendered on GET /. Plain HTML with no inline CSS/JS/images so it works
# under the Caddy vhost CSP `default-src 'none'; frame-ancestors 'none'`.
# Default browser styles are sufficient for an API docs page.

LANDING_PAGE_HTML = b"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VibeOS Bootstrap Groq Proxy</title>
</head>
<body>
<h1>VibeOS Bootstrap Groq Proxy</h1>
<p>API-only service. No browser UI. Hands out free 300-message bootstrap
tokens to fresh VibeOS installs so <em>Vibbey</em> (the 3D AI assistant) has a
smart backend before the user has signed up for their own Groq key.</p>

<h2>Endpoints</h2>

<h3><code>GET /health</code></h3>
<p>Service status and call counters.</p>
<pre>curl https://groq.mwmai.no/health</pre>

<h3><code>POST /bootstrap</code></h3>
<p>Issue a fresh 300-message token. Optional <code>label</code> in the body.</p>
<pre>curl -X POST https://groq.mwmai.no/bootstrap \\
  -H "Content-Type: application/json" \\
  -d '{"label":"my-vibeos-laptop"}'</pre>

<h3><code>POST /v1/chat/completions</code></h3>
<p>OpenAI-compatible chat. Requires
<code>Authorization: Bearer &lt;bootstrap-token&gt;</code>. Response headers include
<code>X-Bootstrap-Remaining</code> and <code>X-Bootstrap-Quota</code> so clients can warn
the user as they approach zero.</p>
<pre>curl -X POST https://groq.mwmai.no/v1/chat/completions \\
  -H "Authorization: Bearer $TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{"messages":[{"role":"user","content":"hello"}]}'</pre>

<h2>Source</h2>
<p><a href="https://github.com/Matswm86/vibeos/tree/main/services/groq-proxy">github.com/Matswm86/vibeos/tree/main/services/groq-proxy</a></p>

<hr>
<p><small>Part of the <a href="https://github.com/Matswm86/vibeos">VibeOS</a>
project &mdash; free OSS Linux distro with a 3D AI assistant.</small></p>
</body>
</html>
"""

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("groq-proxy")

# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------
# Per-IP sliding window (in-memory, resets on restart — acceptable) plus a
# global per-day call cap. Counters are surfaced in /health so a tripped
# limit is observable, never silent.

_rate_buckets: dict[tuple[str, str], deque] = {}
_rate_lock = threading.Lock()
_rate_tripped = 0

_global_lock = threading.Lock()
_global_day = ""
_global_count = 0
_global_tripped = 0


def rate_limit_ok(client_ip: str, route: str, max_requests: int, window: float) -> tuple[bool, int]:
    """Sliding-window per-IP limiter. Returns ``(ok, retry_after_seconds)``.

    Localhost bypasses (internal health checks / same-host calls).
    """
    global _rate_tripped
    if client_ip in ("127.0.0.1", "::1", ""):
        return True, 0
    now = time.monotonic()
    key = (client_ip, route)
    with _rate_lock:
        bucket = _rate_buckets.get(key)
        if bucket is None:
            bucket = deque()
            _rate_buckets[key] = bucket
        while bucket and now - bucket[0] >= window:
            bucket.popleft()
        if len(bucket) >= max_requests:
            _rate_tripped += 1
            retry = int(window - (now - bucket[0])) + 1
            return False, max(retry, 1)
        bucket.append(now)
        return True, 0


def global_cap_ok() -> bool:
    """Hard daily call ceiling across all callers. ``GLOBAL_DAILY_CAP<=0`` disables."""
    global _global_day, _global_count, _global_tripped
    if GLOBAL_DAILY_CAP <= 0:
        return True
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    with _global_lock:
        if today != _global_day:
            _global_day = today
            _global_count = 0
        if _global_count >= GLOBAL_DAILY_CAP:
            _global_tripped += 1
            return False
        _global_count += 1
        return True


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
    now = datetime.now(UTC).isoformat(timespec="seconds")
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
    now = datetime.now(UTC).isoformat(timespec="seconds")
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
        "rate_limited_hits": _rate_tripped,
        "global_calls_today": _global_count,
        "global_daily_cap": GLOBAL_DAILY_CAP,
        "global_cap_hits": _global_tripped,
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
        return (
            exc.code,
            detail or json.dumps({"error": f"groq_http_{exc.code}"}).encode(),
            "application/json",
        )
    except urllib.error.URLError as exc:
        log.error("Groq unreachable: %s", exc)
        return (
            502,
            json.dumps({"error": "groq_unreachable", "detail": str(exc)}).encode(),
            "application/json",
        )
    except OSError as exc:
        log.error("Groq OSError: %s", exc)
        return (
            502,
            json.dumps({"error": "groq_os_error", "detail": str(exc)}).encode(),
            "application/json",
        )


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

    def _send_html(self, status: int, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "public, max-age=300")
        self.end_headers()
        self.wfile.write(body)

    def _send_429(self, retry_after: int, detail: str) -> None:
        body = json.dumps(
            {"error": "rate_limited", "detail": detail, "retry_after": retry_after}
        ).encode()
        self.send_response(429)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Retry-After", str(retry_after))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _client_ip(self) -> str:
        """Real client IP. Caddy fronts this on 127.0.0.1 and appends the
        true peer last in X-Forwarded-For, so the rightmost hop is the
        trustworthy value (a client-spoofed XFF entry sits to its left)."""
        xff = self.headers.get("X-Forwarded-For", "")
        if xff:
            parts = [p.strip() for p in xff.split(",") if p.strip()]
            if parts:
                return parts[-1]
        return self.client_address[0] if self.client_address else ""

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
        if self.path == "/":
            self._send_html(200, LANDING_PAGE_HTML)
            return
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
        ip = self._client_ip()
        ok, retry = rate_limit_ok(ip, "/bootstrap", BOOTSTRAP_RATE_MAX, BOOTSTRAP_RATE_WINDOW)
        if not ok:
            log.warning("bootstrap rate-limited ip=%s retry=%ss", ip, retry)
            self._send_429(
                retry,
                f"max {BOOTSTRAP_RATE_MAX} bootstrap tokens per IP per {int(BOOTSTRAP_RATE_WINDOW)}s",
            )
            return
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
            self._send_json(
                503, {"error": "proxy_not_configured", "detail": "GROQ_API_KEY missing on server"}
            )
            return

        ip = self._client_ip()
        ok, retry = rate_limit_ok(ip, "/v1/chat/completions", CHAT_RATE_MAX, CHAT_RATE_WINDOW)
        if not ok:
            log.warning("chat rate-limited ip=%s retry=%ss", ip, retry)
            self._send_429(
                retry, f"max {CHAT_RATE_MAX} chat calls per IP per {int(CHAT_RATE_WINDOW)}s"
            )
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

        if not global_cap_ok():
            log.error("global daily cap reached (%d) — refusing chat ip=%s", GLOBAL_DAILY_CAP, ip)
            self._send_json(
                429,
                {
                    "error": "global_daily_cap",
                    "detail": f"server daily cap {GLOBAL_DAILY_CAP} reached, retry tomorrow",
                },
            )
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
        log.warning(
            "GROQ_API_KEY missing — /v1/chat/completions will return 503. /bootstrap still works."
        )
    else:
        log.info(
            "Groq key loaded (%d chars). Model default: %s", len(GROQ_API_KEY), GROQ_MODEL_DEFAULT
        )
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
