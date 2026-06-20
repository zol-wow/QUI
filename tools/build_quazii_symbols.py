#!/usr/bin/env python3
"""Draw original symbol glyphs into Quazii.ttf (arrows, checks, stars, suits...).

Quazii ships full Latin + Cyrillic but is sparse in the symbol blocks (verified
via the cmap). The WoW FontAlphabet enum has no "symbol" member, so these
codepoints classify as roman and cannot fall back to a system font at render
time -- the only fix is baking glyphs into the roman TTF. Outlines below are
original geometric contours tuned to the font's condensed-bold weight; no other
font is used as a source. Running --bake repeatedly is idempotent for glyphs and
cmap (only the head fontRevision bumps).

  python3 tools/build_quazii_symbols.py --preview   # render PNG, no file change
  python3 tools/build_quazii_symbols.py --bake      # write assets/Quazii.ttf
"""
import math
import os
import sys

from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen

SRC = "assets/Quazii.ttf"
PREVIEW_PNG = "tools/preview/quazii_symbols.png"

# Drawing box (1000 upm). Baseline 0 -> cap top ~700, matching the bold weight.
L, R = 90, 610
B, T = 0, 700
MX = (L + R) // 2        # 350
MY = (B + T) // 2        # 350
H = 70                   # half shaft thickness
HH = 165                 # half arrow-head height
HD = 200                 # arrow-head depth
ADV = 700


# --- contour primitives -----------------------------------------------------
def _area(pts):
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        a += x0 * y1 - x1 * y0
    return a / 2.0


def _emit(pen, pts):
    pts = [(int(round(x)), int(round(y))) for x, y in pts]
    pen.moveTo(pts[0])
    for p in pts[1:]:
        pen.lineTo(p)
    pen.closePath()


def _poly(pen, pts):
    # Filled exterior contour -> force clockwise (TrueType non-zero union).
    if _area(pts) > 0:
        pts = list(reversed(pts))
    _emit(pen, pts)


def _hole(pen, pts):
    # Counter / hole -> force counter-clockwise.
    if _area(pts) < 0:
        pts = list(reversed(pts))
    _emit(pen, pts)


def _seg(pen, p0, p1, width):
    x0, y0 = p0
    x1, y1 = p1
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / ln * width / 2.0, dx / ln * width / 2.0
    _poly(pen, [(x0 + nx, y0 + ny), (x1 + nx, y1 + ny),
                (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)])


def _circle_pts(cx, cy, r, n=48):
    return [(cx + r * math.cos(2 * math.pi * i / n),
             cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def _circle(pen, cx, cy, r, n=48):
    _poly(pen, _circle_pts(cx, cy, r, n))


def _ring(pen, cx, cy, r, w, n=48):
    _poly(pen, _circle_pts(cx, cy, r, n))
    _hole(pen, _circle_pts(cx, cy, r - w, n))


def _fit(raw, box, margin=40):
    xs = [p[0] for p in raw]
    ys = [p[1] for p in raw]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    bx0, by0, bx1, by1 = box
    s = min((bx1 - bx0 - 2 * margin) / (maxx - minx),
            (by1 - by0 - 2 * margin) / (maxy - miny))
    ox = (bx0 + bx1) / 2 - s * (minx + maxx) / 2
    oy = (by0 + by1) / 2 - s * (miny + maxy) / 2
    return [(x * s + ox, y * s + oy) for x, y in raw]


def _heart_raw(n=80):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x, y))
    return pts


# --- arrows (batch 1) -------------------------------------------------------
def right_arrow(pen):
    _poly(pen, [(L, MY - H), (R - HD, MY - H), (R - HD, MY + H), (L, MY + H)])
    _poly(pen, [(R - HD, MY - HH), (R, MY), (R - HD, MY + HH)])


def left_arrow(pen):
    _poly(pen, [(L + HD, MY - H), (R, MY - H), (R, MY + H), (L + HD, MY + H)])
    _poly(pen, [(L + HD, MY - HH), (L, MY), (L + HD, MY + HH)])


