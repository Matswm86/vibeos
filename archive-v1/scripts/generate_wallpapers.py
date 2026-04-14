#!/usr/bin/env python3
"""Generate VibeOS synthetic Neon Grid wallpaper set via Pillow.

Produces five 1920x1080 JPGs from the VibeOS Neon Grid palette:
radial gradient base + perspective grid overlay + horizon line +
vignette + accent dot. All cc0 (we authored it).

Usage:
  python3 scripts/generate_wallpapers.py <output_dir>

Idempotent: rewrites every file each run. Deterministic output.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


W, H = 1920, 1080

# Palette (Neon Grid)
BG0 = (11, 2, 24)       # #0B0218 near-black
BG1 = (26, 11, 46)      # #1A0B2E midnight
BG2 = (45, 27, 78)      # #2D1B4E plum
MAGENTA = (255, 46, 207)
HOTPINK = (255, 113, 206)
CYAN = (1, 249, 255)
VIOLET = (157, 78, 221)
YELLOW = (255, 228, 0)
MINT = (5, 255, 161)
BLACK = (0, 0, 0)


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        int(a[0] + (b[0] - a[0]) * t),
        int(a[1] + (b[1] - a[1]) * t),
        int(a[2] + (b[2] - a[2]) * t),
    )


def radial_gradient(
    inner: tuple[int, int, int],
    outer: tuple[int, int, int],
    w: int = W,
    h: int = H,
) -> Image.Image:
    """Radial gradient centered on (w/2, h*0.58), biased below horizon."""
    cx, cy = w / 2, h * 0.58
    max_r = math.hypot(max(cx, w - cx), max(cy, h - cy))

    img = Image.new("RGB", (w, h), outer)
    px = img.load()
    assert px is not None
    for y in range(h):
        for x in range(w):
            r = math.hypot(x - cx, y - cy) / max_r
            t = min(1.0, r ** 1.4)
            px[x, y] = lerp(inner, outer, t)
    return img


def draw_grid(
    img: Image.Image,
    color: tuple[int, int, int],
    step: int,
    alpha: int = 56,
) -> None:
    """Draw a neon grid overlay on the image via a separate RGBA layer."""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    line_color = (*color, alpha)
    w, h = img.size
    for x in range(0, w, step):
        draw.line([(x, 0), (x, h)], fill=line_color, width=1)
    for y in range(0, h, step):
        draw.line([(0, y), (w, y)], fill=line_color, width=1)
    img.paste(overlay, (0, 0), overlay)


def draw_perspective_grid(
    img: Image.Image,
    color: tuple[int, int, int],
    horizon_y: int,
    alpha: int = 110,
) -> None:
    """Tron-style perspective grid converging on a horizon vanishing point."""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    line_color = (*color, alpha)
    w, h = img.size
    cx = w // 2

    # Horizontal perspective lines (receding toward horizon)
    num_lines = 18
    for i in range(1, num_lines + 1):
        # Exponential spacing: denser near horizon, wider at bottom
        t = i / num_lines
        depth = 1.0 - (1.0 - t) ** 2
        y = int(horizon_y + depth * (h - horizon_y))
        a = int(alpha * (1.0 - t * 0.3))
        draw.line([(0, y), (w, y)], fill=(*color, a), width=1 if t < 0.7 else 2)

    # Radiating vertical lines (converging on vanishing point)
    num_rays = 24
    for i in range(-num_rays, num_rays + 1):
        # Spread rays across the bottom of the screen
        x_bottom = cx + int(i * (w / num_rays) * 0.9)
        draw.line(
            [(x_bottom, h), (cx, horizon_y)],
            fill=line_color,
            width=1,
        )

    img.paste(overlay, (0, 0), overlay)


def draw_horizon_and_sun(
    img: Image.Image,
    accent: tuple[int, int, int],
    grid: tuple[int, int, int],
    horizon_y: int,
) -> None:
    w, h = img.size
    cx = w // 2

    # Horizon line (the bright one)
    line = Image.new("RGBA", (w, 4), (*grid, 200))
    img.paste(line, (0, horizon_y - 2), line)

    # Sun: vertical-scanline styled circle above the horizon
    sun_r = 180
    sun_cx = cx
    sun_cy = horizon_y - 20
    sun_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sun_draw = ImageDraw.Draw(sun_layer)
    # Outer glow layer (large, soft)
    for i, r in enumerate(range(sun_r + 80, sun_r, -8)):
        a = 10 + i * 3
        sun_draw.ellipse(
            [sun_cx - r, sun_cy - r, sun_cx + r, sun_cy + r],
            fill=(*accent, a),
        )
    # Core sun
    sun_draw.ellipse(
        [sun_cx - sun_r, sun_cy - sun_r, sun_cx + sun_r, sun_cy + sun_r],
        fill=(*accent, 240),
    )
    # Scanlines cut into the sun for retrowave look
    for i in range(sun_r * 2):
        band_y = sun_cy - sun_r + i
        if i % 14 < 5:
            sun_draw.line(
                [sun_cx - sun_r, band_y, sun_cx + sun_r, band_y],
                fill=(0, 0, 0, 180),
                width=1,
            )
    # Blur the sun layer slightly for that neon bloom
    sun_blur = sun_layer.filter(ImageFilter.GaussianBlur(radius=3))
    img.paste(sun_blur, (0, 0), sun_blur)


def apply_vignette(img: Image.Image, strength: float = 0.55) -> None:
    """Darken corners via a multiply blend with a radial mask."""
    w, h = img.size
    cx, cy = w / 2, h / 2
    max_r = math.hypot(cx, cy)

    mask = Image.new("L", (w, h), 0)
    mpx = mask.load()
    assert mpx is not None
    for y in range(h):
        for x in range(w):
            r = math.hypot(x - cx, y - cy) / max_r
            v = int(255 * min(1.0, r ** 2) * strength)
            mpx[x, y] = v

    dark = Image.new("RGB", (w, h), (0, 0, 0))
    img_rgba = img.convert("RGBA")
    dark_rgba = dark.convert("RGBA")
    dark_rgba.putalpha(mask)
    img_rgba.paste(dark_rgba, (0, 0), dark_rgba)
    out = img_rgba.convert("RGB")
    img.paste(out)


def generate(
    out_path: Path,
    inner: tuple[int, int, int],
    outer: tuple[int, int, int],
    grid_color: tuple[int, int, int],
    grid_step: int,
    accent_color: tuple[int, int, int],
) -> None:
    print(f"  → {out_path.name}")
    img = radial_gradient(inner, outer)

    horizon_y = int(H * 0.62)

    # Grid: perspective grid below horizon, subtle orthogonal grid above
    draw_grid(img, grid_color, grid_step, alpha=40)
    draw_perspective_grid(img, grid_color, horizon_y, alpha=90)

    # Horizon + sun
    draw_horizon_and_sun(img, accent_color, grid_color, horizon_y)

    # Vignette
    apply_vignette(img, strength=0.5)

    img.save(out_path, "JPEG", quality=92, optimize=True)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: generate_wallpapers.py <output_dir>", file=sys.stderr)
        return 2
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)

    variants = [
        ("01-neon-grid.jpg",    BG1, BG0,   CYAN,    64, MAGENTA),
        ("02-tron-horizon.jpg", BG2, BG0,   CYAN,    80, CYAN),
        ("03-sunset-wave.jpg",  BG1, BG0,   MAGENTA, 72, HOTPINK),
        ("04-orbital-grid.jpg", BG2, BG1,   VIOLET,  48, CYAN),
        ("05-neon-void.jpg",    BG0, BLACK, CYAN,    96, MINT),
    ]
    for name, inner, outer, grid, step, accent in variants:
        generate(out_dir / name, inner, outer, grid, step, accent)

    print(f"\n  ✓ {len(variants)} wallpapers generated in {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
