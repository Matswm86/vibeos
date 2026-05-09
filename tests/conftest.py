"""Shared pytest fixtures for vibeos pre-build tests."""

from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture(scope="session")
def repo_root() -> Path:
    """Absolute path to the vibeos repo root (parent of tests/)."""
    return Path(__file__).resolve().parent.parent


@pytest.fixture(scope="session")
def mkosi_dir(repo_root: Path) -> Path:
    return repo_root / "mkosi"


@pytest.fixture(scope="session")
def packages_dir(repo_root: Path) -> Path:
    return repo_root / "packages"


@pytest.fixture(scope="session")
def systemd_units(packages_dir: Path) -> list[Path]:
    """Real systemd units shipped by our packages.

    Excludes debhelper-generated artifacts under .debhelper/ and the staged
    install trees under debian/<pkg>/ — those are build outputs, not source.
    """
    skip_parts = {".debhelper"}
    units: list[Path] = []
    for pkg in packages_dir.iterdir():
        if not pkg.is_dir() or pkg.name == "local":
            continue
        src = pkg / "src"
        if not src.exists():
            continue
        for path in src.rglob("*"):
            if path.suffix not in {".service", ".timer", ".socket", ".target", ".mount"}:
                continue
            if any(p in skip_parts for p in path.parts):
                continue
            units.append(path)
    return sorted(units)


@pytest.fixture(scope="session")
def debian_packages(packages_dir: Path) -> list[Path]:
    """Source package directories with a debian/control file."""
    out: list[Path] = []
    for pkg in packages_dir.iterdir():
        if not pkg.is_dir() or pkg.name == "local":
            continue
        if (pkg / "debian" / "control").exists():
            out.append(pkg)
    return sorted(out)
