"""Writes Data/ForeverRecipes.lua: the recipes WoW: Forever added, which the
Classic book in Data/RecipeBook.lua does not have, so they show among the
recipes to learn before anyone has opened a profession window (the owner,
2026-10-17: "always add new recipe finds to tradeskills").

Run from the repository root:

    python tools/make_forever_recipes.py <tables folder> [--build 1.60.1.70450] [--stdout]

The tables folder holds the Forever client's game tables as CSV, one file
per table. Read: SkillLineAbility (which recipe belongs to which
profession, when it turns yellow and grey), SpellName, SpellEffect (what it
makes), SpellReagents (what it takes), Item, ItemEffect, ItemXItemEffect
(which recipe item teaches it) and ItemSparse (the recipe item's skill and
vendor price). The tables are never copied into the repository; only the
rows below go in the data file.

Only recipes in Forever's own spell range (FOREVER_FIRST and up) are kept.
The client also carries recipes from other Classic seasons below it, which
are not part of Forever. A recipe the book already has is left alone, and
so is one whose name says it is a test or unused.

The data file adds its recipes to ns.RECIPE_BOOK, in the book's own row
shape, each marked f = 1, with y and g for when it turns yellow and grey.
Nothing says where most of them are learned; a profession window seen in
game still wins over them (Logic/RecipeBook.lua). Rerun this whenever the
client tables are pulled again, and after tools/make_recipe_book.py.

Options:
    --build    the client build, written in the file's header
    --stdout   print the file instead of writing it
"""

import collections
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "ForeverRecipes.lua")
BOOK = os.path.join(ROOT, "Data", "RecipeBook.lua")

# The professions that craft, by Classic skill line, as in the book.
PROFESSIONS = {129, 164, 165, 171, 185, 186, 197, 202, 333}

# Forever's own spells start here; below are other Classic seasons' leftovers.
FOREVER_FIRST = 1000000

CREATE_ITEM = "24"
LEARN_SPELL = "36"
ENCHANT_ITEM = "53"
RECIPE_CLASS = "9"

# Names that mark a row the game never uses.
SKIP_NAME = re.compile(r"\[DNT\]|\bUNUSED\b|\(OLD\)|^Test\b|\bTEST\b|^zz", re.I)

# A real client has thousands of profession rows; fewer means a bad export.
FEWEST_ROWS = 1000


def rows(folder, name):
    path = os.path.join(folder, name + ".csv")
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def number(value):
    try:
        return int(float(value or 0))
    except (TypeError, ValueError):
        return 0


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def book_recipes(path):
    """The recipe IDs and recipe item IDs Data/RecipeBook.lua already has."""
    text = open(path, encoding="utf-8").read()
    split = text.index("Book.ITEMS")
    recipes = {int(m) for m in re.findall(r"^\s+\[(\d+)\] = \{ \d+,", text[:split], re.M)}
    items = {int(m) for m in re.findall(r"^\s+\[(\d+)\] = \{", text[split:], re.M)}
    return recipes, items


