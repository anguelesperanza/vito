#!/usr/bin/env python3
"""Write placeholder LiveArea images for a project.

    python tools/make_livearea.py <project folder> "Title" [--color RRGGBB]

Creates, inside <project folder>/sce_sys/:

    icon0.png                        128 x 128   the bubble on the home screen
    pic0.png                         960 x 544   shown while the app loads
    livearea/contents/bg.png         840 x 500   LiveArea background
    livearea/contents/startup.png    280 x 158   the "gate" picture you press to start
    livearea/contents/template.xml               which images the LiveArea uses

build.bat packs the whole sce_sys folder into the .vpk when it exists.

The Vita is strict about these files: each PNG must have exactly the size
above and be 8-bit indexed colour (a palette), not truecolour. A bubble whose
images break that rule fails to install or shows as a blank icon. This script
writes them that way; if you replace them with your own art, convert it the
same way (for example with `pngquant 256`).

Requires Pillow (`pip install pillow`). Existing files are not overwritten
unless --force is given.
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont

TEMPLATE = """<?xml version="1.0" encoding="utf-8"?>
<livearea style="a1" format-ver="01.00" content-rev="1">
  <livearea-background>
    <image>bg.png</image>
  </livearea-background>
  <gate>
    <startup-image>startup.png</startup-image>
  </gate>
</livearea>
"""


def font(size):
    for name in ("segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def shade(rgb, f):
    return tuple(max(0, min(255, int(c * f))) for c in rgb)


def picture(w, h, rgb, title, text_size):
    img = Image.new("RGB", (w, h), shade(rgb, 0.25))
    d = ImageDraw.Draw(img)
    # diagonal bands
    step = max(8, h // 6)
    for i in range(-h, w + h, step * 2):
        d.polygon([(i, 0), (i + step, 0), (i + step - h, h), (i - h, h)], fill=shade(rgb, 0.35))
    # a simple match-box mark: a rounded box and a stripe
    m = min(w, h)
    bx, by, bs = w // 2 - m // 4, h // 2 - m // 4 - (m // 10 if title else 0), m // 2
    d.rounded_rectangle([bx, by, bx + bs, by + bs], radius=bs // 8, fill=rgb, outline=shade(rgb, 1.6), width=max(2, m // 60))
    d.rectangle([bx, by + bs * 2 // 3, bx + bs, by + bs * 2 // 3 + bs // 8], fill=shade(rgb, 0.45))
    if title:
        f = font(text_size)
        tw = d.textlength(title, font=f)
        d.text(((w - tw) / 2, by + bs + m // 24), title, font=f, fill=(255, 255, 255))
    return img


def save_indexed(img, path, force):
    if os.path.exists(path) and not force:
        print("kept   ", path)
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    q = img.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    # Pad the palette to 256 entries. Pillow otherwise writes a picture with few
    # colours as a 4-bit palette, and the requirement is an 8-bit one.
    pal = list(q.getpalette() or [])
    q.putpalette(pal + [0] * (768 - len(pal)))
    q.save(path, bits=8)
    print("wrote  ", path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project")
    ap.add_argument("title")
    ap.add_argument("--color", default="E07020", help="main colour as RRGGBB")
    ap.add_argument("--force", action="store_true", help="overwrite existing files")
    a = ap.parse_args()
    rgb = tuple(int(a.color[i:i + 2], 16) for i in (0, 2, 4))
    sys_dir = os.path.join(a.project, "sce_sys")
    live = os.path.join(sys_dir, "livearea", "contents")

    save_indexed(picture(128, 128, rgb, "", 0), os.path.join(sys_dir, "icon0.png"), a.force)
    save_indexed(picture(960, 544, rgb, a.title, 44), os.path.join(sys_dir, "pic0.png"), a.force)
    save_indexed(picture(840, 500, rgb, a.title, 40), os.path.join(live, "bg.png"), a.force)
    save_indexed(picture(280, 158, rgb, "", 0), os.path.join(live, "startup.png"), a.force)
    tpl = os.path.join(live, "template.xml")
    if not os.path.exists(tpl) or a.force:
        with open(tpl, "w", newline="\n") as f:
            f.write(TEMPLATE)
        print("wrote  ", tpl)


if __name__ == "__main__":
    main()
