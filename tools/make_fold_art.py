"""Draw Media/Frame/FoldGem.tga, the gold gem beside a window's close gem that
folds the window down to its plate and opens it back up (UI/FoldWindow.lua).

    python tools/make_fold_art.py

The close gem's shape (tools/make_frame_art.py) in gold, with nothing on its
face: the bar or the plus on it is drawn by the game from plain colour, so
one picture serves both. The same file in all five Blackthornes addons.
"""

import math

import make_frame_art as art


def fold_gem():
    c = 32.0

    def shade(x, y):
        dx, dy = x - c, y - c
        r = math.hypot(dx, dy)
        if r > 31.5:
            return None
        if r > 30.3:
            return art.EDGE + (1.0,)
        if r > 25:
            angle = (math.degrees(math.atan2(dy, dx)) + 360 + 70) % 360 / 360.0
            return art.ramp([(0, art.METAL_HI), (0.25, art.METAL_LO), (0.5, art.hexrgb("#e3c26e")),
                             (0.75, art.METAL_LO), (1, art.METAL_HI)], angle) + (1.0,)
        if r > 23.8:
            return art.hexrgb("#2a1c06") + (1.0,)
        t = math.hypot(dx, dy + 8) / 30.0
        fill = art.ramp([(0, art.hexrgb("#ffe8a3")), (0.45, art.hexrgb("#e0aa3e")),
                         (1, art.hexrgb("#7a5414"))], t)
        # A glint on the top of the gem, as the close gem has.
        shine = max(0.0, 1 - math.hypot(dx / 14.0, (dy + 13) / 6.0))
        fill = art.mix(fill, (1, 1, 1), shine * 0.45)
        return fill + (1.0,)

    art.render("FoldGem", 64, 64, shade)


if __name__ == "__main__":
    fold_gem()
