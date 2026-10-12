"""Writes Data/LearnSpots.lua: where a recipe nobody here knows yet is
learned, and the skill Forever asks for it, for the Level Up tab's Learn
next list (asked 2026-10-12).

Run from the repository root after tools/make_recipe_book.py, with the same
two Classic sources and the Forever client's game tables exported as CSV:

    python tools/make_learn_spots.py <world database dump> <quest database> <client tables>

  world database dump   the same world_full_14_june_2021.sql as
                        make_recipe_book.py: which trainer teaches what
  quest database        the same folder as make_recipe_book.py: where each
                        trainer and vendor stands
  client tables         a folder with the Forever client's SkillLineAbility.csv:
                        the skill at which each recipe turns yellow and grey
                        on Forever

What it writes, all keyed the way Data/RecipeBook.lua is:

  SKILLS    [recipe ID] = { skill to learn, yellow, grey } on Forever. The
            client tables give the yellow and grey skills, not the skill to
            learn, so that one is Classic's moved by as much as Forever moved
            the yellow (Raptor Hide Belt: Classic 165 and yellow at 185,
            Forever yellow at 160, so 140, which a player saw in game). Only
            recipes the book has; a recipe item's own tooltip, read in game,
            still beats it (Logic/RecipeBook.lua).
  TRAINERS  [skill line] = { { name, zone, x, y, faction, most }, ... }: who
            trains each profession and the highest Classic skill they teach,
            so an Apprentice is never sent to for an Expert's recipe.
  VENDORS   ["name|zone"] = { x, y } for every vendor Data/RecipeBook.lua
            names, so Show the way can pin them.

Spots are Classic's, the spawn in the zone the NPC mostly stands in. Never
edit the output by hand; rerun this.
"""

import collections
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_recipe_book import (  # noqa: E402
    BUILD, PATCH, PROFESSIONS, LEARN_SPELL, latest, lua_string, load_pfquest, tables,
)

from lupa import lua51  # noqa: E402


