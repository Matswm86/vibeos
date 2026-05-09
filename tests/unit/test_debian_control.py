"""debian/control validity checks across vibeos source packages.

Each control file declares one source package + ≥1 binary package. We validate
the required fields per Debian Policy §5 and a few project-specific invariants
(maintainer email, vibbey runtime depends).
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REQUIRED_SOURCE_FIELDS = {"Source", "Section", "Priority", "Maintainer", "Standards-Version"}
REQUIRED_BINARY_FIELDS = {"Package", "Architecture", "Description"}


def _parse_control(path: Path) -> list[dict[str, str]]:
    """Parse a debian/control file into a list of paragraphs. Each paragraph
    is a {field: value} dict; multi-line fields are joined by newlines."""
    text = path.read_text(encoding="utf-8")
    paragraphs: list[dict[str, str]] = []
    current: dict[str, str] = {}
    last_field: str | None = None

    for line in text.splitlines():
        if not line.strip():
            if current:
                paragraphs.append(current)
                current = {}
            last_field = None
            continue
        if line.startswith((" ", "\t")):
            # Continuation of previous field.
            if last_field is not None:
                current[last_field] += "\n" + line.strip()
            continue
        if ":" not in line:
            raise ValueError(f"{path}: malformed line {line!r}")
        field, _, value = line.partition(":")
        field = field.strip()
        current[field] = value.strip()
        last_field = field

    if current:
        paragraphs.append(current)
    return paragraphs


@pytest.fixture(scope="module")
def control_paragraphs(debian_packages: list[Path]) -> dict[str, list[dict[str, str]]]:
    return {pkg.name: _parse_control(pkg / "debian" / "control") for pkg in debian_packages}


def test_at_least_three_packages(control_paragraphs: dict[str, list[dict[str, str]]]) -> None:
    """Sanity: vibeos-claude-code, vibeos-desktop, vibeos-vibbey all present."""
    assert "vibeos-claude-code" in control_paragraphs
    assert "vibeos-desktop" in control_paragraphs
    assert "vibeos-vibbey" in control_paragraphs


@pytest.mark.parametrize("pkg_name", ["vibeos-claude-code", "vibeos-desktop", "vibeos-vibbey"])
def test_source_paragraph_required_fields(
    control_paragraphs: dict[str, list[dict[str, str]]], pkg_name: str
) -> None:
    paragraphs = control_paragraphs[pkg_name]
    assert paragraphs, f"{pkg_name}: empty control file"
    source_para = paragraphs[0]
    missing = REQUIRED_SOURCE_FIELDS - source_para.keys()
    assert not missing, f"{pkg_name}: source paragraph missing fields: {missing}"
    assert source_para["Source"] == pkg_name


@pytest.mark.parametrize("pkg_name", ["vibeos-claude-code", "vibeos-desktop", "vibeos-vibbey"])
def test_binary_paragraphs_required_fields(
    control_paragraphs: dict[str, list[dict[str, str]]], pkg_name: str
) -> None:
    paragraphs = control_paragraphs[pkg_name]
    binaries = paragraphs[1:]
    assert binaries, f"{pkg_name}: no binary package paragraphs"
    for para in binaries:
        missing = REQUIRED_BINARY_FIELDS - para.keys()
        assert not missing, f"{pkg_name}: binary {para.get('Package')} missing fields: {missing}"


def test_maintainer_email_consistent(
    control_paragraphs: dict[str, list[dict[str, str]]],
) -> None:
    """All packages share one maintainer; drift is almost always a paste error."""
    seen = {paragraphs[0]["Maintainer"] for paragraphs in control_paragraphs.values()}
    assert len(seen) == 1, f"maintainer drift across packages: {seen}"
    (maintainer,) = seen
    assert "@" in maintainer and "<" in maintainer and ">" in maintainer


def test_vibbey_runtime_depends_on_ollama(
    control_paragraphs: dict[str, list[dict[str, str]]],
) -> None:
    """Regression: dropping `ollama` from Depends ships a Vibbey that 500s on
    every prompt. Has happened once in v2.0.0-day1."""
    binaries = control_paragraphs["vibeos-vibbey"][1:]
    vibbey = next((p for p in binaries if p.get("Package") == "vibeos-vibbey"), None)
    assert vibbey is not None
    depends = vibbey["Depends"].lower()
    assert "ollama" in depends, "vibeos-vibbey must Depends: ollama"
    # Python 3.11 floor matches what mkosi.conf installs.
    assert re.search(r"python3\s*\(\s*>=\s*3\.11\s*\)", depends), depends
