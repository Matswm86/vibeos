"""Tool-use allowlist — the only shell commands Vibbey is allowed to run.

Design principles:
  * Strict allowlist. If a command isn't in ``ALLOWED``, it's rejected.
  * Read-only. No writes, no network requests, no sudo, no config edits.
  * Fixed argument shapes. ``ollama pull`` takes one model name matching a
    regex; no shell interpolation.
  * Bounded runtime. Every command has a timeout (default 30s, pull is 600s).
  * Capture stdout + stderr + exit, return as JSON.

Frontend flow: user asks Vibbey "am I logged into GitHub?" → Vibbey responds
"Let me check — may I run ``gh auth status``?" → user confirms → frontend
POSTs to ``/api/run`` with ``{command: "gh_auth_status"}`` → backend validates,
runs, returns result → Vibbey interprets and replies.

The allowlist keys are stable command IDs (not raw shell strings) so we don't
have to parse user input and can't accidentally allow `gh auth status; rm -rf`.
"""

import re
import shutil
import subprocess
from dataclasses import dataclass
from typing import Callable


@dataclass
class ToolSpec:
    """Declarative spec for one allowlisted command."""
    argv: list[str]                 # exact argv to execute (no shell)
    description: str                # human-readable (shown in confirm prompt)
    timeout_s: int = 30
    # Optional: builder for commands that take one user-supplied argument.
    # The builder receives the validated argument and returns the final argv.
    accepts_arg: bool = False
    arg_pattern: re.Pattern[str] | None = None
    arg_builder: Callable[[str], list[str]] | None = None
    # Spawn-and-detach: for long-running GUI processes (e.g. the installer).
    # We Popen with start_new_session=True and return immediately with
    # exit_code=0 + a "spawned" stdout marker. Caller never blocks.
    detach: bool = False


# Model name regex: allow alphanumerics, dots, hyphens, colons, slashes (for
# repo/model format like "library/gemma3:4b"). Max 64 chars. No shell metachars.
_MODEL_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._\-:/]{0,63}$")


ALLOWED: dict[str, ToolSpec] = {
    # ── Claude Code ────────────────────────────────────────
    "claude_version": ToolSpec(
        argv=["claude", "--version"],
        description="Show the installed Claude Code version",
    ),

    # ── GitHub CLI ─────────────────────────────────────────
    "gh_version": ToolSpec(
        argv=["gh", "--version"],
        description="Show the installed GitHub CLI version",
    ),
    "gh_auth_status": ToolSpec(
        argv=["gh", "auth", "status"],
        description="Check if GitHub CLI is authenticated",
    ),

    # ── Ollama ─────────────────────────────────────────────
    "ollama_list": ToolSpec(
        argv=["ollama", "list"],
        description="List locally pulled Ollama models",
    ),
    "ollama_pull": ToolSpec(
        argv=["ollama", "pull"],  # plus the user-supplied model name
        description="Pull an Ollama model (takes several minutes)",
        timeout_s=600,
        accepts_arg=True,
        arg_pattern=_MODEL_NAME_RE,
        arg_builder=lambda m: ["ollama", "pull", m],
    ),

    # ── Docker ─────────────────────────────────────────────
    "docker_info": ToolSpec(
        argv=["docker", "info"],
        description="Check Docker daemon status",
    ),
    "docker_ps": ToolSpec(
        argv=["docker", "ps"],
        description="List running Docker containers",
    ),

    # ── System inspection ──────────────────────────────────
    "os_release": ToolSpec(
        argv=["cat", "/etc/os-release"],
        description="Show distro + version",
    ),
    "uname": ToolSpec(
        argv=["uname", "-a"],
        description="Show kernel version + arch",
    ),
    "free_memory": ToolSpec(
        argv=["free", "-h"],
        description="Show RAM + swap usage (human-readable)",
    ),
    "disk_home": ToolSpec(
        argv=["df", "-h", str(__import__("pathlib").Path.home())],
        description="Show disk space on home directory",
    ),
    "cpu_info": ToolSpec(
        argv=["lscpu"],
        description="Show CPU model + cores + features",
    ),
    "nvidia_smi": ToolSpec(
        argv=["nvidia-smi"],
        description="Show NVIDIA GPU status (if present)",
    ),

    # ── Python ─────────────────────────────────────────────
    "python_version": ToolSpec(
        argv=["python3", "--version"],
        description="Show Python 3 version",
    ),
    "node_version": ToolSpec(
        argv=["node", "--version"],
        description="Show Node.js version",
    ),

    # ── Installer ──────────────────────────────────────────
    # Live-session only in practice — on installed systems Calamares
    # is usually still present but launching it is harmless (it'll just
    # show "no media" and exit). pkexec gives the polkit auth dialog
    # the live `vibeos` user already has NOPASSWD rules for.
    "install_vibeos": ToolSpec(
        argv=["pkexec", "calamares", "-d"],
        description="Launch the VibeOS installer (Calamares)",
        detach=True,
    ),
    "is_live_session": ToolSpec(
        argv=["test", "-d", "/cdrom/casper"],
        description="Check whether we're running from the live ISO",
    ),
}


