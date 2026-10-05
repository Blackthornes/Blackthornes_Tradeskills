"""Writes Data/RecipeBook.lua: every recipe of every crafting profession,
including the ones nobody on the account has learned.

Run from the repository root with the vmangos world database dump and
pfQuest checked out somewhere:

    python tools/make_recipe_book.py <world_full_14_june_2021.sql> <pfQuest>

  github.com/brotalnia/database    world_full_14_june_2021.7z, unpacked: the
                                   vmangos world database, which carries
                                   Classic 1.12's spell table (what a recipe
                                   makes and from what), the skill lines
                                   (which profession, at what skill), the
                                   trainers and the recipe items
  github.com/shagu/pfQuest         db/: who sells a recipe item and where
                                   they stand, and who drops one

Nothing in the output is typed by hand except PROFESSIONS below. The game
fills in names, prices and whatever Forever changed: a recipe seen in a
profession window in game (Data/Recipes.lua) always wins over this table.

Each recipe is keyed by its spell ID, which is the recipe ID the profession
window uses for Classic recipes. Each recipe item (Pattern, Plans, Formula,
Recipe, Schematic, Manual) is keyed by its item ID and says which recipe it
teaches, so a recipe seen at the auction house can be valued before it is
learned.
"""

import collections
import re
import sys
from pathlib import Path

from lupa import lua51

# The professions that craft, by Classic skill line.
PROFESSIONS = {
    129: "First Aid", 164: "Blacksmithing", 165: "Leatherworking",
    171: "Alchemy", 185: "Cooking", 186: "Mining", 197: "Tailoring",
    202: "Engineering", 333: "Enchanting",
}

PATCH = 10       # item_template rows up to patch 1.12
BUILD = 5875     # spell and trainer rows up to client build 5875 (1.12.1)

CREATE_ITEM = 24
LEARN_SPELL = 36
RECIPE_CLASS = 9

# A recipe dropped by more creatures than this is a world drop, and the
# tooltip says so rather than naming one of them.
NAMED_DROPPERS = 3
# Vendors named per recipe item; the rest are counted.
NAMED_VENDORS = 3

BAD_TITLE = re.compile(r"UNUSED|DEPRECATED|\bOLD\b|<|\[|TEST|NYI|ZZOLD|\bQA\b|DND", re.I)
INSERT = re.compile(r"INSERT INTO `(\w+)` \(([^)]*)\) VALUES")


def parse_row(line):
    """One `(a,'b',c)` row as a list of values, or None when it runs on."""
    values, cur, in_str, quoted = [], [], False, False
    j, n = 1, len(line)
    while j < n:
        ch = line[j]
        if in_str:
            if ch == "\\":
                cur.append(line[j + 1])
                j += 2
                continue
            if ch == "'":
                in_str = False
            else:
                cur.append(ch)
        elif ch == "'":
            in_str, quoted = True, True
        elif ch in ",)":
            text = "".join(cur)
            if quoted:
                values.append(text)
            else:
                text = text.strip()
                try:
                    values.append(int(text))
                except ValueError:
                    try:
                        values.append(float(text))
                    except ValueError:
                        values.append(text)
            cur, quoted = [], False
            if ch == ")":
                return values
        else:
            cur.append(ch)
        j += 1
    return None


def tables(path, wanted):
    """Every row of the tables in `wanted` from one mysqldump file, as dicts."""
    out = {t: [] for t in wanted}
    current, columns = None, None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            m = INSERT.match(line)
            if m:
                current = m.group(1) if m.group(1) in wanted else None
                columns = [c.strip(" `") for c in m.group(2).split(",")]
                continue
            if not line.startswith("("):
                if line:
                    current = None
                continue
            if current is None:
                continue
            values = parse_row(line)
            if values is not None and len(values) == len(columns):
                row = dict(zip(columns, values))
                for k, v in row.items():
                    if isinstance(v, str):
                        row[k] = v.strip()
                out[current].append(row)
    return out


def latest(rows, key, version, highest):
    """One row per `key`: the newest whose `version` is at most `highest`."""
    best = {}
    for r in rows:
        if r[version] > highest:
            continue
        k = r[key]
        if k not in best or r[version] > best[k][version]:
            best[k] = r
    return best


