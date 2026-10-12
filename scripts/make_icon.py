#!/usr/bin/env python3
"""Renders the LockIn app icon in the app's neo-brutalist style and writes every size
the macOS AppIcon set needs. Re-run after tweaking; it overwrites in place.

    python3 scripts/make_icon.py

Requires Pillow.
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "LockIn", "Assets.xcassets", "AppIcon.appiconset")
PREVIEW = os.path.join(ROOT, "docs", "icon-preview.png")

# Palette (matches Theme.swift)
PAPER = (0xFF, 0xFB, 0xF0, 255)
BLACK = (0x11, 0x11, 0x11, 255)
CORAL = (0xFF, 0x6B, 0x6B, 255)
YELLOW = (0xFF, 0xD9, 0x3D, 255)
LAVENDER = (0xB8, 0xA9, 0xF5, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)

S = 4  # supersampling factor
SIZE = 1024 * S


def font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf",
        "/usr/share/fonts/opentype/inter/Inter-Black.otf",
        "/System/Library/Fonts/Supplemental/Arial Black.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            return ImageFont.truetype(c, size)
    return ImageFont.load_default()


def rounded_mask(size: int, radius: int) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return m


def slab(w: int, h: int, fill, border: int, shadow: int, angle: float) -> Image.Image:
    """A bordered rectangle with a hard offset shadow, rotated. Returns an RGBA layer."""
    pad = shadow + border * 2
    layer = Image.new("RGBA", (w + pad * 2, h + pad * 2), CLEAR)
    d = ImageDraw.Draw(layer)
    d.rectangle((pad + shadow, pad + shadow, pad + shadow + w, pad + shadow + h), fill=BLACK)
    d.rectangle((pad, pad, pad + w, pad + h), fill=fill, outline=BLACK, width=border)
    return layer.rotate(angle, resample=Image.BICUBIC, expand=True)


def render() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), CLEAR)

    # macOS icon grid: the artwork sits inside ~824/1024 of the canvas.
    inset = int(SIZE * 0.098)
    tile = SIZE - inset * 2
    radius = int(tile * 0.225)

    # Paper tile with dot grid and a heavy black border.
    paper = Image.new("RGBA", (tile, tile), PAPER)
    pd = ImageDraw.Draw(paper)
    spacing = int(tile * 0.052)
    dot = max(2, int(tile * 0.0065))
    y = spacing // 2
    while y < tile:
        x = spacing // 2
        while x < tile:
            pd.ellipse((x - dot, y - dot, x + dot, y + dot), fill=(0x11, 0x11, 0x11, 70))
            x += spacing
        y += spacing

    # Decorative blocks peeking from the corners, like the hero mock.
    pd.rectangle((-tile * 0.05, tile * 0.80, tile * 0.16, tile * 1.05), fill=CORAL, outline=BLACK, width=int(tile * 0.016))
    pd.ellipse((tile * 0.74, tile * 0.10, tile * 0.92, tile * 0.28), fill=LAVENDER, outline=BLACK, width=int(tile * 0.016))

    mask = rounded_mask(tile, radius)
    paper.putalpha(mask)

    # Border: draw a slightly larger black rounded rect underneath.
    border_w = int(tile * 0.028)
    frame = Image.new("RGBA", (tile, tile), CLEAR)
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, tile - 1, tile - 1), radius=radius, fill=BLACK)
    inner = Image.new("RGBA", (tile, tile), CLEAR)
    inner_mask = rounded_mask(tile - border_w * 2, radius - border_w)
    inner_paper = paper.resize((tile - border_w * 2, tile - border_w * 2), Image.LANCZOS)
    inner_paper.putalpha(inner_mask)
    inner.alpha_composite(inner_paper, (border_w, border_w))
    frame.alpha_composite(inner)
    img.alpha_composite(frame, (inset, inset))

    cx, cy = SIZE // 2, SIZE // 2

    # The padlock body: a yellow slab, tilted, with a hard shadow.
    body_w, body_h = int(tile * 0.62), int(tile * 0.46)
    body = slab(body_w, body_h, YELLOW, border=int(tile * 0.03), shadow=int(tile * 0.05), angle=-6)
    body_pos = (cx - body.width // 2 + int(tile * 0.01), cy - body.height // 2 + int(tile * 0.13))
    body_center = (body_pos[0] + body.width // 2 - int(tile * 0.02), body_pos[1] + body.height // 2 - int(tile * 0.02))

    # The shackle: a thick black arc sitting on top of the body.
    shackle = Image.new("RGBA", (SIZE, SIZE), CLEAR)
    sd = ImageDraw.Draw(shackle)
    sw = int(tile * 0.085)
    r = int(tile * 0.19)
    scx, scy = body_center[0] + int(tile * 0.02), body_pos[1] + int(tile * 0.06)
    sd.arc((scx - r, scy - r, scx + r, scy + r), start=180, end=360, fill=BLACK, width=sw)
    sd.rectangle((scx - r, scy, scx - r + sw, scy + int(tile * 0.14)), fill=BLACK)
    sd.rectangle((scx + r - sw, scy, scx + r, scy + int(tile * 0.14)), fill=BLACK)
    shackle = shackle.rotate(-6, resample=Image.BICUBIC, center=(scx, scy))
    img.alpha_composite(shackle)

    img.alpha_composite(body, body_pos)

    # The keyhole is a timer: white dial, coral progress wedge, black hand.
    dial_r = int(tile * 0.13)
    dial = Image.new("RGBA", (SIZE, SIZE), CLEAR)
    dd = ImageDraw.Draw(dial)
    dcx, dcy = body_center
    dd.ellipse((dcx - dial_r, dcy - dial_r, dcx + dial_r, dcy + dial_r), fill=WHITE, outline=BLACK, width=int(tile * 0.025))
    wedge_r = dial_r - int(tile * 0.03)
    dd.pieslice((dcx - wedge_r, dcy - wedge_r, dcx + wedge_r, dcy + wedge_r), start=-90, end=30, fill=CORAL)
    hand_w = int(tile * 0.022)
    dd.line((dcx, dcy, dcx, dcy - wedge_r + int(tile * 0.01)), fill=BLACK, width=hand_w)
    ang = math.radians(30)
    dd.line((dcx, dcy, dcx + math.cos(ang) * (wedge_r - int(tile * 0.01)), dcy + math.sin(ang) * (wedge_r - int(tile * 0.01))), fill=BLACK, width=hand_w)
    dd.ellipse((dcx - hand_w, dcy - hand_w, dcx + hand_w, dcy + hand_w), fill=BLACK)
    dial = dial.rotate(-6, resample=Image.BICUBIC, center=(dcx, dcy))
    img.alpha_composite(dial)

    # Little "LOCK IN" tag, coral, slightly tilted the other way.
    f = font(int(tile * 0.075))
    text = "LOCK IN"
    tw, th = f.getbbox(text)[2:]
    tag_w, tag_h = tw + int(tile * 0.06), th + int(tile * 0.05)
    tag = slab(tag_w, tag_h, CORAL, border=int(tile * 0.02), shadow=int(tile * 0.03), angle=4)
    tag_layer = Image.new("RGBA", (tag_w + int(tile * 0.2), tag_h + int(tile * 0.2)), CLEAR)
    td = ImageDraw.Draw(tag_layer)
    pad = int(tile * 0.1)
    td.rectangle((pad + int(tile * 0.03), pad + int(tile * 0.03), pad + int(tile * 0.03) + tag_w, pad + int(tile * 0.03) + tag_h), fill=BLACK)
    td.rectangle((pad, pad, pad + tag_w, pad + tag_h), fill=CORAL, outline=BLACK, width=int(tile * 0.02))
    td.text((pad + tag_w / 2, pad + tag_h / 2 - int(tile * 0.004)), text, font=f, fill=BLACK, anchor="mm")
    tag_layer = tag_layer.rotate(4, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(tag_layer, (cx - tag_layer.width // 2 - int(tile * 0.10), inset + int(tile * 0.72) - tag_layer.height // 2))
    _ = tag  # kept for parity with slab(); the tag is drawn inline so the text can be centered precisely

    return img


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    big = render().resize((1024, 1024), Image.LANCZOS)

    sizes = {
        "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
    }
    for name, px in sizes.items():
        im = big if px == 1024 else big.resize((px, px), Image.LANCZOS)
        im.save(os.path.join(OUT, name), "PNG")

    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    # Preview sheet: 512, 128, 32 side by side on paper.
    sheet = Image.new("RGBA", (512 + 128 + 64 + 32 + 160, 560), PAPER)
    x = 40
    for px in (512, 128, 64, 32):
        im = big.resize((px, px), Image.LANCZOS)
        sheet.alpha_composite(im, (x, (560 - px) // 2))
        x += px + 32
    sheet.save(PREVIEW, "PNG")
    print(f"wrote {len(sizes)} icons to {OUT}\npreview: {PREVIEW}")


if __name__ == "__main__":
    sys.exit(main())
