#!/usr/bin/env python3
"""Bake a TrueType font into the atlas lib/gfx/text.odin draws from.

    python tools/make_font.py <font.ttf> <size in pixels> <output name> [--chars latin1]

Writes <output name>.png (white glyphs on transparent, 8-bit RGBA) and
<output name>.fnt (where each glyph is). Load both with gfx.load_font.

    --chars ascii     32..126 (the default)
    --chars latin1    ASCII plus 160..255 (accented Western European letters)
    --chars FILE      every character that appears in the UTF-8 text file FILE

Text is sharpest at the baked size, so bake one atlas per size that matters.
Check the font's licence before shipping an atlas made from it: an atlas is a
copy of the font's shapes. DejaVu, Liberation, Noto and other OFL fonts are fine.

.fnt layout (little-endian):
    header   "VFNT", u16 version (1), u16 glyph count, i16 line height,
             i16 ascent, u16 pixel size, u16 zero
    glyphs   sorted by code point, 20 bytes each:
             u32 code point, u16 x, y, w, h in the atlas,
             i16 offset x (pen to left edge), i16 offset y (baseline up to top edge),
             i16 advance in 1/64 pixel, u16 zero

Requires Pillow (`pip install pillow`).
"""
import argparse
import os
import struct

from PIL import Image, ImageDraw, ImageFont

PADDING = 1  # empty pixels around each glyph, so neighbours do not bleed when scaled


def characters(spec):
    if spec == "ascii":
        return [chr(c) for c in range(32, 127)]
    if spec == "latin1":
        return [chr(c) for c in list(range(32, 127)) + list(range(160, 256))]
    with open(spec, encoding="utf-8") as f:
        found = set(f.read()) | {"?", " "}
    return sorted(c for c in found if c >= " ")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("font")
    parser.add_argument("size", type=int)
    parser.add_argument("output")
    parser.add_argument("--chars", default="ascii")
    args = parser.parse_args()

    font = ImageFont.truetype(args.font, args.size)
    ascent, descent = font.getmetrics()
    chars = characters(args.chars)

    # Measure every glyph. getbbox is relative to the pen at the top of the
    # ascent, so the baseline is `ascent` pixels below its origin.
    glyphs = []
    for ch in chars:
        left, top, right, bottom = font.getbbox(ch)
        w, h = max(0, right - left), max(0, bottom - top)
        advance = round(font.getlength(ch) * 64)
        glyphs.append({"ch": ch, "w": w, "h": h, "left": left, "top": top, "advance": advance})

    # Pack in rows, tallest first, into the smallest power-of-two square that fits.
    order = sorted(range(len(glyphs)), key=lambda i: -glyphs[i]["h"])
    side = 64
    while True:
        x = y = row = 0
        fits = True
        for i in order:
            g = glyphs[i]
            w, h = g["w"] + 2 * PADDING, g["h"] + 2 * PADDING
            if x + w > side:
                x, y, row = 0, y + row, 0
            if y + h > side or w > side:
                fits = False
                break
            g["x"], g["y"] = x + PADDING, y + PADDING
            x += w
            row = max(row, h)
        if fits:
            break
        side *= 2
        if side > 4096:
            raise SystemExit("the glyphs do not fit in a 4096 x 4096 atlas; use a smaller size or fewer characters")

    # Draw: coverage goes into alpha, colour stays white, so tinting works.
    coverage = Image.new("L", (side, side), 0)
    draw = ImageDraw.Draw(coverage)
    for g in glyphs:
        if g["w"] and g["h"]:
            draw.text((g["x"] - g["left"], g["y"] - g["top"]), g["ch"], font=font, fill=255)
    atlas = Image.merge("RGBA", (Image.new("L", (side, side), 255),) * 3 + (coverage,))

    out_dir = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(out_dir, exist_ok=True)
    atlas.save(args.output + ".png")

    data = struct.pack("<4sHHhhHH", b"VFNT", 1, len(glyphs), ascent + descent, ascent, args.size, 0)
    for g in sorted(glyphs, key=lambda g: ord(g["ch"])):
        data += struct.pack("<IHHHHhhhH", ord(g["ch"]), g["x"], g["y"], g["w"], g["h"],
                            g["left"], ascent - g["top"], g["advance"], 0)
    with open(args.output + ".fnt", "wb") as f:
        f.write(data)
    print(f"wrote {args.output}.png ({side} x {side}) and {args.output}.fnt ({len(glyphs)} glyphs, "
          f"line height {ascent + descent}, ascent {ascent})")


if __name__ == "__main__":
    main()
