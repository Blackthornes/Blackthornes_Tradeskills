"""Draw Media/Arrow/*.tga, the arrow's dial: a gold ring with four gems lying
back like a compass on the ground, and the gold blade that floats over it.

    python -m pip install numpy
    python tools/make_arrow_art.py

The same file in Farmer (goal arrow), Equipment (quest arrow) and Pets
(beast arrow), so the three dials match. Rerun it rather than editing the
TGAs.

The dial is seen from above at a slant (ELEVATION degrees), so it cannot be
turned in the game the flat way: the blade is drawn once for each of TURNS
headings, the light staying put, and the game shows the frame nearest the
way to go (SetTexCoord on one texture, no drawing at run time).

- Ring.tga: the tilted dial, 256 x 256.
- Blade.tga: TURNS frames of the blade and its shadow on the glass, 128 x
  128 each, COLUMNS a row, frame 0 pointing straight ahead and the rest
  turning anticlockwise. Coloured: the game shows it untinted.
- BladeGlow.tga: the same frames as a soft white light, 64 x 64 each, for
  the game to tint and add over the dial.

Each frame covers exactly the ring's square, so the two line up when both
fill the dial. A small triangle rasterizer, supersampled SAMPLES x SAMPLES.
"""

import math
import os
import struct

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Arrow")

SAMPLES = 4
TURNS = 64
COLUMNS = 8
ELEVATION = 52          # degrees above the ground the dial is seen from
DISTANCE = 7.0          # how far the eye is, for a touch of perspective
VIEW = 3.70             # world units across the square
LIFT = 0.30             # how high the blade floats over the glass


def hexrgb(value):
    value = value.lstrip("#")
    return np.array([int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# The house gold (make_frame_art.py), the dial's gems and its dark glass.
METAL_HI = hexrgb("#fbe6a6")
METAL = hexrgb("#c8a44d")
METAL_MID = hexrgb("#b08b3c")
METAL_LO = hexrgb("#5b4416")
DEEP = hexrgb("#2a1c06")
EDGE = hexrgb("#050608")
GOLD_HI = hexrgb("#FFF4CF")
GEM = hexrgb("#4fc8ff")
GEM_HI = hexrgb("#e6f8ff")
GEM_LO = hexrgb("#0b3a66")
GLASS = hexrgb("#14161c")
GLASS_HI = hexrgb("#2f3542")


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


# From the front left, above: the light never turns with the blade.
LIGHT = unit([-0.55, -0.35, 0.78])


def ramp(stops, t):
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(t, [s[0] for s in stops], [s[1][c] for s in stops])
    return out


GOLD_RAMP = [(0, DEEP), (0.3, METAL_LO), (0.55, METAL_MID), (0.8, METAL), (1, METAL_HI)]


# -----------------------------------------------------------------------------
# Drawing triangles
# -----------------------------------------------------------------------------

class Mesh:
    def __init__(self):
        self.tris = []

    def tri(self, a, b, c, kind, normals=None):
        a, b, c = (np.asarray(p, float) for p in (a, b, c))
        if normals is None:
            n = np.cross(b - a, c - a)
            length = np.linalg.norm(n)
            if length < 1e-12:
                return
            normals = (n / length,) * 3
        self.tris.append((a, b, c) + tuple(np.asarray(n, float) for n in normals) + (kind,))

    def quad(self, a, b, c, d, kind):
        self.tri(a, b, c, kind)
        self.tri(a, c, d, kind)


def camera(size):
    """World to pixels (x right, y down) and depth, for a square `size` wide."""
    e = math.radians(ELEVATION)
    se, ce = math.sin(e), math.cos(e)
    scale = size / VIEW

    def project(p):
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        depth = y * ce - z * se
        k = DISTANCE / (DISTANCE + depth)
        return np.stack([size / 2 + x * scale * k, size / 2 - (y * se + z * ce) * scale * k, depth], -1)

    return project, unit([0, -ce, se])


def raster(mesh, size, shade):
    """Draw `mesh` into an RGBA float image `size` square, nearest wins."""
    project, view = camera(size)
    depth = np.full((size, size), np.inf)
    image = np.zeros((size, size, 4))
    for a, b, c, na, nb, nc, kind in mesh.tris:
        p = project(np.stack([a, b, c]))
        x0, x1 = max(int(p[:, 0].min()), 0), min(int(math.ceil(p[:, 0].max())), size - 1)
        y0, y1 = max(int(p[:, 1].min()), 0), min(int(math.ceil(p[:, 1].max())), size - 1)
        if x1 < x0 or y1 < y0:
            continue
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1] + 0.5
        (ax, ay, _), (bx, by, _), (cx, cy, _) = p
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        w0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
        w1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
        w2 = 1 - w0 - w1
        z = w0 * p[0, 2] + w1 * p[1, 2] + w2 * p[2, 2]
        here = depth[y0:y1 + 1, x0:x1 + 1]
        win = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6) & (z < here - 1e-7)
        if not win.any():
            continue
        n = unit(w0[..., None] * na + w1[..., None] * nb + w2[..., None] * nc)[win]
        at = (w0[..., None] * a + w1[..., None] * b + w2[..., None] * c)[win]
        here[win] = z[win]
        patch = image[y0:y1 + 1, x0:x1 + 1]
        patch[win, :3] = shade(kind, n, at, view)
        patch[win, 3] = 1
    return image


