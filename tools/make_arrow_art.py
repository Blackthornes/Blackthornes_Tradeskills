"""Draw Media/Arrow/*.tga, the guide arrow's slim pill (2026-11-25): a thin
dark glass pill with a gold hairline edge, and on its left a round dark well
where a flat gold chevron turns.

    python -m pip install numpy
    python tools/make_arrow_art.py

The same file in Farmer (goal arrow), Equipment (quest arrow), Pets (beast
arrow), Butler and Tradeskills (way arrows), so the five match. Rerun it
rather than editing the TGAs.

The chevron is flat, so the game turns it with SetRotation: one picture, no
sheet of headings. The step box's small dial (UI/TravelCard.lua) uses the
same chevron and dot.

- Pill.tga, PillEdge.tga: the pill's glass and its hairline edge, white for
  the game to tint, 128 x 64. Drawn in three slices (left end, middle,
  right end), so the pill can be any width.
- Well.tga: the round dark well, coloured, 64 x 64.
- WellEdge.tga: the well's rim, white for the game to tint, 64 x 64.
- Chevron.tga: the gold chevron pointing straight up, coloured, 64 x 64.
- ChevronGlow.tga: a soft white light the shape of the chevron, for the
  game to tint and add behind it, 64 x 64.
- Dot.tga: a soft white dot, shown when the arrow can't point, 32 x 32.
- Check.tga: the green check shown once you are there, 64 x 64.

Shapes are filled by testing SAMPLES x SAMPLES points a pixel, so the edges
are smooth.
"""

import math
import os
import struct

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Arrow")

SAMPLES = 4