def collect(folder, book, book_items):
    names = {number(r["ID"]): r["Name_lang"] for r in rows(folder, "SpellName")}

    effects = collections.defaultdict(list)
    for r in rows(folder, "SpellEffect"):
        effects[number(r["SpellID"])].append(r)

    abilities, seen = {}, 0
    for r in rows(folder, "SkillLineAbility"):
        line, spell = number(r["SkillLine"]), number(r["Spell"])
        if line not in PROFESSIONS:
            continue
        seen += 1
        if spell < FOREVER_FIRST or spell in book or spell in abilities:
            continue
        name = names.get(spell) or ""
        kinds = {e["Effect"] for e in effects.get(spell, [])}
        if not name or SKIP_NAME.search(name) or not ({CREATE_ITEM, ENCHANT_ITEM} & kinds):
            continue
        abilities[spell] = r
    if seen < FEWEST_ROWS:
        raise SystemExit(f"SkillLineAbility has only {seen} profession rows; is the export whole?")

    reagents = {}
    for r in rows(folder, "SpellReagents"):
        spell = number(r["SpellID"])
        if spell not in abilities or spell in reagents:
            continue
        mats = []
        for i in range(8):
            item, count = number(r.get(f"Reagent_{i}")), number(r.get(f"ReagentCount_{i}"))
            if item > 0 and count > 0:
                mats += [item, count]
        reagents[spell] = mats

    # Which recipe item teaches which recipe: the item's use spell learns it
    # (or is it).
    classes = {number(r["ID"]): r["ClassID"] for r in rows(folder, "Item")}
    effect_spell = {number(r["ID"]): number(r["SpellID"]) for r in rows(folder, "ItemEffect")}
    sparse = {}
    for r in rows(folder, "ItemSparse"):
        sparse[number(r["ID"])] = (number(r.get("RequiredSkillRank")), number(r.get("BuyPrice")))
    teaches = collections.defaultdict(set)
    for r in rows(folder, "ItemXItemEffect"):
        item = number(r["ItemID"])
        if classes.get(item) != RECIPE_CLASS or item in book_items or item not in sparse:
            continue
        spell = effect_spell.get(number(r["ItemEffectID"]))
        if not spell:
            continue
        if spell in abilities:
            teaches[spell].add(item)
        for e in effects.get(spell, []):
            taught = number(e["EffectTriggerSpell"])
            if e["Effect"] == LEARN_SPELL and taught in abilities:
                teaches[taught].add(item)

    recipes, items = {}, {}
    for spell, r in abilities.items():
        made, count = 0, 1
        for e in effects.get(spell, []):
            if e["Effect"] == CREATE_ITEM and number(e["EffectItemType"]) > 0:
                made, count = number(e["EffectItemType"]), max(1, number(e["EffectBasePointsF"]))
                break
        yellow = number(r["TrivialSkillLineRankLow"])
        grey = number(r["TrivialSkillLineRankHigh"])
        if grey < yellow:
            grey = 0
        # The skill to learn: the recipe item's own, else the ability's,
        # else when it turns yellow (never earlier than it can be learned).
        skill = 0
        for item in teaches.get(spell, ()):
            skill = max(skill, sparse[item][0])
        if skill <= 0:
            skill = number(r["MinSkillLineRank"])
        if skill <= 1 and yellow > 1 and number(r["AcquireMethod"]) != 1:
            skill = yellow
        skill = max(1, skill)
        starter = number(r["AcquireMethod"]) == 1 and skill <= 1
        recipes[spell] = {
            "line": number(r["SkillLine"]), "skill": skill, "made": made, "count": count,
            "mats": reagents.get(spell, []), "name": names[spell],
            "yellow": yellow, "grey": grey, "starter": starter,
        }
        for item in teaches.get(spell, ()):
            items[item] = (spell, sparse[item][1])
    return recipes, items


def render(recipes, items, build):
    out = [
        "-- Blackthornes Tradeskills -- Data/ForeverRecipes.lua",
        "-- The recipes WoW: Forever added, which the Classic book",
        "-- (Data/RecipeBook.lua) does not have, laid into it in the book's own",
        "-- shape. f = 1 marks them; y and g are when they turn yellow and grey.",
        "-- A profession window seen in game still wins (Logic/RecipeBook.lua).",
        "--",
        "-- Generated by tools/make_forever_recipes.py from the Forever client's",
        f"-- game tables{f' (build {build})' if build else ''}. Do not edit by hand: rerun the tool.",
        "",
        "local _, ns = ...",
        "",
        "local Book = ns.RECIPE_BOOK",
        "if not Book then return end",
        "local RECIPES, ITEMS = Book.RECIPES, Book.ITEMS",
        "",
        "local recipes = {",
    ]
    for spell in sorted(recipes):
        r = recipes[spell]
        mats = ", ".join(str(v) for v in r["mats"])
        extra = ", f = 1"
        if r["yellow"] > 0:
            extra += f", y = {r['yellow']}"
        if r["grey"] > 0:
            extra += f", g = {r['grey']}"
        if r["starter"]:
            extra += ", s = 1"
        out.append(
            f"    [{spell}] = {{ {r['line']}, {r['skill']}, {r['made']}, {r['count']}, {r['count']}, "
            f"{{ {mats} }}, {lua_string(r['name'])}{extra} }},"
        )
    out += ["}", "", "-- [recipe item] = { recipe ID, what a vendor charges in copper }", "local items = {"]
    for item in sorted(items):
        spell, price = items[item]
        out.append(f"    [{item}] = {{ {spell}, {price}, f = 1 }},")
    out += [
        "}",
        "",
        "for id, row in pairs(recipes) do",
        "    if RECIPES[id] == nil then RECIPES[id] = row end",
        "end",
        "for id, row in pairs(items) do",
        "    if ITEMS[id] == nil then ITEMS[id] = row end",
        "end",
        "",
    ]
    return "\n".join(out)


def main(argv):
    args = list(argv)
    build, stdout = None, False
    if "--build" in args:
        i = args.index("--build")
        build = args[i + 1]
        del args[i:i + 2]
    if "--stdout" in args:
        args.remove("--stdout")
        stdout = True
    if len(args) != 1:
        raise SystemExit(__doc__)

    book, book_items = book_recipes(BOOK)
    recipes, items = collect(args[0], book, book_items)
    text = render(recipes, items, build)
    if stdout:
        sys.stdout.write(text)
        return
    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"Wrote {len(recipes)} recipes and {len(items)} recipe items to {OUTPUT}")


if __name__ == "__main__":
    main(sys.argv[1:])
