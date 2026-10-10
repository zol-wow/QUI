from pathlib import Path
import math
import struct

size, width, samples = 32, 2048, 16
pixels = bytearray(width * size * 4)
for tile in range(64):
    radius = tile % 16 + 1
    stroke = tile // 16
    for y in range(radius):
        for x in range(radius):
            coverage = 0
            for sy in range(samples):
                for sx in range(samples):
                    dx = radius - x - (sx + 0.5) / samples
                    dy = radius - y - (sy + 0.5) / samples
                    distance = math.hypot(dx, dy)
                    coverage += distance <= radius and (stroke == 0 or distance >= radius - stroke)
            offset = (y * width + tile * size + x) * 4
            pixels[offset:offset + 4] = bytes((255, 255, 255, round(255 * coverage / samples ** 2)))
header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, width, size, 32, 0x28)
path = Path(__file__).resolve().parents[1] / 'assets/appearance/RoundedSurfaceStrokes.tga'
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(header + pixels)
print(path)
