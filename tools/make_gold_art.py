"""Draw the two small pieces of Goblin Gold's bar: Media/Frame/GoldGem.tga, the
gold diamond at each end of the bar and on each tenth, and
Media/Frame/GoldSparkle.tga, the four-point star that breathes at the end of
the gold and twinkles along it.

The art is generated rather than hand-drawn so it can be adjusted and rebuilt:
change a number here, run `python tools/make_gold_art.py`, commit the result.
Never edit the TGAs by hand.

WoW loads addon textures as uncompressed 32-bit TGA with power-of-two sides,
which is exactly what this writes. Edges are supersampled 4x4 per pixel.
"""

import math
import os
import struct

SIZE = 32
SAMPLES = 4

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAME = os.path.join(ROOT, "Media", "Frame")

# The gem: gold lit from the top left, a pale rim and a bright facet, the same
# gold the rest of the UI is built from.
GEM_LIGHT = (1.000, 0.925, 0.690)
GEM_DARK = (0.560, 0.400, 0.140)
GEM_RIM = (1.000, 0.910, 0.660)
GEM_RADIUS = 14.0
GEM_RIM_WIDTH = 1.6

# The sparkle is near white, so the code can tint it and add it as light.
SPARK_ARMS = 15.0
SPARK_WAIST = 2.2


def write_tga(path, rows):
    """`rows` runs bottom to top, each a list of (r, g, b, a) floats 0..1."""
    pixels = []
    for row in rows:
        for r, g, b, a in row:
            pixels.append(bytes((
                int(round(max(0, min(1, b)) * 255)),
                int(round(max(0, min(1, g)) * 255)),
                int(round(max(0, min(1, r)) * 255)),
                int(round(max(0, min(1, a)) * 255)),
            )))
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0, 0, 2,
        0, 0, 0,
        0, 0,
        SIZE, SIZE,
        32,
        8,
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(pixels))
    print("wrote %s (%d bytes)" % (path, os.path.getsize(path)))


def sample(shade):
    """Average `shade(x, y)` over each pixel; y runs downwards from the top."""
    rows = []
    for row in range(SIZE - 1, -1, -1):
        line = []
        for column in range(SIZE):
            total = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = column + (sx + 0.5) / SAMPLES - SIZE / 2.0
                    y = row + (sy + 0.5) / SAMPLES - SIZE / 2.0
                    r, g, b, a = shade(x, y)
                    total[0] += r * a
                    total[1] += g * a
                    total[2] += b * a
                    total[3] += a
            count = SAMPLES * SAMPLES
            alpha = total[3] / count
            if alpha <= 0:
                line.append((0, 0, 0, 0))
            else:
                line.append((total[0] / total[3], total[1] / total[3], total[2] / total[3], alpha))
        rows.append(line)
    return rows


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def gem(x, y):
    # A diamond: |x| + |y| under the radius.
    reach = abs(x) + abs(y)
    if reach > GEM_RADIUS:
        return (0, 0, 0, 0)
    if reach > GEM_RADIUS - GEM_RIM_WIDTH:
        return GEM_RIM + (1,)
    # Lit from the top left: the upper left facets bright, the lower right deep.
    light = 0.5 + 0.5 * (-(x + y) / GEM_RADIUS)
    color = mix(GEM_DARK, GEM_LIGHT, max(0, min(1, light)))
    # A small bright facet near the top.
    if abs(x + 3) + abs(y + 4) < 3.2:
        color = mix(color, (1, 1, 1), 0.7)
    return color + (1,)


def sparkle(x, y):
    # Four thin arms that taper to points, and a soft round core.
    distance = math.hypot(x, y)
    arm = 0.0
    for ax, ay in ((abs(x), abs(y)), (abs(y), abs(x))):
        if ax < SPARK_ARMS:
            width = SPARK_WAIST * (1 - ax / SPARK_ARMS)
            if ay < width:
                arm = max(arm, (1 - ay / max(width, 0.01)) * (1 - ax / SPARK_ARMS) ** 0.5)
    core = max(0.0, 1 - distance / 5.0)
    alpha = max(arm, core)
    if alpha <= 0:
        return (0, 0, 0, 0)
    return (1.0, 0.97, 0.86, alpha)


def main():
    write_tga(os.path.join(FRAME, "GoldGem.tga"), sample(gem))
    write_tga(os.path.join(FRAME, "GoldSparkle.tga"), sample(sparkle))


if __name__ == "__main__":
    main()
