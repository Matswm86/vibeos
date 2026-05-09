"""Run `systemd-analyze verify` against every shipped unit file.

This catches malformed unit grammar, deprecated directives, and bad option
values that the pure-INI structural test in tests/unit/ doesn't see.

Skipped locally on hosts without systemd-analyze; required green in CI on
ubuntu-24.04 (systemd is preinstalled).

Two classes of error are *expected* and filtered out:
  - "Command X is not executable: No such file or directory" — the binary
    is installed by the .deb at runtime; absent on the build host.
  - "Failed to resolve unit specifier in After=ollama.service" type errors
    when the unit is referenced but not staged — same reason.

Anything else (bad directive, parse error, deprecated key, unknown option)
fails the test.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.integration


_RUNTIME_DEP_ERROR_PATTERNS = (
    re.compile(r"Command .* is not executable: No such file or directory"),
    re.compile(r"Failed to resolve unit specifiers"),
)


def _filter_expected_errors(stderr: str) -> list[str]:
    """Return only the error/warning lines that aren't expected runtime-dep
    misses. An empty result means the unit passed."""
    real: list[str] = []
    for line in stderr.splitlines():
        line = line.rstrip()
        if not line:
            continue
        if any(p.search(line) for p in _RUNTIME_DEP_ERROR_PATTERNS):
            continue
        real.append(line)
    return real


@pytest.fixture(scope="module")
def systemd_analyze() -> str:
    binary = shutil.which("systemd-analyze")
    if binary is None:
        pytest.skip("systemd-analyze not on PATH")
    return binary


def test_at_least_one_unit_to_verify(systemd_units: list[Path]) -> None:
    assert systemd_units, "no units to verify"


def test_systemd_analyze_verify_each_unit(
    systemd_analyze: str, systemd_units: list[Path], tmp_path: Path
) -> None:
    staged = tmp_path / "units"
    staged.mkdir()
    for unit in systemd_units:
        (staged / unit.name).write_bytes(unit.read_bytes())

    failures: list[tuple[Path, str]] = []
    for unit in systemd_units:
        result = subprocess.run(
            [systemd_analyze, "verify", "--no-pager", str(staged / unit.name)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        real_errors = _filter_expected_errors(result.stderr + result.stdout)
        if real_errors:
            failures.append((unit, "\n".join(real_errors)))

    assert not failures, "systemd-analyze verify failed for:\n" + "\n".join(
        f"  {p}:\n    {msg}" for p, msg in failures
    )
