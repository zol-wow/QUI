#!/usr/bin/env python3
"""Assert Quazii.ttf keeps its existing coverage AND gains the symbol glyphs."""
from fontTools.ttLib import TTFont

f = TTFont("assets/Quazii.ttf")
cmap = set()
for t in f["cmap"].tables:
    cmap |= set(t.cmap.keys())


def block(a, b):
    return sum(1 for c in range(a, b + 1) if c in cmap)


# Existing coverage floors (pre-bake measurement).
assert block(0x20, 0x7E) == 95, "Basic Latin regressed"
assert block(0xA0, 0xFF) == 96, "Latin-1 regressed"
assert block(0x100, 0x17F) == 128, "Latin Ext-A regressed"
assert block(0x400, 0x4FF) >= 255, "Cyrillic regressed"

NEW = [
    # batch 1: arrows / checks / triangles
    0x2190, 0x2191, 0x2192, 0x2193, 0x2194, 0x21D2, 0x2713, 0x2717, 0x25B2, 0x25BC,
    # batch 2: common chat symbols
    0x2605, 0x25CF, 0x25CB, 0x25A0, 0x25A1, 0x2666, 0x2665, 0x2764, 0x2660, 0x2663,
    0x2714, 0x2716, 0x279C,
    # batch 3: divider/separator decorations (the reported ◄▬► blanks)
    0x25BA, 0x25C4, 0x25AC, 0x25B6, 0x25C0,
]
missing = [hex(c) for c in NEW if c not in cmap]
assert not missing, "symbol glyphs missing: " + ",".join(missing)

print("check_quazii_coverage: PASS  (cmap entries:", len(cmap), ")")
