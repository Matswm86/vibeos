"""Vibbey — 3D Clippy-lineage assistant for VibeOS first-run.

Package layout:

    vibbey/
    ├── __init__.py          this file — loads config at import time
    ├── __main__.py          entry point: `python3 -m vibbey [--server-only] [--window]`
    ├── config.py            reads /etc/vibeos/vibbey.conf → os.environ
    ├── launcher.py          webkit2gtk window + server lifecycle + first-run marker
    ├── server.py            ThreadingHTTPServer + /api/* routes
    ├── groq_proxy.py        Groq BYO-key / bootstrap / Ollama tier router
    ├── tools.py             strict allowlist of shell commands Vibbey can run
    ├── dialogue.py          voice block + 4-step welcome tour + canned responses
    ├── memory.py            JSON memory at VIBEOS_STATE_DIR/vibbey-memory.json
    ├── install_snapshot.py  non-blocking startup snapshot of claude/gh/ollama/docker
    ├── knowledge/           static markdown knowledge pack injected into system prompt
    └── static/              index.html + main.js + style.css + vendor/three + clippy.glb

Single-config design: every model reference reads os.environ['VIBEOS_MODEL'].
The config file (/etc/vibeos/vibbey.conf) is the single source of truth; this
package imports config.load() before anything else so all submodules see the
populated environment without knowing about the config file themselves.
"""

from . import config as _config

# Load config before any submodule can read VIBEOS_MODEL or similar.
# This is safe to call multiple times — subsequent calls are no-ops.
_config.load()