def read_book():
    """Data/RecipeBook.lua's recipes and recipe items, as make_recipe_book wrote them."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("ns = {}")
    text = Path("Data/RecipeBook.lua").read_text(encoding="utf-8")
    text = text.replace("local _, ns = ...", "", 1)
    lua.execute(text)
    book = lua.eval("ns.RECIPE_BOOK")
    recipes = {int(k): v for k, v in book["RECIPES"].items()}
    items = {int(k): v for k, v in book["ITEMS"].items()}
    return recipes, items


def spot(entry, zone_names):
    """(zone, x, y) where an NPC mostly stands, or None."""
    coords = entry and entry["coords"]
    if not coords:
        return None
    spawns = [coords[i] for i in coords]
    zones = collections.Counter(s[3] for s in spawns)
    if not zones:
        return None
    zone = zones.most_common(1)[0][0]
    first = next(s for s in spawns if s[3] == zone)
    name = zone_names[zone]
    if not name:
        return None
    return name, round(float(first[1]), 1), round(float(first[2]), 1)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)

    recipes, book_items = read_book()

    vm = tables(sys.argv[1], {
        "skill_line_ability", "spell_template", "npc_trainer", "npc_trainer_template",
        "creature_template",
    })
    quests = load_pfquest(Path(sys.argv[2]))
    client = Path(sys.argv[3])

    spells = latest(vm["spell_template"], "entry", "build", BUILD)
    templates = latest(vm["creature_template"], "entry", "patch", PATCH)

    # Classic's yellow per recipe, to move the skill to learn by.
    # (min_value is where it turns yellow, max_value grey.)
    classic_yellow = {}
    rows = [r for r in vm["skill_line_ability"]
            if r["skill_id"] in PROFESSIONS and r["spell_id"] in recipes]
    for spellID, r in latest(rows, "spell_id", "build", BUILD).items():
        if r["min_value"]:
            classic_yellow[spellID] = r["min_value"]

    # Forever's yellow and grey.
    skills = {}
    with open(client / "SkillLineAbility.csv", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            spellID = int(row["Spell"])
            if spellID not in recipes:
                continue
            yellow = int(row["TrivialSkillLineRankLow"] or 0)
            grey = int(row["TrivialSkillLineRankHigh"] or 0)
            if yellow <= 0 or grey < yellow:
                continue
            book_skill = recipes[spellID][2]
            old_yellow = classic_yellow.get(spellID)
            req = book_skill
            if old_yellow:
                req = max(1, min(yellow, book_skill + (yellow - old_yellow)))
            skills[spellID] = (req, yellow, grey)

    # Who trains each profession, and the highest Classic skill they teach.
    teaches = {}
    for spellID, spell in spells.items():
        for e in (1, 2, 3):
            if spell[f"effect{e}"] == LEARN_SPELL and spell[f"effectTriggerSpell{e}"] in recipes:
                teaches[spellID] = spell[f"effectTriggerSpell{e}"]
    by_template = collections.defaultdict(list)
    for uid, t in templates.items():
        if t["trainer_id"]:
            by_template[t["trainer_id"]].append(uid)
    most = collections.defaultdict(lambda: collections.defaultdict(int))
    for r in vm["npc_trainer"] + vm["npc_trainer_template"]:
        if r["build_min"] > BUILD or r["build_max"] < BUILD:
            continue
        spellID = teaches.get(r["spell"], r["spell"])
        if spellID not in recipes:
            continue
        line = recipes[spellID][1]
        skill = max(recipes[spellID][2], r["reqskillvalue"])
        for uid in ([r["entry"]] if r["entry"] in templates else by_template.get(r["entry"], [])):
            most[uid][line] = max(most[uid][line], skill)

    units, unit_names = quests["units"]["data"], quests["units"]["enUS"]
    zone_names = quests["zones"]["enUS"]

    trainers = collections.defaultdict(list)
    for uid, lines in most.items():
        name = unit_names[uid]
        where = spot(units[uid], zone_names)
        if not name or not where:
            continue
        for line, top in lines.items():
            trainers[line].append((name, *where, units[uid]["fac"] or "", top))
    for line in trainers:
        trainers[line].sort(key=lambda t: (t[1], t[0]))

    # Spots for the vendors the book names.
    wanted = set()
    for row in book_items.values():
        v = row["v"]
        if v:
            values = [v[i] for i in range(1, len(v) + 1)]
            for i in range(0, len(values) - 2, 3):
                wanted.add((values[i], values[i + 1]))
    vendors = {}
    for uid in units:
        name = unit_names[uid]
        if not name:
            continue
        where = spot(units[uid], zone_names)
        if where and (name, where[0]) in wanted:
            vendors[(name, where[0])] = where[1:]

    out = []
    w = out.append
    w("-- Blackthornes Tradeskills -- Data/LearnSpots.lua")
    w("-- Where a recipe is learned, and the skill Forever asks for it, for the")
    w("-- Level Up tab's Learn next list (Logic/LearnNext.lua).")
    w("--")
    w("-- Generated by tools/make_learn_spots.py, never typed by hand. Spots are")
    w("-- Classic's; the skills are Forever's own.")
    w("")
    w("local _, ns = ...")
    w("")
    w("local Spots = {}")
    w("ns.LEARN_SPOTS = Spots")
    w("")
    w("-- [recipe ID] = { skill to learn, yellow from, grey from } on Forever.")
    w("Spots.SKILLS = {")
    for spellID in sorted(skills):
        req, yellow, grey = skills[spellID]
        w(f"    [{spellID}] = {{ {req}, {yellow}, {grey} }},")
    w("}")
    w("")
    w("-- [skill line] = { { trainer, zone, x, y, faction (A, H or AH), highest")
    w("--   Classic skill taught }, ... }")
    w("Spots.TRAINERS = {")
    for line in sorted(trainers):
        w(f"    [{line}] = {{")
        for name, zone, x, y, fac, top in trainers[line]:
            w(f"        {{ {lua_string(name)}, {lua_string(zone)}, {x}, {y}, {lua_string(fac)}, {top} }},")
        w("    },")
    w("}")
    w("")
    w('-- ["vendor|zone"] = { x, y } for the vendors Data/RecipeBook.lua names.')
    w("Spots.VENDORS = {")
    for name, zone in sorted(vendors):
        x, y = vendors[(name, zone)]
        w(f"    [{lua_string(name + '|' + zone)}] = {{ {x}, {y} }},")
    w("}")
    w("")

    Path("Data/LearnSpots.lua").write_text("\n".join(out), encoding="utf-8", newline="\n")
    moved = sum(1 for s, v in skills.items() if v[0] != recipes[s][2])
    print(f"{len(skills)} recipe skills ({moved} moved from Classic), "
          f"{sum(len(t) for t in trainers.values())} trainer rows, "
          f"{len(vendors)} of {len(wanted)} vendors placed")


if __name__ == "__main__":
    main()
