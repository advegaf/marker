#!/usr/bin/env python3
"""The Marker icon: a highlighter stroke laid across two lines of text.

Says "marker" literally and "reading" visually, and survives being shrunk to
16pt in a Finder sidebar, which is where most icons turn to mush. Writes the
1024 master plus the ten mac slots into AppIcon.appiconset, and a contact sheet
so legibility at small sizes is checked by eye rather than assumed.

    python3 Scripts/make_appicon.py
"""
from PIL import Image, ImageDraw, ImageFilter
import json
import os

S = 1024

# macOS icon grid: the artwork is not system masked in the asset catalog path, so
# it draws its own rounded square, inset from the canvas to leave room for the
# shadow the grid expects.
CONTENT = 824
INSET = (S - CONTENT) // 2

INK_TOP = (28, 30, 36)
INK_BOTTOM = (16, 17, 21)
ACCENT = (255, 176, 46)
ACCENT_DEEP = (243, 138, 22)
TEXT_BRIGHT = (236, 238, 243)
TEXT_DIM = (118, 124, 138)

SS = 4  # supersample factor, so every curve is resolved before downscaling


def squircle(size, radius_ratio=0.235, samples=2048):
    """A superellipse mask, which is the shape macOS actually uses.

    A plain rounded rectangle reads subtly wrong next to system icons: the
    curvature jumps where the arc meets the straight edge instead of easing into
    it. The exponent here is the standard continuous-corner approximation.
    """
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    n = 5.0
    half = size / 2.0
    points = []
    for i in range(samples + 1):
        t = i / samples * 2 * 3.141592653589793
        import math
        cos_t, sin_t = math.cos(t), math.sin(t)
        x = half * (abs(cos_t) ** (2 / n)) * (1 if cos_t >= 0 else -1)
        y = half * (abs(sin_t) ** (2 / n)) * (1 if sin_t >= 0 else -1)
        points.append((half + x, half + y))
    draw.polygon(points, fill=255)
    return mask


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        grad.putpixel((0, y), tuple(
            int(round(top[c] + (bottom[c] - top[c]) * t)) for c in range(3)
        ))
    return grad.resize((size, size), Image.BILINEAR)


def rounded_bar(draw, x, y, w, h, fill):
    draw.rounded_rectangle([x, y, x + w, y + h], radius=h / 2, fill=fill)


def build_master():
    big = CONTENT * SS

    # Ground.
    ground = vertical_gradient(big, INK_TOP, INK_BOTTOM)

    # Text lines. Three of them, the middle one longest, so the block reads as a
    # paragraph rather than as an abstract pattern. The middle line is drawn again
    # after the slab, because a highlighter you cannot read through is just a bar.
    lines = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lines)
    bar_h = int(big * 0.072)
    gap = int(big * 0.118)
    left = int(big * 0.185)
    widths = [0.560, 0.630, 0.395]
    top = int(big * 0.305)
    for index, ratio in enumerate(widths):
        if index == 1:
            continue
        rounded_bar(ld, left, top + index * gap, int(big * ratio), bar_h, TEXT_DIM + (255,))
    ground = Image.alpha_composite(ground.convert("RGBA"), lines)

    # The highlighter slab, angled very slightly the way a hand draws it, with a
    # soft leading edge so it reads as wet ink rather than as a pasted rectangle.
    slab = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    sd = ImageDraw.Draw(slab)
    slab_h = int(big * 0.175)
    slab_y = top + gap - int(slab_h * 0.30)
    # Held inside the squircle rather than bled to its edge: a stroke that runs off
    # both sides reads as a clipped rectangle, not as something someone drew.
    slab_left, slab_right = int(big * 0.115), int(big * 0.885)
    sd.polygon(
        [
            (slab_left, slab_y + int(big * 0.012)),
            (slab_right, slab_y - int(big * 0.012)),
            (slab_right, slab_y + slab_h - int(big * 0.012)),
            (slab_left, slab_y + slab_h + int(big * 0.012)),
        ],
        fill=ACCENT + (238,),
    )
    # A denser core, offset down, the way a chisel tip leaves more pigment on the
    # trailing edge of a stroke.
    sd.polygon(
        [
            (slab_left, slab_y + int(slab_h * 0.55)),
            (slab_right, slab_y + int(slab_h * 0.30)),
            (slab_right, slab_y + slab_h - int(big * 0.012)),
            (slab_left, slab_y + slab_h + int(big * 0.012)),
        ],
        fill=ACCENT_DEEP + (130,),
    )
    slab = slab.filter(ImageFilter.GaussianBlur(big * 0.004))
    art = Image.alpha_composite(ground, slab)

    # The highlighted line, on top of the ink in the ground colour, so it reads as
    # text seen through the highlighter. At 16pt this is the whole mark: an amber
    # bar with a dark line running through it.
    over = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    rounded_bar(od, left, top + gap, int(big * widths[1]), bar_h, (18, 19, 24, 236))
    art = Image.alpha_composite(art, over)

    # Mask to the squircle.
    mask = squircle(big)
    art.putalpha(mask)
    art = art.resize((CONTENT, CONTENT), Image.LANCZOS)

    # Canvas, with the soft contact shadow the macOS grid leaves room for.
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 78), (INSET, INSET + int(S * 0.010)), art.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.014))
    canvas = Image.alpha_composite(canvas, shadow)
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

    # Contact sheet: every slot at its real pixel size on a neutral ground, so the
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
