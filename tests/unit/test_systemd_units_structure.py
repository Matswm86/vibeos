"""Structural checks on shipped systemd unit files.

Cheap sanity (no systemd-analyze required, runs in milliseconds). For the full
grammar check, see tests/integration/test_systemd_analyze_verify.py.
"""

from __future__ import annotations

import configparser
from pathlib import Path

import pytest


def _parse_unit(path: Path) -> configparser.ConfigParser:
    cp = configparser.ConfigParser(strict=False, allow_no_value=True, interpolation=None)
    cp.read(path, encoding="utf-8")
    return cp


def test_at_least_one_unit_shipped(systemd_units: list[Path]) -> None:
    assert systemd_units, "no systemd unit files found in packages/*/src/"


@pytest.fixture(scope="module")
def parsed_units(systemd_units: list[Path]) -> dict[Path, configparser.ConfigParser]:
    return {path: _parse_unit(path) for path in systemd_units}


def test_every_unit_has_unit_section(parsed_units: dict[Path, configparser.ConfigParser]) -> None:
    for path, cp in parsed_units.items():
        assert "Unit" in cp, f"{path}: missing [Unit] section"


def test_every_unit_has_description(parsed_units: dict[Path, configparser.ConfigParser]) -> None:
    for path, cp in parsed_units.items():
        desc = cp["Unit"].get("Description", "").strip()
        assert desc, f"{path}: empty Description="


def test_service_units_have_execstart(
    parsed_units: dict[Path, configparser.ConfigParser],
) -> None:
    for path, cp in parsed_units.items():
        if path.suffix != ".service":
            continue
        assert "Service" in cp, f"{path}: missing [Service] section"
        # Type=oneshot may use ExecStart=… or ExecStartPre=…; require at least one.
        has_exec = any(
            cp["Service"].get(field, "").strip() for field in ("ExecStart", "ExecStartPre")
        )
        assert has_exec, f"{path}: no ExecStart/ExecStartPre"


def test_install_section_targets_known_target(
    parsed_units: dict[Path, configparser.ConfigParser],
) -> None:
    """If [Install] is present, WantedBy/RequiredBy must point at a real target."""
    known_targets = {
        "multi-user.target",
        "graphical.target",
        "default.target",
        "timers.target",
        "sockets.target",
        "network-online.target",
    }
    for path, cp in parsed_units.items():
        if "Install" not in cp:
            continue
        wanted = cp["Install"].get("WantedBy", "").strip()
        required = cp["Install"].get("RequiredBy", "").strip()
        targets = {*wanted.split(), *required.split()}
        if not targets:
            continue
        unknown = targets - known_targets
        assert not unknown, f"{path}: [Install] references unknown target(s): {unknown}"
