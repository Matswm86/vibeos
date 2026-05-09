"""mkosi.repart/ partition table checks.

Two partitions only: ESP (vfat, fixed 512M) + root (ext4, grown to disk).
Anything else means the repart layout has drifted.
"""

from __future__ import annotations

import configparser
from pathlib import Path

import pytest


def _parse_partition(path: Path) -> dict[str, str]:
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    cp.read(path, encoding="utf-8")
    assert "Partition" in cp, f"{path}: missing [Partition] section"
    return {k: v.strip() for k, v in cp["Partition"].items()}


@pytest.fixture(scope="module")
def repart_files(mkosi_dir: Path) -> list[Path]:
    files = sorted((mkosi_dir / "mkosi.repart").glob("*.conf"))
    assert files, "no partition definitions found"
    return files


def test_exactly_two_partitions(repart_files: list[Path]) -> None:
    """ESP + root only. Adding a third partition (swap, /home) should be a
    deliberate decision documented in the v2-plan."""
    assert len(repart_files) == 2, f"expected 2 partition files, got {len(repart_files)}"


def test_esp_partition_layout(mkosi_dir: Path) -> None:
    cfg = _parse_partition(mkosi_dir / "mkosi.repart" / "00-esp.conf")
    assert cfg["type"] == "esp"
    assert cfg["format"] == "vfat"
    # Fixed 512M — large enough for systemd-boot + kernel + initrd, small
    # enough that a 16GB USB still fits the root partition.
    assert cfg["sizeminbytes"] == "512M"
    assert cfg["sizemaxbytes"] == "512M"


def test_root_partition_layout(mkosi_dir: Path) -> None:
    cfg = _parse_partition(mkosi_dir / "mkosi.repart" / "10-root.conf")
    assert cfg["type"] == "root"
    assert cfg["format"] == "ext4"
    assert cfg["copyfiles"] == "/"
    # Minimize=guess shrinks the root partition to its minimum free + 5%
    # so the ISO image is small while still allowing growth on first boot.
    assert cfg["minimize"] == "guess"
