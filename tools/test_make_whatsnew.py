"""tools/make_whatsnew.py: what goes into the in-game What's New window.
The same test is in all five addons.

    python tools/test_make_whatsnew.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_whatsnew as tool  # noqa: E402

NEWS = """# News

Words about the file, which never ship.

## 1.3.0

- Newest thing, with a "quote" and a back\\slash.
- A **bold** bullet with `code` that runs
  onto a second line.

Thanks Ana and Bob for the ideas and reports!

## 1.2.1

- Fixed a thing.

## 1.2.0

- Middle thing.

## 1.1.0

- Too old to ship.
"""

failures = []


def check(label, ok, detail=""):
    if not ok:
        failures.append("%s %s" % (label, detail))


found = tool.sections(NEWS)
check("every section read", [v for v, _ in found] == ["1.3.0", "1.2.1", "1.2.0", "1.1.0"], found)
check("bullets only, wrapped lines joined, markdown taken out",
      found[0][1] == ['Newest thing, with a "quote" and a back\\slash.',
                      "A bold bullet with code that runs onto a second line."], found[0][1])

lua = tool.render(NEWS)
check("the thanks line never ships", "Ana" not in lua and "Thanks" not in lua, lua)
check("the intro never ships", "never ship" not in lua, lua)
check("only the newest sections", '"1.2.0"' in lua and '"1.1.0"' not in lua, lua)
check("quotes and backslashes escaped", '\\"quote\\"' in lua and "back\\\\slash" in lua, lua)
check("sets ns.WHATS_NEW", "ns.WHATS_NEW = {" in lua, lua)
check("up to date is no problem", tool.problems(NEWS, lua) == [])
check("stale is a problem", tool.problems("## 9.9.9\n\n- x\n\n" + NEWS, lua) != [])

# Fixes and other changes go to Discord, never into the window.
SPLIT = """## 2.1.0

- Fixed only.
- Another fix.

## 2.0.1

Fixes:

- Fixed only, under the line.

## 2.0.0

- A feature.

Fixes and changes:

- A fix that stays out
  over two lines.

Thanks Ana!

## 1.9.0

- Older feature.

**Fixes:**

- Old fix.
"""
split = tool.sections(SPLIT)
check("a section of only fixes is left out",
      [v for v, _ in split] == ["2.1.0", "2.0.0", "1.9.0"], split)
check("bullets after the fixes line stay out",
      split[1][1] == ["A feature."] and split[2][1] == ["Older feature."], split)
check("bullets with no fixes line all count", split[0][1] == ["Fixed only.", "Another fix."], split)
check("the next heading starts features again", "Old fix." not in tool.render(SPLIT))

notes = tool.style_notes("## 1.0.0\n\n- Got loot? Now you can see it \u2014 seamlessly!\n- Plain words.\n")
check("advert wording is noted", len(notes) == 5 and all("Plain" not in n for n in notes), notes)

# This repository's own file, as the release check reads it.
for problem in tool.problems():
    failures.append("this repo: " + problem)

if failures:
    for failure in failures:
        print("FAIL " + failure)
    sys.exit(1)
print("make_whatsnew: all checks passed")
