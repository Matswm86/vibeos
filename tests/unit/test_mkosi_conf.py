"""mkosi.conf structural + content checks.

Catches mkosi config regressions that would yield a built ISO with no window
manager (kde without kwin-x11), wrong distribution base, or missing kernel
cmdline flags. The cost of catching these at CI is ~20 ms; the cost of
catching them at first-boot QA is ~1 h per ISO build.
"""

from __future__ import annotations

import configparser
from pathlib import Path

import pytest


def _parse_mkosi(path: Path) -> configparser.ConfigParser:
    """mkosi.conf is INI-like. Multi-line `Packages=` values are joined into
    a single string by configparser; we keep that form for substring checks.
    """
    cp = configparser.ConfigParser(strict=False, allow_no_value=True, interpolation=None)
    cp.read(path, encoding="utf-8")
    return cp


@pytest.fixture(scope="module")
def mkosi_conf(mkosi_dir: Path) -> configparser.ConfigParser:
    path = mkosi_dir / "mkosi.conf"
    assert path.exists(), f"missing {path}"
    return _parse_mkosi(path)


def test_required_sections_present(mkosi_conf: configparser.ConfigParser) -> None:
    for section in ("Distribution", "Output", "Build", "Content"):
        assert section in mkosi_conf, f"missing [{section}] in mkosi.conf"


def test_distribution_is_ubuntu_noble(mkosi_conf: configparser.ConfigParser) -> None:
    assert mkosi_conf["Distribution"]["Distribution"].strip() == "ubuntu"
    assert mkosi_conf["Distribution"]["Release"].strip() == "noble"


def test_output_is_disk_image(mkosi_conf: configparser.ConfigParser) -> None:
    assert mkosi_conf["Output"]["Format"].strip() == "disk"
    assert mkosi_conf["Output"]["ImageId"].strip() == "vibeos"


def test_bootable_with_systemd_boot(mkosi_conf: configparser.ConfigParser) -> None:
    """Regression: we hit non-bootable images twice when mkosi defaulted to grub."""
    assert mkosi_conf["Content"]["Bootable"].strip() == "yes"
    assert mkosi_conf["Content"]["Bootloader"].strip() == "systemd-boot"


def test_locale_keymap_timezone(mkosi_conf: configparser.ConfigParser) -> None:
    assert mkosi_conf["Content"]["Locale"].strip() == "en_US.UTF-8"
    # Norwegian keymap, no dead keys — Mats' workstation default.
    assert mkosi_conf["Content"]["Keymap"].strip() == "no-nodeadkeys"
    assert mkosi_conf["Content"]["Timezone"].strip() == "Europe/Oslo"


def test_kernel_cmdline_has_quiet_splash(mkosi_conf: configparser.ConfigParser) -> None:
    cmdline = mkosi_conf["Content"]["KernelCommandLine"]
    assert "quiet" in cmdline
    assert "splash" in cmdline


@pytest.mark.parametrize(
    "package",
    [
        "ubuntu-minimal",
        "linux-image-generic",
        "systemd-boot",
        "network-manager",
        "kde-plasma-desktop",
        # kwin-x11 is mandatory: kde-plasma-desktop only Recommends a kwin variant,
        # and mkosi installs without recommends. Without explicit kwin-x11, Plasma
        # boots with no window manager (no titlebars, no movable windows). The
        # comment in mkosi.conf calls this out explicitly.
        "kwin-x11",
        "sddm",
    ],
)
def test_required_packages_listed(mkosi_conf: configparser.ConfigParser, package: str) -> None:
    pkgs = mkosi_conf["Content"]["Packages"]
    # Packages are whitespace/newline-separated; check exact word match.
    tokens = {p.strip() for p in pkgs.replace("\n", " ").split() if p.strip()}
    assert package in tokens, f"required package {package!r} missing from Packages="


def test_local_package_dir_referenced(mkosi_conf: configparser.ConfigParser) -> None:
    """Ensure mkosi pulls in our locally-built .debs from packages/local/."""
    pkg_dirs = mkosi_conf["Content"]["PackageDirectories"]
    assert "../packages/local" in pkg_dirs


def test_extra_trees_includes_calamares_config(mkosi_conf: configparser.ConfigParser) -> None:
    """Calamares branding regression: drop this and the installer ships stock."""
    extra = mkosi_conf["Content"]["ExtraTrees"]
    assert "../calamares-config:/etc/calamares" in extra