def load_pfquest(folder):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("pfDB = setmetatable({}, {__index = function(t, k) "
                "local v = {} rawset(t, k, v) return v end})")
    db = folder / "db"
    for name in ["units.lua", "items.lua", "zones.lua",
                 "enUS/units.lua", "enUS/items.lua", "enUS/zones.lua"]:
        lua.execute((db / name).read_text(encoding="utf-8"))
    return lua.eval("pfDB")


def lua_table(t):
    return {k: t[k] for k in t} if t is not None else {}


def zone_of(entry):
    """The zone an NPC mostly stands in."""
    coords = entry and entry["coords"]
    if not coords:
        return None
    zones = collections.Counter(coords[i][3] for i in coords)
    return zones.most_common(1)[0][0] if zones else None


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    vm = tables(sys.argv[1], {
        "item_template", "spell_template", "skill_line_ability", "npc_trainer",
        "npc_trainer_template", "creature_template",
    })
    pfq = load_pfquest(Path(sys.argv[2]))

    items = latest(vm["item_template"], "entry", "patch", PATCH)
    spells = latest(vm["spell_template"], "entry", "build", BUILD)
    templates = latest(vm["creature_template"], "entry", "patch", PATCH)

    # Which profession teaches each spell, and the skill it asks.
    lines = {}
    for r in vm["skill_line_ability"]:
        if r["skill_id"] in PROFESSIONS and r["build"] <= BUILD:
            lines[r["spell_id"]] = r

    # Recipes: a profession spell that uses materials. Most make an item;
    # enchants and a few others make none and are kept with item 0.
    recipes = {}
    for spellID, line in lines.items():
        spell = spells.get(spellID)
        if not spell or BAD_TITLE.search(spell["name"]):
            continue
        materials = []
        for n in range(1, 9):
            rid, count = spell[f"reagent{n}"], spell[f"reagentCount{n}"]
            if rid and count and rid in items:
                materials.append((rid, count))
        if not materials:
            continue
        made, qmin, qmax = 0, 1, 1
        for e in (1, 2, 3):
            if spell[f"effect{e}"] == CREATE_ITEM and spell[f"effectItemType{e}"] in items:
                made = spell[f"effectItemType{e}"]
                base = spell[f"effectBasePoints{e}"]
                qmin = max(1, base + max(1, spell[f"effectBaseDice{e}"]))
                qmax = max(qmin, base + spell[f"effectDieSides{e}"])
                break
        if made and BAD_TITLE.search(items[made]["name"]):
            continue
        recipes[spellID] = {
            "prof": line["skill_id"], "skill": line["req_skill_value"],
            "item": made, "qmin": qmin, "qmax": qmax, "materials": materials,
            "start": 1 if line["learn_on_get_skill"] else 0, "name": spell["name"],
        }

    # Spells that teach a recipe: trainers and recipe items cast these.
    teaches = {}
    for spellID, spell in spells.items():
        for e in (1, 2, 3):
            if spell[f"effect{e}"] == LEARN_SPELL and spell[f"effectTriggerSpell{e}"] in recipes:
                teaches[spellID] = spell[f"effectTriggerSpell{e}"]

    # Trainers: the cheapest a trainer asks, and the skill it asks for.
    by_template = collections.defaultdict(list)
    for uid, t in templates.items():
        if t["trainer_id"]:
            by_template[t["trainer_id"]].append(uid)
    trained = {}
    for r in vm["npc_trainer"] + vm["npc_trainer_template"]:
        if r["build_min"] > BUILD or r["build_max"] < BUILD:
            continue
        spellID = teaches.get(r["spell"], r["spell"])
        if spellID not in recipes:
            continue
        if r["entry"] not in templates and not by_template.get(r["entry"]):
            continue
        held = trained.get(spellID)
        if not held or r["spellcost"] < held[0]:
            trained[spellID] = (r["spellcost"], r["reqskillvalue"])

    # Recipe items: what they teach, who sells and who drops them.
    units, unit_names = pfq["units"]["data"], pfq["units"]["enUS"]
    zone_names = pfq["zones"]["enUS"]
    pf_items = pfq["items"]["data"]
    books = {}
    for itemID, item in items.items():
        if item["class"] != RECIPE_CLASS or BAD_TITLE.search(item["name"]):
            continue
        for n in range(1, 6):
            spellID = teaches.get(item[f"spellid_{n}"], item[f"spellid_{n}"])
            if spellID in recipes:
                break
        else:
            continue
        entry = pf_items[itemID]
        vendors, droppers = [], {}
        if entry and entry["V"]:
            for uid in sorted(lua_table(entry["V"])):
                name = unit_names[uid]
                if not name or not units[uid]:
                    continue
                zone = zone_of(units[uid])
                zone = zone_names[zone] if zone else None
                vendors.append((name, zone or "", units[uid]["fac"] or ""))
        if entry and entry["U"]:
            droppers = {uid: float(c) for uid, c in lua_table(entry["U"]).items()}
        named = []
        if 0 < len(droppers) <= NAMED_DROPPERS:
            for uid, _ in sorted(droppers.items(), key=lambda x: -x[1]):
                if unit_names[uid]:
                    named.append(unit_names[uid])
        books[itemID] = {
            "spell": spellID, "skill": item["required_skill_rank"],
            "price": item["buy_price"] // max(1, item["buy_count"]),
            "vendors": vendors, "drops": len(droppers), "named": named,
            "name": item["name"],
        }

    # The skill a recipe really asks: the most of what the skill line, the
    # trainer and the recipe item say.
    for spellID, r in recipes.items():
        if spellID in trained:
            r["skill"] = max(r["skill"], trained[spellID][1])
    for b in books.values():
        r = recipes[b["spell"]]
        r["skill"] = max(r["skill"], b["skill"])

    out = []
    w = out.append
    w("-- Blackthornes Tradeskills -- Data/RecipeBook.lua")
    w("-- Every recipe of every crafting profession, learned or not, and the recipe")
    w("-- items that teach them.")
    w("--")
    w("-- Generated by tools/make_recipe_book.py from Classic 1.12 data, never typed")
    w("-- by hand: the vmangos world database (recipes, skill lines, trainers,")
    w("-- recipe items) and pfQuest's database (who sells or drops a recipe item).")
    w("-- Forever may have changed some of it; a recipe seen in a profession window")
    w("-- in game always wins over this table (Logic/RecipeBook.lua).")
    w("")
    w("local _, ns = ...")
    w("")
    w("local Book = {}")
    w("ns.RECIPE_BOOK = Book")
    w("")
    w("-- Classic skill line -> profession name.")
    w("Book.PROFESSIONS = {")
    for k in sorted(PROFESSIONS):
        w(f"    [{k}] = {lua_string(PROFESSIONS[k])},")
    w("}")
    w("")
    w("-- [recipe ID] = { skill line, skill, item made (0 for none), least made,")
    w("--   most made, { material, count, ... }, name }; t = what a trainer asks,")
    w("--   in copper; s = 1 when the profession comes with it.")
    w("Book.RECIPES = {")
    for spellID in sorted(recipes):
        r = recipes[spellID]
        mats = ", ".join(f"{i}, {c}" for i, c in r["materials"])
        extra = ""
        if spellID in trained:
            extra += f", t = {trained[spellID][0]}"
        if r["start"]:
            extra += ", s = 1"
        w(f"    [{spellID}] = {{ {r['prof']}, {r['skill']}, {r['item']}, {r['qmin']}, "
          f"{r['qmax']}, {{ {mats} }}, {lua_string(r['name'])}{extra} }},")
    w("}")
    w("")
    w("-- [recipe item] = { recipe ID, what a vendor charges in copper };")
    w("--   v = { vendor, zone, faction, ... } who sells it (faction A, H or AH);")
    w("--   d = how many creatures drop it; n = { creature, ... } when only a few do.")
    w("Book.ITEMS = {")
    for itemID in sorted(books):
        b = books[itemID]
        extra = ""
        if b["vendors"]:
            shown = b["vendors"][:NAMED_VENDORS]
            extra += ", v = { " + ", ".join(
                f"{lua_string(n)}, {lua_string(z)}, {lua_string(f)}" for n, z, f in shown) + " }"
            if len(b["vendors"]) > NAMED_VENDORS:
                extra += f", vn = {len(b['vendors'])}"
        if b["drops"]:
            extra += f", d = {b['drops']}"
        if b["named"]:
            extra += ", n = { " + ", ".join(lua_string(n) for n in b["named"]) + " }"
        w(f"    [{itemID}] = {{ {b['spell']}, {b['price']}{extra} }}, -- {b['name']}")
    w("}")
    w("")

    Path("Data/RecipeBook.lua").write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"{len(recipes)} recipes, {len(books)} recipe items, "
          f"{sum(1 for r in recipes.values() if r['item'])} make an item")


if __name__ == "__main__":
    main()
