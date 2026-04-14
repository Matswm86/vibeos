"""Cache a snapshot of the user's install state into Vibbey memory.

Runs a handful of allowlisted tools non-interactively at server startup,
parses the output, and writes a structured summary into
``VIBEOS_STATE_DIR/vibbey-memory.json::install_state``. Vibbey can then answer
"do I have Claude Code installed?" without asking the user to click through
tool-use confirmations for the same question every session.

Re-runs on every server start. Cheap (<2s total) and always-fresh beats a
stale cache.
"""

import re

from . import memory as vibbey_memory
from . import tools as vibbey_tools


def _extract_version(output: str) -> str | None:
    if not output:
        return None
    match = re.search(r"\d+\.\d+(?:\.\d+)?(?:[-+][\w.]+)?", output)
    return match.group(0) if match else output.strip().splitlines()[0][:40]


def _parse_ollama_list(output: str) -> list[str]:
    """Parse `ollama list` output into a list of model names.

    Format:
        NAME             ID              SIZE    MODIFIED
        qwen2.5:3b       abc123          1.9 GB  3 days ago
    """
    if not output:
        return []
    lines = [l for l in output.splitlines() if l.strip()]
    if len(lines) <= 1:
        return []
    models: list[str] = []
    for line in lines[1:]:
        parts = line.split()
        if parts:
            models.append(parts[0])
    return models


def _parse_os_release(output: str) -> str | None:
    if not output:
        return None
    for line in output.splitlines():
        if line.startswith("PRETTY_NAME="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def capture_snapshot() -> dict[str, object]:
    """Run the snapshot tools, return a dict with parsed results.

    Also writes the snapshot into Vibbey's persistent memory so chat
    augmentation can reference it without re-running tools.
    """
    results: dict[str, object] = {}

    r = vibbey_tools.run_tool("claude_version")
    results["claude_version"] = _extract_version(r.get("stdout", "")) if r.get("exit_code") == 0 else None

    r = vibbey_tools.run_tool("gh_auth_status")
    if r.get("error") == "not_installed":
        results["gh_authed"] = None
    else:
        results["gh_authed"] = r.get("exit_code") == 0

    r = vibbey_tools.run_tool("ollama_list")
    if r.get("error") == "not_installed":
        results["ollama_models"] = []
    else:
        results["ollama_models"] = _parse_ollama_list(r.get("stdout", ""))

    r = vibbey_tools.run_tool("docker_info")
    if r.get("error") == "not_installed":
        results["docker_running"] = None
    else:
        results["docker_running"] = r.get("exit_code") == 0

    r = vibbey_tools.run_tool("os_release")
    results["os_release"] = _parse_os_release(r.get("stdout", ""))

    vibbey_memory.update_install_state(**results)
    return results