def up_arrow(pen):
    _poly(pen, [(MX - H, B), (MX + H, B), (MX + H, T - HD), (MX - H, T - HD)])
    _poly(pen, [(MX - HH, T - HD), (MX, T), (MX + HH, T - HD)])


def down_arrow(pen):
    _poly(pen, [(MX - H, T), (MX + H, T), (MX + H, B + HD), (MX - H, B + HD)])
    _poly(pen, [(MX - HH, B + HD), (MX, B), (MX + HH, B + HD)])


def left_right_arrow(pen):
    _poly(pen, [(L + HD, MY - H), (R - HD, MY - H), (R - HD, MY + H), (L + HD, MY + H)])
    _poly(pen, [(L + HD, MY - HH), (L, MY), (L + HD, MY + HH)])
    _poly(pen, [(R - HD, MY - HH), (R, MY), (R - HD, MY + HH)])


def double_arrow(pen):
    cw, ct, hh = 150, 120, HH
    for x0 in (290, 460):
        _poly(pen, [(x0, MY - hh), (x0 + cw, MY), (x0, MY + hh),
                    (x0 - ct, MY + hh), (x0 + cw - ct, MY), (x0 - ct, MY - hh)])


# --- checks / triangles (batch 1) -------------------------------------------
def check(pen):
    vb = (300, 120)
    _seg(pen, vb, (150, 320), 130)
    _seg(pen, vb, (600, 620), 150)


def ballot_x(pen):
    _seg(pen, (160, 150), (590, 600), 135)
    _seg(pen, (160, 600), (590, 150), 135)


def triangle_up(pen):
    _poly(pen, [(130, 150), (R - 20, 150), (MX, 650)])


def triangle_down(pen):
    _poly(pen, [(130, 650), (R - 20, 650), (MX, 150)])


# --- common chat symbols (batch 2) ------------------------------------------
def star(pen):
    cx, cy, ro, ri = 350, 360, 320, 135
    pts = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        r = ro if i % 2 == 0 else ri
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    _poly(pen, pts)


def black_circle(pen):
    _circle(pen, 350, 350, 295)


def white_circle(pen):
    _ring(pen, 350, 350, 295, 110)


def black_square(pen):
    _poly(pen, [(105, 95), (595, 95), (595, 585), (105, 585)])


def white_square(pen):
    _poly(pen, [(105, 95), (595, 95), (595, 585), (105, 585)])
    w = 105
    _hole(pen, [(105 + w, 95 + w), (595 - w, 95 + w), (595 - w, 585 - w), (105 + w, 585 - w)])


def diamond(pen):
    _poly(pen, [(350, 640), (560, 350), (350, 60), (140, 350)])


def heart(pen):
    _poly(pen, _fit(_heart_raw(), (100, 70, 600, 640)))


def spade(pen):
    body = [(x, -y) for x, y in _heart_raw()]      # flip -> point up
    _poly(pen, _fit(body, (110, 200, 590, 650)))
    _poly(pen, [(305, 230), (395, 230), (445, 70), (255, 70)])   # stem


def club(pen):
    r = 122
    _circle(pen, 350, 505, r)
    _circle(pen, 248, 330, r)
    _circle(pen, 452, 330, r)
    _poly(pen, [(318, 360), (382, 360), (440, 80), (260, 80)])   # stem


def point_right(pen):   # 25BA pointer / 25B6 triangle
    _poly(pen, [(L + 40, 130), (R - 20, MY), (L + 40, 570)])


def point_left(pen):    # 25C4 pointer / 25C0 triangle
    _poly(pen, [(R - 40, 130), (L + 20, MY), (R - 40, 570)])


def black_rect(pen):    # 25AC horizontal bar (divider)
    _poly(pen, [(70, MY - 95), (630, MY - 95), (630, MY + 95), (70, MY + 95)])


