"""Writes Data/ForeverVendorSpots.lua: where vendors and trainers stand on
WoW: Forever, as the game showed them, so every player gets the spots the
owner's play found.

Run from the repository root:

    python tools/forever_vendor_spots.py [saved file ...]

A saved file is the addon's account save, Blackthornes_TS.lua from the
game's WTF/Account/<account>/SavedVariables folder. Only its `vendorSpots`
and `trainerSpots` tables are read (Logic/VendorPins.lua: NPC ID -> name,
map ID, x, y, side and, for a vendor, the materials it sells; kept whenever
a vendor or trainer window opens), so nothing about the player or their
characters is copied.

The spots already in Data/ForeverVendorSpots.lua are kept, and a reading
from a save replaces them (the newest when several saves name one vendor).
When it was seen is not written out. A spot the game saw always wins
over Classic's (Data/VendorSpots.lua, Data/LearnSpots.lua).

Options:
    --stdout   print the file instead of writing it
"""

import os
import sys

from lupa import lua51
from lupa.lua51 import lua_type

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "ForeverVendorSpots.lua")
SIDES = ("A", "H", "")


# A save is read as data: run in an empty table with nothing to call, so a
# file that is not what it seems can reach neither the disk nor Python.
# Compiled chunks are refused, since they could get round that.
READ_SAVE = """
function(text)
    if text:sub(1, 1) == "\\27" then return nil, "a compiled file, not a save" end
    local chunk, err = loadstring(text, "=save")
    if not chunk then return nil, err end
    local env = {}
    setfenv(chunk, env)
    local ok, why = pcall(chunk)
    if not ok then return nil, why end
    return env.BlackthornesTSDB, false
end
"""


def clean(row):
    """One vendor as (name, mapID, x, y, side, at, {itemID: unlimited}), or
    None when a field is not what it should be."""
    try:
        name = row["name"]
        if not isinstance(name, str) or not name or len(name) > 60:
            return None
        map_id = int(row["mapID"])
        x, y = float(row["x"]), float(row["y"])
        if map_id <= 0 or not (0 <= x <= 100 and 0 <= y <= 100):
            return None
        side = row["side"] if row["side"] in SIDES else ""
        at = int(row["at"] or 0)
        items = {}
        for item_id in keys(row["items"]):
            items[int(item_id)] = bool(row["items"][item_id])
        return (name, map_id, round(x, 1), round(y, 1), side, at, items)
    except (TypeError, ValueError, KeyError):
        return None


def keys(table):
    """A Lua table's keys. Never its truth: a table keyed by IDs has no
    length, so lupa calls it false."""
    return list(table.keys()) if lua_type(table) == "table" else []


def from_save(lua, path, key):
    """One spots table (vendorSpots or trainerSpots) in one account save,
    checked row by row."""
    with open(path, encoding="utf-8") as f:
        db, why = lua.eval(READ_SAVE)(f.read())
    if why:
        print(f"could not read {path}: {why}", file=sys.stderr)
    spots = db and db[key]
    found = {}
    for npc_id in keys(spots):
        spot = clean(spots[npc_id])
        try:
            npc = int(npc_id)
        except (TypeError, ValueError):
            spot = None
        if spot:
            found[npc] = spot
        else:
            print(f"skipped a row that could not be read: {npc_id}", file=sys.stderr)
    return found


def shipped(lua, table):
    """What Data/ForeverVendorSpots.lua already holds in one table."""
    if not os.path.exists(OUTPUT):
        return {}
    lua.execute("ns = {}")
    chunk = lua.eval("function(path) return assert(loadfile(path)) end")(OUTPUT)
    chunk("Blackthornes_TS", lua.eval("ns"))
    data = lua.eval("ns." + table)
    found = {}
    for npc_id in keys(data):
        row = data[npc_id]
        items = {}
        for item_id in keys(row[6]):
            items[int(item_id)] = bool(row[6][item_id])
        found[int(npc_id)] = (row[1], int(row[2]), float(row[3]), float(row[4]),
                              row[5] or "", 0, items)
    return found


def lua_string(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + s.replace("\n", "\\n").replace("\r", "\\r") + '"'


def num(x):
    return ("%.1f" % x).rstrip("0").rstrip(".")


def rows(spots):
    lines = []
    for npc_id in sorted(spots):
        name, map_id, x, y, side, _, items = spots[npc_id]
        sells = ", ".join(f"[{i}] = {'true' if items[i] else 'false'}" for i in sorted(items))
        sells = "{ " + sells + " }" if sells else "{}"
        lines.append(f"    [{npc_id}] = {{ {lua_string(name)}, {map_id}, {num(x)}, {num(y)}, "
                     f"{lua_string(side)}, {sells} }},")
    return lines


def render(vendors, trainers):
    lines = [
        "-- Blackthornes Tradeskills -- Data/ForeverVendorSpots.lua",
        "-- Where vendors and trainers stand on WoW: Forever, as the game showed",
        "-- them. It wins over Classic's spots (Data/VendorSpots.lua,",
        "-- Data/LearnSpots.lua); one the player opens wins over this",
        "-- (Logic/VendorPins.lua).",
        "--",
        "-- Generated by tools/forever_vendor_spots.py from spots seen in game.",
        "-- Do not edit by hand: rerun the tool.",
        "",
        "local _, ns = ...",
        "",
        "-- [npc ID] = { name, map ID, x, y, side (\"A\", \"H\" or \"\"),",
        "--   { [item ID] = never runs out } }",
        "ns.FOREVER_VENDOR_SPOTS = {",
    ]
    lines += rows(vendors)
    lines += ["}", "", "-- [npc ID] = { name, map ID, x, y, side, {} }", "ns.FOREVER_TRAINER_SPOTS = {"]
    lines += rows(trainers)
    lines.append("}")
    return "\n".join(lines) + "\n"


def merge(spots, found):
    for npc_id, spot in found.items():
        old = spots.get(npc_id)
        if not old or old[5] == 0 or spot[5] >= old[5]:
            spots[npc_id] = spot


def main(argv):
    to_stdout = "--stdout" in argv
    saves = [a for a in argv if a != "--stdout"]
    lua = lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
    vendors = shipped(lua, "FOREVER_VENDOR_SPOTS")
    trainers = shipped(lua, "FOREVER_TRAINER_SPOTS")
    for path in saves:
        merge(vendors, from_save(lua, path, "vendorSpots"))
        merge(trainers, from_save(lua, path, "trainerSpots"))
    text = render(vendors, trainers)
    if to_stdout:
        sys.stdout.write(text)
    else:
        with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"{len(vendors)} vendor and {len(trainers)} trainer spots written to "
              "Data/ForeverVendorSpots.lua")


if __name__ == "__main__":
    main(sys.argv[1:])
