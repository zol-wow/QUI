from pathlib import Path
import math
import struct

size, width, samples = 32, 1024, 8
pixels = bytearray(width * size * 4)
for tile in range(17):
    for y in range(size):
        for x in range(size):
            coverage = 0
            for sy in range(samples):
                for sx in range(samples):
                    dx = 1 - (x + (sx + 0.5) / samples) / size
                    dy = 1 - (y + (sy + 0.5) / samples) / size
                    distance = math.hypot(dx, dy)
                    coverage += distance <= 1 and (tile == 0 or distance >= 1 - 1 / tile)
            offset = (y * width + tile * size + x) * 4
            pixels[offset:offset + 4] = bytes((255, 255, 255, round(255 * coverage / samples ** 2)))
header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, width, size, 32, 0x28)
path = Path(__file__).resolve().parents[1] / 'assets/appearance/RoundedSurface.tga'
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(header + pixels)
assert pixels[3] == 0
assert pixels[(size - 1) * width * 4 + (size - 1) * 4 + 3] == 255
assert pixels[(size - 1) * width * 4 + (size * 8 + size - 1) * 4 + 3] == 0
print(path)