def shade(kind, n, at, view):
    lit = np.clip(n @ LIGHT, 0, 1)
    shine = np.clip(n @ unit(LIGHT + view), 0, 1)
    if kind in ("blade", "bladeside"):
        t = 0.16 + 0.74 * lit
        if kind == "bladeside":
            t = t * 0.5
        return np.clip(ramp(GOLD_RAMP, t) + (shine ** 60)[:, None] * GOLD_HI * 0.45, 0, 1)
    if kind == "rim":
        t = 0.1 + 0.8 * lit
        return np.clip(ramp(GOLD_RAMP, t) + (shine ** 24)[:, None] * GOLD_HI * 0.8, 0, 1)
    if kind == "rimside":
        return ramp([(0, EDGE), (0.4, DEEP), (1, METAL_LO)], 0.05 + 0.45 * lit)
    if kind == "line":
        return np.tile(GOLD_HI, (len(n), 1)) * (0.75 + 0.25 * lit)[:, None]
    if kind == "glass":
        r = np.hypot(at[:, 0], at[:, 1]) / 1.4
        t = np.clip(0.55 + 0.45 * at[:, 1] / 1.4, 0, 1)
        band = np.exp(-((at[:, 1] - 0.6 * at[:, 0] - 0.55) ** 2) / 0.05) * 0.10
        return np.clip(ramp([(0, GLASS), (1, GLASS_HI)], t * (1 - 0.4 * r)) + band[:, None], 0, 1)
    if kind == "gem":
        return np.clip(ramp([(0, GEM_HI), (0.3, GEM), (1, GEM_LO)], 1 - lit) + (shine ** 50)[:, None], 0, 1)
    return np.zeros((len(n), 3))


# -----------------------------------------------------------------------------
# Images
# -----------------------------------------------------------------------------

