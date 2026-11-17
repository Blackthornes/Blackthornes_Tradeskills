"""The house rules check flags what it should and lets the rest through.

    python tools/test_check_house_rules.py

The same file lives in all five addons.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_house_rules as rules  # noqa: E402


def flags(line):
    return rules.problems_in_line(line)


def main():
    cases = [
        ('label:SetText(L["Sell this now"])', 0),
        ('label:SetText(L["Sell this now — fast"])', 1),
        ('label:SetText(L["Sell this now -- fast"])', 1),
        ('label:SetText(L["Farm seamlessly"])', 1),
        ('label:SetText(L["Now you can sell it"])', 1),
        ('label:SetText(L["Want to sell it?"])', 1),
        ('chat(L.Format("Sold %s?", name))', 1),
        ('chat(L.Format("Sold %s.", name))', 0),
        ('label:SetText(L["Want to sell it?"]) -- house-ok', 0),
        ('local q = "Ready?" -- not player words through L', 0),
        ('row:SetColor(C.rowAlt)', 1),
        ('row:SetColor(Theme.Color("rowAlt"))', 1),
        ('row:SetColor(Theme.Color("row"))', 1),
        ('row:SetColor(C.glassAlt)', 0),
        ('local row = rows[i]', 0),
        ('local rowAltered = 1', 0),
        ('    rowAlt      = { 0.125, 0.125, 0.133 },', 0),
    ]
    bad = 0
    for line, want in cases:
        got = len(flags(line))
        if got != want:
            bad += 1
            print("FAIL: %r flagged %d, wanted %d" % (line, got, want))
    for path, want in [
        ("UI/Main.lua", True),
        ("Locale/deDE.lua", False),
        ("Data/Items.lua", False),
        ("tools/test_x.lua", False),
        ("UI/Main.xml", False),
    ]:
        if rules.checked_path(path) != want:
            bad += 1
            print("FAIL: checked_path(%r) should be %s" % (path, want))
    if bad:
        print("%d house rules checks failed" % bad)
        return 1
    print("house rules check: all %d cases pass" % (len(cases) + 5))
    return 0


if __name__ == "__main__":
    sys.exit(main())
