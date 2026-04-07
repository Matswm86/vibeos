"""Shell command runner with output capture and error handling."""

import subprocess
import shutil
from dataclasses import dataclass


@dataclass
class RunResult:
    returncode: int
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        return self.returncode == 0

    @property
    def output(self) -> str:
        return self.stdout.strip()


def run(cmd: str, timeout: int = 60, check: bool = False) -> RunResult:
    """Run a shell command, capture output."""
    try:
        proc = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        result = RunResult(proc.returncode, proc.stdout, proc.stderr)
        if check and not result.ok:
            raise subprocess.CalledProcessError(
                proc.returncode, cmd, proc.stdout, proc.stderr
            )
        return result
    except subprocess.TimeoutExpired:
        return RunResult(124, "", f"Command timed out after {timeout}s: {cmd}")


def has_command(name: str) -> bool:
    """Check if a command is on PATH."""
    return shutil.which(name) is not None


def run_interactive(cmd: str) -> int:
    """Run a command with stdin/stdout attached to terminal (for auth flows)."""
    return subprocess.call(cmd, shell=True)
