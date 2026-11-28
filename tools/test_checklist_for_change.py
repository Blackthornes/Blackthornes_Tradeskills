"""The change checklist reads its items and picks the ones a change touches.

    python tools/test_checklist_for_change.py

Also checks that every item in this repo's Docs/change-checklist.md has a
trigger that compiles, a Check line and a Why line. The same file lives in all
five addons.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import checklist_for_change as checklist  # noqa: E402

SAMPLE = """# Change checklist

Some words before the first item are ignored.

## Shared file changed
Files: ^UI/SharedWindow\\.lua$
Check: Copy the change to the other four addons.
Why: A fix landed in one addon only.

## Sound without Mute
Lines: PlaySound
Check: Ask ns.Muted() first.
  This line carries on the one above.
Why: A new sound played while muted.

## No trigger
Check: Never printed.
"""


def main():
    bad = 0

    def expect(ok, what):
        nonlocal bad
        if not ok:
            bad += 1
            print("FAIL: " + what)

    items = checklist.read_items(SAMPLE)
    expect(len(items) == 2, "two items with triggers, got %d" % len(items))
    expect(items[1]["Check"].endswith("carries on the one above."), "a wrapped line joins its field")
    expect(checklist.matches(items[0], ["UI/SharedWindow.lua"], []), "a changed path matches")
    expect(not checklist.matches(items[0], ["UI/Main.lua"], []), "another path does not")
    expect(checklist.matches(items[1], [], ["  PlaySound(123)"]), "a changed line matches")
    expect(not checklist.matches(items[1], ["UI/Main.lua"], ["x = 1"]), "other lines do not")

    with open(checklist.CHECKLIST, encoding="utf-8") as handle:
        real = checklist.read_items(handle.read())
    expect(len(real) >= 5, "this repo's checklist has at least five items")
    for item in real:
        for field in ("Files", "Lines"):
            if item.get(field):
                try:
                    re.compile(item[field])
                except re.error as err:
                    expect(False, "%s: %s does not compile: %s" % (item["name"], field, err))
        expect(bool(item.get("Check")), "%s has a Check line" % item["name"])
        expect(bool(item.get("Why")), "%s has a Why line" % item["name"])

    if bad:
        print("%d checklist checks failed" % bad)
        return 1
    print("change checklist: all checks pass (%d items in this repo)" % len(real))
    return 0


if __name__ == "__main__":
    sys.exit(main())
