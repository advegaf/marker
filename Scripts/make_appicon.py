#!/usr/bin/env python3
"""The Marker icon: a paragraph reduced to three strokes, one of them marked.

Written to sit beside minus and wave rather than beside a stock app icon. The
family rule those two share is monochrome, one reductive idea, sharp geometry,
no decorative gradient and no skeuomorphism. minus carries its single accent as
RGB dispersion at the edges of a bone bar; the same technique is used here on
the middle stroke, so the highlighter reads as split light rather than as a
coloured rectangle painted over text.

    python3 Scripts/make_appicon.py
"""
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import json
import math
import os

S = 1024

# macOS still ships app icons through the classic appiconset, confirmed by
# /System/Applications carrying CFBundleIconName and an AppIcon.icns, so the
# artwork is not system masked and draws its own rounded square. Wave fills
# nearly the whole canvas, so this does too.
CONTENT = 964
INSET = (S - CONTENT) // 2

OBSIDIAN = (16, 16, 16)
BONE = (255, 253, 249)

# The dispersion triad, matched to minus/scripts/make_appicon.py.
RED = (235, 45, 45)
BLUE = (45, 125, 235)
GREEN = (45, 225, 45)

SS = 4  # supersample, so edges and the superellipse resolve before downscaling

# Three strokes reading as a paragraph. Unequal lengths, the middle one longest
# and marked, so the block is a paragraph rather than a pattern.
#
# Proportions are set by the 16pt case, not by how the 1024 master looks. At 16
# pixels the whole block gets about 13 of them, so a stroke needs roughly an
# eighth of the height and the gaps need to be wider than the strokes or the
# three merge into a grey smear. Everything larger then takes care of itself.
BAR_HEIGHT = 0.115
BAR_GAP = 0.200
BAR_LEFT = 0.170
BAR_WIDTHS = (0.540, 0.660, 0.400)
BLOCK_TOP = 0.243


def squircle_mask(size, samples=2048):
    """A superellipse, which is the curve macOS actually uses.

    A plain rounded rectangle reads subtly wrong beside system icons: curvature
    jumps where the arc meets the straight edge instead of easing into it.
    """
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    n = 5.0
    half = size / 2.0
    points = []
    for i in range(samples + 1):
        t = i / samples * 2 * math.pi
        cos_t, sin_t = math.cos(t), math.sin(t)
        x = half * (abs(cos_t) ** (2 / n)) * (1 if cos_t >= 0 else -1)
        y = half * (abs(sin_t) ** (2 / n)) * (1 if sin_t >= 0 else -1)
        points.append((half + x, half + y))
    draw.polygon(points, fill=255)
    return mask


def bar_rect(big, index):
    height = int(big * BAR_HEIGHT)
    y = int(big * BLOCK_TOP) + index * int(big * BAR_GAP)
    x = int(big * BAR_LEFT)
    width = int(big * BAR_WIDTHS[index])
    return [x, y, x + width, y + height]


def clone(big, index, colour, dx, dy):
    """One offset colour copy of the marked bar, for additive dispersion."""
    layer = Image.new("RGB", (big, big), (0, 0, 0))
    draw = ImageDraw.Draw(layer)
    left, top, right, bottom = bar_rect(big, index)
    draw.rectangle([left + dx, top + dy, right + dx, bottom + dy], fill=colour)
    return layer


def build_master():
    big = CONTENT * SS
    art = Image.new("RGB", (big, big), OBSIDIAN)

    # The marked stroke: additive RGB copies, offset and softened so they read as
    # dispersion rather than as misregistration, then the bone bar laid on top so
    # the copies survive only at the fringes.
    glow = Image.new("RGB", (big, big), (0, 0, 0))
    spread = int(big * 0.009)
    glow = ImageChops.add(glow, clone(big, 1, RED, -spread, -int(spread * 0.75)))
    glow = ImageChops.add(glow, clone(big, 1, BLUE, spread, int(spread * 0.75)))
    glow = ImageChops.add(glow, clone(big, 1, GREEN, 0, int(spread * 1.1)))
    glow = glow.filter(ImageFilter.GaussianBlur(big * 0.005))
    art = ImageChops.add(art, glow)

    draw = ImageDraw.Draw(art)
    # Sharp corners. minus and wave both cut their forms square; a rounded bar
    # here would soften the one thing the icon is made of.
    for index in range(3):
        draw.rectangle(bar_rect(big, index), fill=BONE)

    art = art.convert("RGBA")
    art.putalpha(squircle_mask(big))
    art = art.resize((CONTENT, CONTENT), Image.LANCZOS)

    # No drop shadow. minus has none, wave has none, and a shadow is exactly the
    # decoration the family rule excludes.
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas.paste(art, (INSET, INSET), art)
    return canvas


SLOTS = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "Marker", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out, exist_ok=True)

    master = build_master()
    images = []
    for size, scale in SLOTS:
        pixels = size * scale
        name = f"icon_{size}x{size}.png" if scale == 1 else f"icon_{size}x{size}@2x.png"
        master.resize((pixels, pixels), Image.LANCZOS).save(os.path.join(out, name))
        images.append({
            "idiom": "mac",
            "size": f"{size}x{size}",
            "scale": f"{scale}x",
            "filename": name,
        })

    with open(os.path.join(out, "Contents.json"), "w") as handle:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, handle, indent=2)

    # Contact sheet on a neutral ground, every slot at its real pixel size, so the
    # 16pt case is judged rather than hoped for.
    sheet_w, sheet_h = 900, 220
    sheet = Image.new("RGB", (sheet_w, sheet_h), (238, 239, 242))
    x = 24
    for size, scale in SLOTS:
        pixels = size * scale
        tile = master.resize((pixels, pixels), Image.LANCZOS)
        sheet.paste(tile, (x, (sheet_h - pixels) // 2), tile)
        x += pixels + 24
    sheet.save(os.path.join(root, "QA", "evidence", "_appicon-contact-sheet.png"))

    print(f"wrote {len(SLOTS)} slots to {out}")


if __name__ == "__main__":
    main()
