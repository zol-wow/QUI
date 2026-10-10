from pathlib import Path
import struct

root = Path(__file__).resolve().parents[1] / 'assets' / 'appearance'
root.mkdir(exist_ok=True)
width, height = 32, 64
header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)

for name in ['Satin', 'SatinIcon']:
    pixels = bytearray()
    for y in range(height):
        position = y / (height - 1)
        if name == 'Satin':
            value = 1 - 0.06 * position / 0.3 if position <= 0.3 else 0.94 - 0.13 * (position - 0.3) / 0.7
            channel = round(value * 255)
            pixel = bytes((channel, channel, channel, 255))
        else:
            if position <= 0.3:
                channel = 255
                alpha = 0.19 - 0.155 * position / 0.3
            else:
                fraction = (position - 0.3) / 0.7
                channel = round(255 * (1 - fraction))
                alpha = 0.035 + 0.155 * fraction
            pixel = bytes((channel, channel, channel, round(alpha * 255)))
        pixels.extend(pixel * width)
    (root / (name + '.tga')).write_bytes(header + pixels)
    assert len(header + pixels) == 18 + width * height * 4

print('Generated native Satin fill and icon finish (32 × 64, RGBA TGA).')
