"""Checks tools/make_forever_recipes.py puts Classic recipes right from the
Forever client's game tables: a recipe moved to another profession takes
the client's line, changed amounts take the client's materials, the same
materials in another order change nothing, and a recipe with no materials
in the tables keeps the book's.

    python tools/test_forever_recipes.py
"""

import csv
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_forever_recipes as tool  # noqa: E402

failures = 0


def check(label, got, want):
    global failures
    if got != want:
        failures += 1
        print(f"  FAIL  {label}: got {got!r}, wanted {want!r}")
    else:
        print(f"  ok    {label}")


def write(folder, name, header, rows):
    with open(os.path.join(folder, name + ".csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


SLA = ["SkillLine", "Spell", "MinSkillLineRank", "TrivialSkillLineRankLow",
       "TrivialSkillLineRankHigh", "AcquireMethod"]
REAG = ["SpellID"] + [f"Reagent_{i}" for i in range(8)] + [f"ReagentCount_{i}" for i in range(8)]


def reagent_row(spell, mats):
    items = [mats[i] for i in range(0, len(mats), 2)]
    counts = [mats[i] for i in range(1, len(mats), 2)]
    items += [0] * (8 - len(items))
    counts += [0] * (8 - len(counts))
    return [spell] + items + counts


with tempfile.TemporaryDirectory() as folder:
    write(folder, "SpellName", ["ID", "Name_lang"],
          [[100, "Moved Recipe"], [101, "Cheaper Recipe"], [102, "Same Recipe"],
           [103, "No Reagents Recipe"], [104, "Shuffled Recipe"]])
    write(folder, "SkillLineAbility", SLA,
          [[165, 100, 1, 1, 1, 0], [164, 101, 1, 1, 1, 0], [164, 102, 1, 1, 1, 0],
           [164, 103, 1, 1, 1, 0], [197, 104, 1, 1, 1, 0], [165, 104, 1, 1, 1, 0]])
    write(folder, "SpellReagents", REAG,
          [reagent_row(100, [8170, 40, 12810, 2]),
           reagent_row(101, [2835, 1]),
           reagent_row(102, [2840, 4]),
           reagent_row(103, []),
           reagent_row(104, [4306, 2, 2321, 1])])
    write(folder, "SpellEffect",
          ["SpellID", "Effect", "EffectItemType", "EffectBasePointsF", "EffectTriggerSpell"], [])
    write(folder, "Item", ["ID", "ClassID"], [])
    write(folder, "ItemEffect", ["ID", "SpellID"], [])
    write(folder, "ItemSparse", ["ID", "RequiredSkillRank", "BuyPrice"], [])
    write(folder, "ItemXItemEffect", ["ItemID", "ItemEffectID"], [])

    tool.FEWEST_ROWS, tool.FEWEST_NAMES = 0, 0
    book = {100: "Moved Recipe", 101: "Cheaper Recipe", 102: "Same Recipe",
            103: "No Reagents Recipe", 104: "Shuffled Recipe", 105: "Gone Recipe"}
    book_rows = {
        100: (164, [7077, 1]),
        101: (164, [2835, 1, 2589, 1]),
        102: (164, [2840, 4]),
        103: (164, [2840, 9]),
        104: (165, [2321, 1, 4306, 2]),
        105: (164, [2840, 1]),
    }
    recipes, items, gone, gone_items, fixes = tool.collect(folder, book, {}, book_rows)

    print("\nput right from the tables")
    check("moved recipe takes the client's profession", fixes.get(100, (None,))[0], 165)
    check("moved recipe takes the client's materials", fixes.get(100, (0, None))[1], [8170, 40, 12810, 2])
    check("cheaper recipe keeps its profession", fixes.get(101, (None,))[0], 164)
    check("cheaper recipe takes the client's materials", fixes.get(101, (0, None))[1], [2835, 1])

    print("\nleft alone")
    check("same materials change nothing", 102 in fixes, False)
    check("no materials in the tables keeps the book's", 103 in fixes, False)
    check("another order alone, on one of its lines, changes nothing", 104 in fixes, False)
    check("a gone recipe is not put right", 105 in fixes, False)
    check("a gone recipe is gone", 105 in gone, True)

    print("\nwritten out")
    text = tool.render(recipes, items, "1.0", gone, gone_items, fixes)
    check("the file lists the fixes", "[100] = { 165, { 8170, 40, 12810, 2 } }" in text, True)
    check("the file lays the fixes over the book", "row[6] = fix[2]" in text, True)

if failures:
    sys.exit(f"{failures} check(s) failed")
print("\n  Forever recipe fixes: all checks passed")