# codepoint -> (glyph name, drawer)
GLYPHS = {
    # batch 1 (already shipped)
    0x2192: ("uni2192", right_arrow),
    0x2190: ("uni2190", left_arrow),
    0x2191: ("uni2191", up_arrow),
    0x2193: ("uni2193", down_arrow),
    0x2194: ("uni2194", left_right_arrow),
    0x21D2: ("uni21D2", double_arrow),
    0x2713: ("uni2713", check),
    0x2717: ("uni2717", ballot_x),
    0x25B2: ("uni25B2", triangle_up),
    0x25BC: ("uni25BC", triangle_down),
    # batch 2 (common chat symbols)
    0x2605: ("uni2605", star),
    0x25CF: ("uni25CF", black_circle),
    0x25CB: ("uni25CB", white_circle),
    0x25A0: ("uni25A0", black_square),
    0x25A1: ("uni25A1", white_square),
    0x2666: ("uni2666", diamond),
    0x2665: ("uni2665", heart),
    0x2764: ("uni2764", heart),       # heavy black heart -> same shape
    0x2660: ("uni2660", spade),
    0x2663: ("uni2663", club),
    0x2714: ("uni2714", check),       # heavy check mark -> same shape
    0x2716: ("uni2716", ballot_x),    # heavy multiplication x -> same shape
    0x279C: ("uni279C", right_arrow),  # heavy round-tip arrow -> reuse arrow
    # batch 3 (divider/separator decorations -- the ◄▬► family, blank in stock WoW)
    0x25BA: ("uni25BA", point_right),  # black right-pointing pointer
    0x25C4: ("uni25C4", point_left),   # black left-pointing pointer
    0x25AC: ("uni25AC", black_rect),   # black rectangle
    0x25B6: ("uni25B6", point_right),  # black right-pointing triangle
    0x25C0: ("uni25C0", point_left),   # black left-pointing triangle
}


def build(src=SRC):
    font = TTFont(src)
    glyf, hmtx, cmap = font["glyf"], font["hmtx"], font["cmap"]
    order = font.getGlyphOrder()
    for cp, (name, drawfn) in GLYPHS.items():
        pen = TTGlyphPen(None)
        drawfn(pen)
        glyf[name] = pen.glyph()
        hmtx[name] = (ADV, 0)
        if name not in order:
            order.append(name)
        for t in cmap.tables:
            if t.isUnicode():
                t.cmap[cp] = name
    font.setGlyphOrder(order)
    head = font["head"]
    head.fontRevision = round(head.fontRevision + 0.001, 3)
    return font


def preview(font):
    from PIL import Image, ImageDraw, ImageFont
    os.makedirs("tools/preview", exist_ok=True)
    tmp = "tools/preview/_tmp_quazii.ttf"
    font.save(tmp)
    chars = [chr(c) for c in GLYPHS]
    cell, pad, cols = 130, 20, 12
    rows = (len(chars) + cols - 1) // cols
    img = Image.new("RGB", (cell * cols + pad * 2, (cell + 60) * rows + pad), "white")
    d = ImageDraw.Draw(img)
    big = ImageFont.truetype(tmp, 96)
    small = ImageFont.truetype(tmp, 16)
    for i, ch in enumerate(chars):
        cx = pad + (i % cols) * cell
        cy = pad + (i // cols) * (cell + 60)
        d.text((cx + 16, cy + 10), ch, font=big, fill="black")
        d.text((cx + 6, cy + cell + 12), "U+%04X" % ord(ch), font=small, fill="#888")
    img.save(PREVIEW_PNG)
    os.remove(tmp)
    print("wrote", PREVIEW_PNG, "(%d glyphs)" % len(chars))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--preview"
    font = build()
    if mode == "--preview":
        preview(font)
    elif mode == "--bake":
        font.save(SRC)
        print("baked", SRC, "rev", font["head"].fontRevision)
    else:
        sys.exit("usage: --preview | --bake")


if __name__ == "__main__":
    main()
