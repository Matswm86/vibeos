#!/usr/bin/env python3
"""Fork an existing Kvantum theme and recolor to VibeOS-Neon palette.

Intended to run inside the cubic chroot during Phase D of Stage 4.
Reads `/usr/share/Kvantum/KvGnomeDark/KvGnomeDark.svg` and emits
`theming/plasma/Kvantum/VibeOS-Neon/VibeOS-Neon.svg` next to the kvconfig.

If `qt5-style-kvantum-themes` is not installed yet, the script aborts with
a clear error — it is not meant to fall back silently.
"""
from __future__ import annotations

import sys
from pathlib import Path

# KvGnomeDark hex → VibeOS-Neon hex (case-insensitive match)
COLOR_MAP: dict[str, str] = {
    "#2b2b2b": "#1A0B2E",  # window bg
    "#1b1b1b": "#0B0218",  # darker bg
    "#3b3b3b": "#2D1B4E",  # button
    "#5a5a5a": "#9D4EDD",  # border
    "#787878": "#5A3A8A",  # mid
    "#b7b7b7": "#B5A6D9",  # muted text
    "#eeeeee": "#F8F0FF",  # foreground
    "#3daee9": "#01F9FF",  # blue accent
    "#7aaed6": "#FF71CE",  # hover accent
    "#1e7ec0": "#FF2ECF",  # pressed accent
}

DEFAULT_SOURCE = Path("/usr/share/Kvantum/KvGnomeDark/KvGnomeDark.svg")
DEFAULT_OUTPUT = Path(__file__).resolve().parent.parent / "theming" / "plasma" / "Kvantum" / "VibeOS-Neon" / "VibeOS-Neon.svg"


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

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(svg, encoding="utf-8")
    print(f"recolored {source} -> {output} ({total} substitutions)")
    return 0


def main() -> int:
    source = DEFAULT_SOURCE
    output = DEFAULT_OUTPUT
    argv = sys.argv[1:]
    if argv:
        source = Path(argv[0])
    if len(argv) > 1:
        output = Path(argv[1])
    return recolor(source, output)


if __name__ == "__main__":
    raise SystemExit(main())