def hexrgb(value):
    value = value.lstrip("#")
    return np.array([int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# The house gold and the well's dark glass (the approved mockup).
GOLD_HI = hexrgb("#FFE08A")
GOLD = hexrgb("#F2C14E")
GOLD_LO = hexrgb("#9C7426")
INK = hexrgb("#2a1d06")
WELL_HI = hexrgb("#2a2218")
WELL_LO = hexrgb("#0d0a06")
GREEN = hexrgb("#5EE07A")
EDGE = hexrgb("#050608")


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

def grid(width, height):
    """Sample points, SAMPLES x SAMPLES a pixel, in pixel units."""
    xs = (np.arange(width * SAMPLES) + 0.5) / SAMPLES
    ys = (np.arange(height * SAMPLES) + 0.5) / SAMPLES
    return np.meshgrid(xs, ys)


def shrink(values):
    """Average SAMPLES x SAMPLES blocks."""
    h, w = values.shape[:2]
    k = SAMPLES
    return values.reshape(h // k, k, w // k, k, *values.shape[2:]).mean((1, 3))


def segment_distance(x, y, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = np.clip(((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(x - (ax + t * dx), y - (ay + t * dy))


def inside_polygon(x, y, points):
    """True where (x, y) is inside the polygon, by counting crossings."""
    inside = np.zeros(x.shape, bool)
    count = len(points)
    for i in range(count):
        ax, ay = points[i]
        bx, by = points[(i + 1) % count]
        crosses = (ay > y) != (by > y)
        at = (bx - ax) * (y - ay) / np.where(by - ay == 0, 1e-9, by - ay) + ax
        inside ^= crosses & (x < at)
    return inside


def polygon_edge(x, y, points):
    """Distance from (x, y) to the polygon's outline."""
    count = len(points)
    best = np.full(x.shape, np.inf)
    for i in range(count):
        ax, ay = points[i]
        bx, by = points[(i + 1) % count]
        best = np.minimum(best, segment_distance(x, y, ax, ay, bx, by))
    return best


def blur(alpha, radius):
    """A gaussian blur of a 2D array, edges treated as empty."""
    if radius <= 0:
        return alpha
    taps = int(math.ceil(radius * 3))
    xs = np.arange(-taps, taps + 1)
    kernel = np.exp(-(xs ** 2) / (2 * radius * radius))
    kernel /= kernel.sum()
    padded = np.pad(alpha, taps)
    rows = sum(kernel[i] * padded[:, i:i + alpha.shape[1]] for i in range(len(kernel)))
    return sum(kernel[i] * rows[i:i + alpha.shape[0], :] for i in range(len(kernel)))


def over(top, bottom):
    ta, ba = top[..., 3:4], bottom[..., 3:4]
    a = ta + ba * (1 - ta)
    rgb = (top[..., :3] * ta + bottom[..., :3] * ba * (1 - ta)) / np.maximum(a, 1e-6)
    return np.concatenate([rgb, a], -1)


def image(rgb, alpha):
    """An RGBA image from a colour (or colour per pixel) and an alpha."""
    out = np.zeros(alpha.shape + (4,))
    out[..., :3] = rgb
    out[..., 3] = np.clip(alpha, 0, 1)
    return out


def white(alpha):
    return image(np.ones(3), alpha)


def write(name, picture):
    """An uncompressed 32-bit TGA, rows bottom-up as a plain TGA declares."""
    h, w, _ = picture.shape
    pixels = np.clip(np.round(picture * 255), 0, 255).astype(np.uint8)
    bgra = pixels[::-1][..., [2, 1, 0, 3]]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".tga")
    with open(path, "wb") as handle:
        handle.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8))
        handle.write(bgra.tobytes())
    print("wrote %s (%d bytes)" % (os.path.relpath(path, ROOT), os.path.getsize(path)))


# -----------------------------------------------------------------------------
# The pieces
# -----------------------------------------------------------------------------

PILL_W, PILL_H = 128, 64
# About one game pixel at the pill's height (26), in texture pixels.
PILL_EDGE = 3.0


def pill():
    x, y = grid(PILL_W, PILL_H)
    r = PILL_H / 2
    d = segment_distance(x, y, r, r, PILL_W - r, r) - (r - 0.5)
    write("Pill", white(shrink((d < 0).astype(float))))
    edge = (d < 0) & (d > -PILL_EDGE)
    write("PillEdge", white(shrink(edge.astype(float))))


WELL = 64
# About a game pixel and a half at the well's size (22).
WELL_EDGE = 4.5


def well():
    x, y = grid(WELL, WELL)
    c, r = WELL / 2, WELL / 2 - 0.5
    d = np.hypot(x - c, y - c)
    disc = shrink((d < r).astype(float))
    # Lit from just above the middle, darker toward the rim.
    light = np.clip(np.hypot(x - c, y - WELL * 0.4) / r, 0, 1)
    t = shrink(light)[..., None]
    rgb = WELL_HI * (1 - t) + WELL_LO * t
    # A soft shade just inside the rim.
    rim = shrink(np.clip((d - (r - 7)) / 7, 0, 1))[..., None]
    rgb = rgb * (1 - 0.6 * rim)
    write("Well", image(rgb, disc))
    edge = (d < r) & (d > r - WELL_EDGE)
    write("WellEdge", white(shrink(edge.astype(float))))


# The chevron from the mockup, in its own units: tip up, notch at the back.
CHEVRON = [(0, -10), (8, 8), (0, 3.5), (-8, 8)]
CHEVRON_MIDDLE = -1.0   # halfway between tip and back, so it turns in place


def chevron_points(size, scale):
    c = size / 2
    return [(c + px * scale, c + (py - CHEVRON_MIDDLE) * scale) for px, py in CHEVRON]


def chevron():
    size = 64
    scale = 2.8
    x, y = grid(size, size)
    points = chevron_points(size, scale)
    fill = inside_polygon(x, y, points)
    edge = polygon_edge(x, y, points)
    body = shrink(fill.astype(float))
    line = shrink(((edge < 2.0) & ~fill | (edge < 1.0)).astype(float))
    # Gold from light at the tip to deep at the back.
    top, bottom = points[0][1], points[1][1]
    t = shrink(np.clip((y - top) / (bottom - top), 0, 1))[..., None]
    rgb = np.where(t < 0.55, GOLD_HI + (GOLD - GOLD_HI) * (t / 0.55),
                   GOLD + (GOLD_LO - GOLD) * ((t - 0.55) / 0.45))
    gold = image(rgb, body)
    ink = image(INK, np.clip(line, 0, 1) * 0.9)
    write("Chevron", over(gold, ink))

    # The glow is drawn bigger in the game (CHEVRON + 8), so its shape is
    # smaller here to sit under the chevron.
    glow_scale = scale * 16 / 24
    points = chevron_points(size, glow_scale)
    shape = shrink(inside_polygon(x, y, points).astype(float))
    light = blur(shape, 3.5)
    light = light / max(light.max(), 1e-6)
    write("ChevronGlow", white(light))


def dot():
    size = 32
    x, y = grid(size, size)
    c = size / 2
    d = shrink(np.hypot(x - c, y - c))
    core = np.clip(8.0 - d, 0, 1)
    halo = np.exp(-((d - 6) / 4.0) ** 2) * (d > 6) * 0.55
    write("Dot", white(np.maximum(core, halo)))


# The check from the mockup, in a 20 unit box.
CHECK = [(3, 10.5), (8, 15), (17, 5)]


def check():
    size = 64
    scale = 2.9
    x, y = grid(size, size)
    off = size / 2 - 10 * scale
    points = [(off + px * scale, off + py * scale) for px, py in CHECK]
    d = np.full(x.shape, np.inf)
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        d = np.minimum(d, segment_distance(x, y, ax, ay, bx, by))
    width = 1.5 * scale
    mark = image(GREEN, shrink((d < width).astype(float)))
    rim = image(EDGE, shrink((d < width + 2).astype(float)) * 0.85)
    write("Check", over(mark, rim))


def main():
    pill()
    well()
    chevron()
    dot()
    check()


if __name__ == "__main__":
    main()
