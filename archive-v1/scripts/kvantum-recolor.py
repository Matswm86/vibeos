#!/usr/bin/env python3
"""Fork an existing Kvantum theme and recolor to VibeOS-Neon palette.

Intended to run inside the cubic chroot during Phase D of Stage 4.
Tries a fallback chain of Kvantum upstream themes (Kubuntu 22.04's
qt5-style-kvantum-themes does not ship every theme listed in older
distros — we pick whichever exists).

Usage:
  kvantum-recolor.py                                  # auto-detect source
  kvantum-recolor.py <source.svg> [<output.svg>]      # explicit override

Exit codes:
  0   success (substitutions written to output)
  2   no source theme found in fallback chain
  3   source theme exists but recolor produced zero substitutions
"""
from __future__ import annotations

import sys
from pathlib import Path

# KvGnomeDark / KvFlatDark / KvFlat hex → VibeOS-Neon hex.
# Case-insensitive match. Order is not significant except that longer
# hex strings are matched first in `replace`.
COLOR_MAP: dict[str, str] = {
    # Dark backgrounds
    "#2b2b2b": "#1A0B2E",  # window bg
    "#1b1b1b": "#0B0218",  # darker bg
    "#3b3b3b": "#2D1B4E",  # button
    "#282828": "#1A0B2E",  # alt bg
    "#323232": "#2D1B4E",  # alt button
    # Borders / mids
    "#5a5a5a": "#9D4EDD",
    "#787878": "#5A3A8A",
    "#4d4d4d": "#5A3A8A",
    "#606060": "#9D4EDD",
    # Muted text
    "#b7b7b7": "#B5A6D9",
    "#9a9a9a": "#B5A6D9",
    "#c0c0c0": "#B5A6D9",
    # Foreground
    "#eeeeee": "#F8F0FF",
    "#ffffff": "#F8F0FF",
    "#f0f0f0": "#F8F0FF",
    # Accents (KvGnomeDark blues → neon cyan/magenta)
    "#3daee9": "#01F9FF",
    "#7aaed6": "#FF71CE",
    "#1e7ec0": "#FF2ECF",
    "#2980b9": "#FF2ECF",
    "#4fb3e6": "#01F9FF",
    # KvFlat red accents → magenta
    "#da4453": "#FF2ECF",
    "#ed1515": "#FF2ECF",
    "#c0392b": "#FF71CE",
}

# Fallback chain — first existing source wins.
# `qt5-style-kvantum-themes` layout on Kubuntu 22.04:
#   /usr/share/Kvantum/<ThemeName>/<ThemeName>.svg
SOURCE_CANDIDATES: list[Path] = [
    Path("/usr/share/Kvantum/KvGnomeDark/KvGnomeDark.svg"),
    Path("/usr/share/Kvantum/KvFlatDark/KvFlatDark.svg"),
    Path("/usr/share/Kvantum/KvAdapta/KvAdapta.svg"),
    Path("/usr/share/Kvantum/KvFlat/KvFlat.svg"),
    Path("/usr/share/Kvantum/KvDarkRed/KvDarkRed.svg"),
    Path("/usr/share/Kvantum/KvCurvesDark/KvCurvesDark.svg"),
    Path("/usr/share/Kvantum/KvOxygen/KvOxygen.svg"),
]

DEFAULT_OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "theming"
    / "plasma"
    / "Kvantum"
    / "VibeOS-Neon"
    / "VibeOS-Neon.svg"
)


def find_source() -> Path | None:
    """Walk SOURCE_CANDIDATES, return the first existing path."""
    for candidate in SOURCE_CANDIDATES:
        if candidate.exists():
            return candidate
    return None


def recolor(source: Path, output: Path) -> int:
    if not source.exists():
        sys.stderr.write(
            f"error: source theme not found at {source}\n"
            "hint: apt install qt5-style-kvantum-themes\n"
        )
        return 2

    svg = source.read_text(encoding="utf-8")
    total = 0
    for old, new in COLOR_MAP.items():
        count = svg.lower().count(old.lower())
        if count == 0:
            continue
        # Preserve case variants: replace both lower and upper forms.
        svg = svg.replace(old.lower(), new)
        svg = svg.replace(old.upper(), new)
        total += count

    if total == 0:
        sys.stderr.write(
            f"warn: zero substitutions for {source.name} — palette may not match.\n"
            "      Kvantum will still load but theme will look stock.\n"
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(svg, encoding="utf-8")
    print(f"recolored {source} -> {output} ({total} substitutions)")
    return 0 if total > 0 else 3


def main() -> int:
    argv = sys.argv[1:]

    if argv:
        source = Path(argv[0])
        output = Path(argv[1]) if len(argv) > 1 else DEFAULT_OUTPUT
    else:
        found = find_source()
        if found is None:
            sys.stderr.write(
                "error: no Kvantum upstream theme found. Tried:\n"
                + "".join(f"  - {c}\n" for c in SOURCE_CANDIDATES)
                + "hint: apt install qt5-style-kvantum-themes\n"
            )
            return 2
        print(f"[kvantum-recolor] auto-selected source: {found}")
        source = found
        output = DEFAULT_OUTPUT

    return recolor(source, output)


if __name__ == "__main__":
    raise SystemExit(main())
