"""Draw Media/SkillUpStar.tga, the marker the Profit list puts on a craft that
raises your skill and turns a profit.

The art is generated rather than hand-drawn so it can be adjusted and rebuilt:
change a number here, run `python tools/make_star.py`, commit the result.

WoW loads addon textures as uncompressed 32-bit TGA with power-of-two sides,
which is exactly what this writes. Everything is supersampled 4x4 per pixel,
because a five-pointed star is nothing but diagonal edges and an aliased one
looks like a mistake at 12 pixels tall.
"""

import math
import os
import struct

SIZE = 64
SAMPLES = 4

OUTER = 30.0
INNER = OUTER * 0.42          # classic five-point proportions
RIM = 0.90                    # the fill is this fraction of the full star

# Gold, lit from above: the same accent the rest of the UI is built from at the
# bottom, brightened towards the top so the star reads as metal rather than a
# flat blob.
TOP_FILL = (1.000, 0.925, 0.690)
BOTTOM_FILL = (0.784, 0.643, 0.302)
RIM_COLOR = (0.286, 0.208, 0.075)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, "Media", "SkillUpStar.tga")


def star_points(scale):
    """Ten alternating outer/inner vertices, first point straight up.

    Centred on the bounding box rather than on the geometry: a star pointing up
    reaches further above its centre than below it, and centring on the centre
    leaves it visibly sitting low in its square.
    """
    outer, inner = OUTER * scale, INNER * scale
    cx = SIZE / 2.0
    # Rows run downwards, so the top point is at -90 degrees, and the star is
    # nudged down by half the difference between how far it reaches above its
    # centre and how far below.
    cy = SIZE / 2.0 + (outer - outer * math.cos(math.radians(36))) / 2.0

    points = []
    for index in range(10):
        angle = math.radians(-90 + index * 36)
        radius = outer if index % 2 == 0 else inner
        points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return points


def inside(polygon, x, y):
    """Standard crossing test."""
    result = False
    count = len(polygon)
    for i in range(count):
        ax, ay = polygon[i]
        bx, by = polygon[(i + 1) % count]
        if (ay > y) != (by > y):
            crossing = ax + (y - ay) / (by - ay) * (bx - ax)
            if x < crossing:
                result = not result
    return result


def main():
    full = star_points(1.0)
    core = star_points(RIM)

    pixels = []

    # Bottom-up rows: the orientation a plain TGA declares, and the one every
    # reader agrees on.
    for row in range(SIZE - 1, -1, -1):
        for column in range(SIZE):
            covered = 0
            filled = 0

            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = column + (sx + 0.5) / SAMPLES
                    y = row + (sy + 0.5) / SAMPLES

                    if inside(full, x, y):
                        covered += 1
                        if inside(core, x, y):
                            filled += 1

            total = SAMPLES * SAMPLES
            alpha = covered / total

            if alpha == 0:
                pixels.append(b"\x00\x00\x00\x00")
                continue

            # Vertical gradient across the star's own height, not the image's,
            # so the highlight sits on the top point.
            top = SIZE / 2.0 + (OUTER - OUTER * math.cos(math.radians(36))) / 2.0 - OUTER
            ratio = min(1.0, max(0.0, (row - top) / (OUTER * (1 + math.cos(math.radians(36))))))
            lit = tuple(
                TOP_FILL[i] * (1 - ratio) + BOTTOM_FILL[i] * ratio for i in range(3)
            )

            share = filled / max(1, covered)
            color = tuple(lit[i] * share + RIM_COLOR[i] * (1 - share) for i in range(3))

            blue, green, red = (
                int(round(color[2] * 255)),
                int(round(color[1] * 255)),
                int(round(color[0] * 255)),
            )
            pixels.append(bytes((blue, green, red, int(round(alpha * 255)))))

    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,      # no id field
        0,      # no colour map
        2,      # uncompressed true-colour
        0, 0, 0,
        0, 0,   # origin
        SIZE, SIZE,
        32,     # bits per pixel
        8,      # eight alpha bits, origin bottom-left
    )

    os.makedirs(os.path.dirname(TARGET), exist_ok=True)
    with open(TARGET, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(pixels))

    print("wrote %s (%d bytes)" % (TARGET, os.path.getsize(TARGET)))


if __name__ == "__main__":
    main()
