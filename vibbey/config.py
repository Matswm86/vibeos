"""Load /etc/vibeos/vibbey.conf into os.environ.

Called at package __init__ time so all downstream code can do
os.environ.get('VIBEOS_MODEL', ...) with consistent defaults.

Does NOT raise on missing or malformed file — sensible defaults always work.
Environment variables set before import always take precedence (systemd
EnvironmentFile= sets them before the Python process starts).
"""
import os
from pathlib import Path

CONFIG_PATH = Path(os.environ.get("VIBEOS_CONFIG", "/etc/vibeos/vibbey.conf"))

DEFAULTS: dict[str, str] = {
    "VIBEOS_MODEL": "qwen2.5:3b",
    "VIBEOS_GROQ_MODEL": "llama-3.3-70b-versatile",
    "VIBEOS_GROQ_API_KEY": "",
    "VIBEOS_CLAUDE_API_KEY": "",
}


def load() -> None:
    """Parse config and set missing env vars. Never clobbers existing env."""
    # Apply defaults first (lowest priority — real env and config file win)
    for key, value in DEFAULTS.items():
        if key not in os.environ:
            os.environ[key] = value

    if not CONFIG_PATH.exists():
        return

    try:
        for raw_line in CONFIG_PATH.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip("\"'")
            # Only set if not already present — env vars take precedence
            if key and key not in os.environ:
                os.environ[key] = value
    except OSError:
        pass  # proceed with defaults
