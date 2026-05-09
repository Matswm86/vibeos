"""debian/changelog header parsing.

Catches malformed first lines that break sbuild / dpkg-buildpackage. The parser
mirrors `dpkg-parsechangelog`'s expectations: PKG (VERSION) DISTRO; urgency=URG.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

# Format: "package (version) distro1 distro2; urgency=urgency"
HEADER_RE = re.compile(
    r"^(?P<pkg>[a-z0-9][a-z0-9.+-]+) "
    r"\((?P<version>[^)]+)\) "
    r"(?P<distros>[A-Za-z0-9 ._-]+); "
    r"urgency=(?P<urgency>low|medium|high|critical|emergency)\s*$"
)

ALLOWED_DISTROS = {"unstable", "stable", "noble", "jammy", "focal", "UNRELEASED"}


@pytest.fixture(scope="module")
def changelog_first_lines(debian_packages: list[Path]) -> dict[str, str]:
    out: dict[str, str] = {}
    for pkg in debian_packages:
        path = pkg / "debian" / "changelog"
        with path.open(encoding="utf-8") as fh:
            out[pkg.name] = fh.readline().rstrip("\n")
    return out


@pytest.mark.parametrize("pkg_name", ["vibeos-claude-code", "vibeos-desktop", "vibeos-vibbey"])
def test_header_parses(changelog_first_lines: dict[str, str], pkg_name: str) -> None:
    line = changelog_first_lines[pkg_name]
    match = HEADER_RE.match(line)
    assert match is not None, f"{pkg_name} changelog header malformed: {line!r}"
    assert match.group("pkg") == pkg_name


@pytest.mark.parametrize("pkg_name", ["vibeos-claude-code", "vibeos-desktop", "vibeos-vibbey"])
def test_distro_in_allowed_set(changelog_first_lines: dict[str, str], pkg_name: str) -> None:
    line = changelog_first_lines[pkg_name]
    match = HEADER_RE.match(line)
    assert match is not None
    distros = match.group("distros").split()
    unknown = set(distros) - ALLOWED_DISTROS
    assert not unknown, f"{pkg_name} unknown distros: {unknown}"


@pytest.mark.parametrize("pkg_name", ["vibeos-claude-code", "vibeos-desktop", "vibeos-vibbey"])
def test_version_non_empty_and_starts_with_digit(
    changelog_first_lines: dict[str, str], pkg_name: str
) -> None:
    line = changelog_first_lines[pkg_name]
    match = HEADER_RE.match(line)
    assert match is not None
    version = match.group("version")
    assert version, f"{pkg_name} empty version"
    assert version[0].isdigit(), f"{pkg_name} version must start with digit: {version!r}"
