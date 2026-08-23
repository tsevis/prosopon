#!/usr/bin/env python3
"""Draw Prosopon's icon, and crop the About panel's banner out of the splash.

Run from the repository root:

    python3 scripts/make_assets.py

Produces, all of them checked in so a build needs neither Pillow nor this script:

    Resources/Prosopon.icns                     the app bundle's icon
    Sources/ProsoponReview/Resources/AppMark.png        256 px, the About lockup
    Sources/ProsoponReview/Resources/AboutBanner.jpg    1280 x 500, the About key art

The mark is the specification drawn literally: the 16 x 16 grid of a 2048 canvas,
the five lines that pass through the three fixed targets, and a disc on each of
(512, 512), (1536, 512) and (1024, 1664).  Nothing about it is decorative -- it is
what the program does, which is the only honest thing to put on the front of it.

The pink is measured, not chosen.  #E80F9E is the grid ink sampled off
documents/assets/Splash.jpg, which is where the whole palette comes from.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - a developer aid, not part of the build
    sys.exit("Pillow is needed to regenerate the assets: pip3 install Pillow")

ROOT = Path(__file__).resolve().parent.parent
SPLASH = ROOT / "documents" / "assets" / "Splash.jpg"
RESOURCES = ROOT / "Resources"
BUNDLED = ROOT / "Sources" / "ProsoponReview" / "Resources"

BRAND = (232, 15, 158)          # the splash's grid ink
GROUND = (23, 17, 26)           # a near-black carrying a trace of the same hue

CANVAS = 2048.0                 # the coordinate space the targets are quoted in
TARGETS = [(512, 512), (1536, 512), (1024, 1664)]
CROSSHAIR_X = (512, 1024, 1536)
CROSSHAIR_Y = (512, 1664)


def draw_icon(size: int) -> Image.Image:
    """One square of the icon, at any size, drawn rather than resampled.

    Drawn at each size instead of scaled from one master because the hairlines are
    a pixel or two wide: a 1024 px grid resampled to 32 px loses them entirely and
    leaves three dots floating on an empty plate.
    """
    scale = size / 1024.0
    plate = 832 * scale                     # the art box inside Apple's 1024 grid
    radius = int(0.2237 * size)
    origin = (size - plate) / 2
    cell = plate / 16.0

    def at(x: float, y: float) -> tuple[float, float]:
        return (origin + x / CANVAS * plate, origin + y / CANVAS * plate)

    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(image).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=GROUND
    )

    # The grid and the discs go on their own layer so the rounded plate underneath
    # keeps its clean edge whatever the lines do.
    ink = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pen = ImageDraw.Draw(ink)

    faint = max(1, round(3 * scale))
    for i in range(1, 16):
        offset = origin + i * cell
        pen.line([(origin, offset), (origin + plate, offset)], fill=BRAND + (54,), width=faint)
        pen.line([(offset, origin), (offset, origin + plate)], fill=BRAND + (54,), width=faint)

    strong = max(1, round(9 * scale))
    for x in CROSSHAIR_X:
        pen.line([at(x, 0), at(x, CANVAS)], fill=BRAND + (255,), width=strong)
    for y in CROSSHAIR_Y:
        pen.line([at(0, y), at(CANVAS, y)], fill=BRAND + (255,), width=strong)

    ring = max(1, round(7 * scale))
    for x, y in TARGETS:
        cx, cy = at(x, y)
        r = cell * 1.18
        pen.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BRAND + (255,))
        pen.ellipse(
            [cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 235), width=ring
        )

    image.alpha_composite(ink)
    return image


def write_icns(destination: Path) -> None:
    iconset = destination.with_suffix(".iconset")
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)

    for base in (16, 32, 128, 256, 512):
        draw_icon(base).save(iconset / f"icon_{base}x{base}.png")
        draw_icon(base * 2).save(iconset / f"icon_{base}x{base}@2x.png")

    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(destination)], check=True
    )
    shutil.rmtree(iconset)
    print(f"  {destination.relative_to(ROOT)}")


def write_banner(destination: Path, width: int = 1280, height: int = 500) -> None:
    """The About panel's 640 x 250 key art, at 2x, cropped out of the splash.

    A 2.56:1 band cannot hold all three targets: the discs span 1382 px of a 2048
    square, and a full-width band of that aspect is 800 px tall.  So the crop keeps
    the eye line -- both eyes, the grid, and the seam where the two half-faces meet
    -- and lets the mouth fall below the edge.  The eyes are the constraint the
    whole program is built around, and they are what reads at banner size.
    """
    if not SPLASH.exists():
        sys.exit(f"missing key art: {SPLASH}")

    splash = Image.open(SPLASH).convert("RGB")
    side = splash.width
    band = round(side * height / width)
    # Placed so the eye line sits 30% down the band rather than dead centre, which
    # leaves the darker lower face under the lockup where the type goes.
    top = round(512 / CANVAS * side - band * 0.30)
    top = max(0, min(top, splash.height - band))

    splash.crop((0, top, side, top + band)) \
        .resize((width, height), Image.LANCZOS) \
        .save(destination, "JPEG", quality=90, optimize=True)
    print(f"  {destination.relative_to(ROOT)}")


def main() -> int:
    RESOURCES.mkdir(parents=True, exist_ok=True)
    BUNDLED.mkdir(parents=True, exist_ok=True)

    print("Drawing:")
    write_icns(RESOURCES / "Prosopon.icns")

    mark = BUNDLED / "AppMark.png"
    draw_icon(256).save(mark)
    print(f"  {mark.relative_to(ROOT)}")

    write_banner(BUNDLED / "AboutBanner.jpg")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
