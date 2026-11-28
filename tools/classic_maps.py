"""Moves Classic's map spots onto Forever's own maps.

Classic's spots (Data/LearnSpots.lua, Data/VendorSpots.lua) are numbers on a
zone's map. Most of Forever's zone maps cover the same ground as Classic's,
so the numbers point at the same place. Mulgore's does not: Forever's map
reaches further on every side, so a Classic spot read on it lands north and
west of where the NPC stands. Show the way sent players to Tepa and the other
Thunder Bluff trainers just north of the city (2026-11-17).

The bounds below are where each map starts and ends in the world, as
{ left, right, top, bottom } in world Y (east to west) and world X (north to
south). Forever's come from its client's UiMapAssignment table. Classic's
are the ones its numbers were measured on; every vendor the game showed on
Forever (Data/ForeverVendorSpots.lua) lands within a tenth of a step of its
Classic spot once moved, Thunder Bluff's too. Every other zone the game
showed vendors in already matched, so only Mulgore is listed.

make_learn_spots.py and make_vendor_spots.py call forever_spot() on every
spot they write. To move the spots in files written before that:

    python tools/classic_maps.py

It changes only Mulgore's numbers, and only once: a moved file says so in
its header and is left alone after that.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# zone: (Classic's bounds, Forever's bounds)
MOVED = {
    "Mulgore": (
        (2047.917, -3089.583, -272.917, -3697.917),
        (2479.167, -3675.0, 266.666, -3835.416),
    ),
}

MARK = "-- Mulgore's spots are on Forever's Mulgore map (tools/classic_maps.py)."


def forever_spot(zone, x, y):
    """(x, y) on Forever's map of the zone, from Classic's x, y on it."""
    if zone not in MOVED:
        return x, y
    (cl, cr, ct, cb), (fl, fr, ft, fb) = MOVED[zone]
    world_y = cl - x / 100 * (cl - cr)
    world_x = ct - y / 100 * (ct - cb)
    return (fl - world_y) / (fl - fr) * 100, (ft - world_x) / (ft - fb) * 100


def _moved(x, y, style):
    nx, ny = forever_spot("Mulgore", float(x), float(y))
    nx, ny = round(nx, 1), round(ny, 1)
    return style(nx), style(ny)


def _keep_dot(v):
    return f"{v:.1f}"


def _plain(v):
    return str(int(v)) if v == int(v) else str(v)


NUM = r"(-?\d+(?:\.\d+)?)"
PATTERNS = {
    # Data/LearnSpots.lua: trainers and vendors, written with a dot always.
    "Data/LearnSpots.lua": (
        [
            re.compile(r'(\{ "[^"]*", "Mulgore", )' + NUM + ", " + NUM),
            re.compile(r'(\["[^"]*\|Mulgore"\] = \{ )' + NUM + ", " + NUM),
        ],
        _keep_dot,
    ),
    # Data/VendorSpots.lua: whole numbers written without one.
    "Data/VendorSpots.lua": (
        [re.compile(r'(\{ "[^"]*", "Mulgore", )' + NUM + ", " + NUM)],
        _plain,
    ),
}


def move_file(rel):
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    if MARK in text:
        return 0
    patterns, style = PATTERNS[rel]
    count = 0

    def swap(m):
        nonlocal count
        count += 1
        x, y = _moved(m.group(2), m.group(3), style)
        return f"{m.group(1)}{x}, {y}"

    for pattern in patterns:
        text = pattern.sub(swap, text)
    text = text.replace("\nlocal _, ns = ...", "\n" + MARK + "\n\nlocal _, ns = ...", 1)
    path.write_text(text, encoding="utf-8", newline="\n")
    return count


def main():
    for rel in PATTERNS:
        print(f"{rel}: {move_file(rel)} Mulgore spot(s) moved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
