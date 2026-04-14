# groq-proxy

VibeOS bootstrap Groq proxy. Gives fresh installs 300 free messages on
`llama-3.3-70b-versatile` before they have to bring their own Groq key.

**Live at**: `https://groq.mwmai.no`

## Shape

- Stdlib Python 3.11+ (no pip deps)
- `http.server.ThreadingHTTPServer` on `127.0.0.1:8200`
- SQLite quota store at `~/services/groq-proxy/quota.db`
- Systemd user unit fronted by Caddy

## Endpoints

| Method | Path                       | Auth                        | Purpose                        |
|--------|----------------------------|-----------------------------|--------------------------------|
| GET    | `/health`                  | none                        | Liveness + aggregate stats     |
| POST   | `/bootstrap`               | none                        | Issue a fresh 300-msg token    |
| POST   | `/v1/chat/completions`     | `Authorization: Bearer ...` | OpenAI-compat chat to Groq     |

### `POST /bootstrap`

Request body (optional): `{"label": "my-machine"}` — free-text tag, max 64 chars.

Response:
```json
{"token": "Xy1a2...", "quota": 300, "used": 0}
```

### `POST /v1/chat/completions`

Request is the standard OpenAI chat-completions shape. `model` is
optional — defaults to `llama-3.3-70b-versatile` (overridable via the
`GROQ_MODEL` env var). Response is whatever Groq returned, unchanged.

Response headers:
- `X-Bootstrap-Remaining: 299`
- `X-Bootstrap-Quota: 300`

Error codes:
- `401 missing_bearer_token` / `invalid_token`
- `402 quota_exhausted`
- `413 payload_too_large`
- `503 proxy_not_configured` (server is missing `GROQ_API_KEY`)
- `502 groq_unreachable` / `groq_os_error`

## Config (env)

Loaded from `/etc/mwmai/vibeos.env`:

```bash
GROQ_API_KEY=gsk_...       # required
GROQ_MODEL=llama-3.3-70b-versatile
PORT=8200
BOOTSTRAP_QUOTA=300
QUOTA_DB=~/services/groq-proxy/quota.db
```

## Deploy

```bash
# 1. Copy service files to your VPS
rsync -av services/groq-proxy/ \
    <user>@<your-vps>:~/services/groq-proxy/

# 2. Install systemd user unit
scp services/groq-proxy/groq-proxy.service \
    <user>@<your-vps>:~/.config/systemd/user/
ssh <user>@<your-vps> "systemctl --user daemon-reload && \
    systemctl --user enable --now groq-proxy.service"

# 3. Create an env file (example path: /etc/mwmai/vibeos.env)
#    with a workspace-owned Groq key. One-time manual step — key
#    comes from console.groq.com.

# 4. Add a Caddy (or nginx) vhost for your public hostname →
#    reverse_proxy 127.0.0.1:8200.

# 5. Verify
curl https://<your-hostname>/health
curl -X POST https://<your-hostname>/bootstrap
```

## Operator commands

```bash
# Live logs
ssh <user>@<your-vps> "journalctl --user -u groq-proxy.service -f"

# Restart after key rotation
ssh <user>@<your-vps> "systemctl --user restart groq-proxy.service"

# Peek at quota table
ssh <user>@<your-vps> "sqlite3 ~/services/groq-proxy/quota.db \
    'SELECT token, used_count, quota, label FROM tokens ORDER BY first_seen DESC LIMIT 20'"
```

## Security posture

- **Token entropy**: 32-byte URL-safe random = 256 bits (`secrets.token_urlsafe`)
- **Token storage**: SQLite WAL mode, file perms 0600 (systemd `PrivateTmp`)
- **Groq key**: lives in `/etc/mwmai/vibeos.env` with `0640 root:mats`; never reaches the ISO or the client
- **Rate limiting**: per-token quota (300) — not per-IP. If someone floods `/bootstrap` to mint tokens, that's bounded by Groq's free-tier limits on the workspace account. Upgrade path: add per-IP limiter if abuse appears
- **No CORS**: API is only meant for direct Vibbey calls, not browser JS

## Why no JWT?

Plain random tokens are simpler to validate (single SQLite lookup) and
equally secure for this threat model (burn-after-use quota). JWT would
add signing complexity without fixing anything the quota DB already handles.