def list_tools() -> list[dict[str, str]]:
    """Return a JSON-serializable list of allowed tools for Vibbey's context."""
    out = []
    for key, spec in ALLOWED.items():
        out.append({
            "id": key,
            "description": spec.description,
            "accepts_arg": spec.accepts_arg,
        })
    return out


def run_tool(tool_id: str, arg: str | None = None) -> dict[str, object]:
    """Execute an allowlisted tool, return ``{stdout, stderr, exit_code}``.

    Returns an ``error`` field instead if:
      * tool_id is not in the allowlist
      * the tool requires an arg but none was given (or vice versa)
      * the arg doesn't match the allowed pattern
      * the command binary isn't on $PATH
      * the subprocess times out
    """
    spec = ALLOWED.get(tool_id)
    if spec is None:
        return {"error": "not_allowlisted", "detail": f"tool '{tool_id}' is not allowed"}

    if spec.accepts_arg:
        if arg is None:
            return {"error": "missing_arg", "detail": f"tool '{tool_id}' requires an argument"}
        if spec.arg_pattern is None or not spec.arg_pattern.match(arg):
            return {"error": "bad_arg", "detail": f"arg '{arg}' rejected by pattern"}
        if spec.arg_builder is None:
            return {"error": "config_error", "detail": "arg_builder missing"}
        argv = spec.arg_builder(arg)
    else:
        if arg is not None:
            return {"error": "unexpected_arg", "detail": f"tool '{tool_id}' takes no argument"}
        argv = list(spec.argv)

    # Is the binary present?
    if shutil.which(argv[0]) is None:
        return {
            "error": "not_installed",
            "detail": f"'{argv[0]}' is not on PATH",
            "tool_id": tool_id,
        }

    if spec.detach:
        try:
            subprocess.Popen(
                argv,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as e:
            return {"error": "spawn_failed", "detail": str(e), "tool_id": tool_id}
        return {
            "tool_id": tool_id,
            "argv": argv,
            "stdout": f"spawned {argv[0]} (detached)",
            "stderr": "",
            "exit_code": 0,
        }

    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=spec.timeout_s,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {
            "error": "timeout",
            "detail": f"'{' '.join(argv)}' timed out after {spec.timeout_s}s",
            "tool_id": tool_id,
        }
    except FileNotFoundError as e:
        return {
            "error": "not_installed",
            "detail": str(e),
            "tool_id": tool_id,
        }

    # Trim very long output so the UI stays sane
    def _trim(s: str, limit: int = 4000) -> str:
        if len(s) <= limit:
            return s
        return s[:limit] + f"\n... [trimmed {len(s) - limit} chars]"

    return {
        "tool_id": tool_id,
        "argv": argv,
        "stdout": _trim(proc.stdout),
        "stderr": _trim(proc.stderr),
        "exit_code": proc.returncode,
    }