def shrink(image, k):
    """Average k x k blocks, colour weighted by coverage."""
    h, w, _ = image.shape
    a = image[..., 3].reshape(h // k, k, w // k, k).mean((1, 3))
    rgb = (image[..., :3] * image[..., 3:4]).reshape(h // k, k, w // k, k, 3).mean((1, 3))
    rgb = np.where(a[..., None] > 0, rgb / np.maximum(a[..., None], 1e-6), 0)
    return np.concatenate([rgb, a[..., None]], -1)


def over(top, bottom):
    ta, ba = top[..., 3:4], bottom[..., 3:4]
    a = ta + ba * (1 - ta)
    rgb = (top[..., :3] * ta + bottom[..., :3] * ba * (1 - ta)) / np.maximum(a, 1e-6)
    return np.concatenate([rgb, a], -1)


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


def grow(alpha):
    """Each pixel takes the largest of its 3 x 3 neighbours."""
    padded = np.pad(alpha, 1)
    h, w = alpha.shape
    return np.max([padded[y:y + h, x:x + w] for y in range(3) for x in range(3)], axis=0)


def outlined(image):
    """A dark line round the shape, as the house art has."""
    rim = np.zeros_like(image)
    rim[..., :3] = EDGE
    rim[..., 3] = grow(image[..., 3]) * 0.95
    return over(image, rim)


def write(name, image):
    """An uncompressed 32-bit TGA, rows bottom-up as a plain TGA declares."""
    h, w, _ = image.shape
    pixels = np.clip(np.round(image * 255), 0, 255).astype(np.uint8)
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

RADIUS, RIM_WIDTH, RIM_HEIGHT, RIM_DEPTH = 1.55, 0.30, 0.16, 0.16


def sphere(mesh, centre, r, kind, segments=12):
    centre = np.asarray(centre, float)

    def point(t, p):
        return np.array([math.sin(t) * math.cos(p), math.sin(t) * math.sin(p), math.cos(t)])

    for i in range(segments):
        t0, t1 = math.pi * i / segments, math.pi * (i + 1) / segments
        for j in range(segments * 2):
            p0, p1 = math.pi * j / segments, math.pi * (j + 1) / segments
            a, b, c, d = point(t0, p0), point(t1, p0), point(t1, p1), point(t0, p1)
            mesh.tri(centre + a * r, centre + b * r, centre + c * r, kind, (a, b, c))
            mesh.tri(centre + a * r, centre + c * r, centre + d * r, kind, (a, c, d))


def ring_mesh(segments=128, profile=10):
    """Dark glass in a rounded gold rim, with a gold line inside the rim and
    a gem at each corner. The glass is the ground, z = 0."""
    mesh = Mesh()
    inner = RADIUS - RIM_WIDTH / 2
    up = ((0, 0, 1),) * 3

    def at(a, r, z):
        return np.array([r * math.cos(a), r * math.sin(a), z])

    def rim(a, b):
        r = RADIUS - (RIM_WIDTH / 2) * math.cos(b)
        nr, nz = -math.cos(b) / (RIM_WIDTH / 2), math.sin(b) / RIM_HEIGHT
        length = math.hypot(nr, nz)
        return at(a, r, RIM_HEIGHT * math.sin(b)), np.array(
            [nr / length * math.cos(a), nr / length * math.sin(a), nz / length])

    for i in range(segments):
        a0, a1 = 2 * math.pi * i / segments, 2 * math.pi * (i + 1) / segments
        mesh.tri((0, 0, 0), at(a0, inner, 0), at(a1, inner, 0), "glass", up)
        for k in range(profile):
            b0, b1 = math.pi * k / profile, math.pi * (k + 1) / profile
            (p00, n00), (p01, n01) = rim(a0, b0), rim(a0, b1)
            (p10, n10), (p11, n11) = rim(a1, b0), rim(a1, b1)
            mesh.tri(p00, p01, p11, "rim", (n00, n01, n11))
            mesh.tri(p00, p11, p10, "rim", (n00, n11, n10))
        # The outside of the rim, so its near edge shows how thick it is.
        o = RADIUS + RIM_WIDTH / 2
        n0, n1 = at(a0, 1, 0), at(a1, 1, 0)
        mesh.tri(at(a0, o, 0), at(a0, o, -RIM_DEPTH), at(a1, o, -RIM_DEPTH), "rimside", (n0, n0, n1))
        mesh.tri(at(a0, o, 0), at(a1, o, -RIM_DEPTH), at(a1, o, 0), "rimside", (n0, n1, n1))
        line = inner - 0.06
        mesh.tri(at(a0, line, 0.004), at(a0, line + 0.025, 0.004), at(a1, line + 0.025, 0.004), "line", up)
        mesh.tri(at(a0, line, 0.004), at(a1, line + 0.025, 0.004), at(a1, line, 0.004), "line", up)
    for degrees in (45, 135, 225, 315):
        a = math.radians(degrees)
        sphere(mesh, (RADIUS * math.cos(a), RADIUS * math.sin(a), RIM_HEIGHT * 0.7), 0.15, "gem")
    return mesh


# The blade's outline seen from above, tip ahead (+y): a tip, two wings and a
# notch in the tail, as the flat arrow had. Its top rises to a peak.
OUTLINE = [(0, 1.08), (0.84, -0.92), (0, -0.44), (-0.84, -0.92)]
EDGE_HEIGHT, PEAK = 0.07, 0.30


def turned(x, y, z, heading):
    c, s = math.cos(heading), math.sin(heading)
    return np.array([x * c - y * s, x * s + y * c, z])


def blade_mesh(heading):
    mesh = Mesh()
    peak = turned(0, 0.02, LIFT + PEAK, heading)
    top = [turned(x, y, LIFT + EDGE_HEIGHT, heading) for x, y in OUTLINE]
    low = [turned(x, y, LIFT, heading) for x, y in OUTLINE]
    for i in range(4):
        j = (i + 1) % 4
        mesh.tri(peak, top[i], top[j], "blade")
        mesh.quad(top[i], low[i], low[j], top[j], "bladeside")
    # Facing the right way whatever the winding: tops up, sides out.
    middle = turned(0, 0.02, 0, heading)
    fixed = Mesh()
    for a, b, c, n, _, _, kind in mesh.tris:
        if kind == "blade" and n[2] < 0:
            n = -n
        if kind == "bladeside" and np.dot(n[:2], ((a + b + c) / 3 - middle)[:2]) < 0:
            n = -n
        fixed.tris.append((a, b, c, n, n, n, kind))
    return fixed


def shadow_mesh(heading):
    """The blade cast down the light onto the glass."""
    points = []
    for x, y in OUTLINE:
        p = turned(x, y, LIFT + EDGE_HEIGHT, heading)
        points.append(p - LIGHT * (p[2] / LIGHT[2]) + np.array([0, 0, 0.002]))
    mesh = Mesh()
    mesh.tri(points[0], points[1], points[2], "shadow")
    mesh.tri(points[0], points[2], points[3], "shadow")
    return mesh


def ring():
    size = 256
    write("Ring", shrink(raster(ring_mesh(), size * SAMPLES, shade), SAMPLES))


def blades():
    size, glow_size = 128, 64
    rows = TURNS // COLUMNS
    sheet = np.zeros((rows * size, COLUMNS * size, 4))
    glows = np.zeros((rows * glow_size, COLUMNS * glow_size, 4))
    for frame in range(TURNS):
        heading = 2 * math.pi * frame / TURNS
        blade = outlined(shrink(raster(blade_mesh(heading), size * SAMPLES, shade), SAMPLES))
        shadow = shrink(raster(shadow_mesh(heading), size * SAMPLES, shade), SAMPLES)
        shadow[..., :3] = 0
        shadow[..., 3] = blur(shadow[..., 3], size / 90) * 0.6
        row, column = divmod(frame, COLUMNS)
        sheet[row * size:(row + 1) * size, column * size:(column + 1) * size] = over(blade, shadow)

        light = blade[..., 3].reshape(glow_size, 2, glow_size, 2).mean((1, 3))
        light = np.clip(blur(light, glow_size / 26) * 1.6, 0, 1)
        cell = glows[row * glow_size:(row + 1) * glow_size, column * glow_size:(column + 1) * glow_size]
        cell[..., :3] = 1
        cell[..., 3] = light
    write("Blade", sheet)
    write("BladeGlow", glows)


def main():
    ring()
    blades()


if __name__ == "__main__":
    main()
