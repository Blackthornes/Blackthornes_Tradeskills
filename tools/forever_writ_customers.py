"""Writes Data/ForeverWritCustomers.lua: where each Craftsman's Writ is
handed in on WoW: Forever, as players' own play learned it, so every player
can group the writ list by zone before handing a writ in themselves.

Run from the repository root:

    python tools/forever_writ_customers.py [--shared] [saved file ...]

A saved file is the addon's account save, Blackthornes_TS.lua from the
game's WTF/Account/<account>/SavedVariables folder. Only its
`merchantsFavor.writCustomers` table is read (Logic/Writs.lua: the item a
writ asks for -> the customer's name, zone, map ID, x, y, and fromLog when
the quest log gave the spot), so nothing about the player or their
characters is copied. With --shared, the writ spots players chose to send
(`sharedData[sender id].writs`, Logic/Contribute.lua) are read too; the
sender ids are never read as names or written out.

Only writs in Data/CraftsmansWrits.lua are kept. What the file already holds
is kept, a spot read standing at the customer beats one the quest log gave,
and the save's own spots beat what players sent. When it was seen is not
written out. A spot the player learns in game always wins over this file.

Options:
    --stdout   print the file instead of writing it
"""

import os
import sys

from lupa import lua51
from lupa.lua51 import lua_type

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "ForeverWritCustomers.lua")
WRITS = os.path.join(ROOT, "Data", "CraftsmansWrits.lua")
MOST_WORDS = 60
MOST_MAP = 100000

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


def keys(table):
    """A Lua table's keys. Never its truth: a table keyed by IDs has no
    length, so lupa calls it false."""
    return list(table.keys()) if lua_type(table) == "table" else []


def words(value):
    """Plain words: no colour codes, links or control characters."""
    if not isinstance(value, str) or not value.strip() or len(value.encode("utf-8")) > MOST_WORDS:
        return None
    if "|" in value or any(ord(c) < 32 for c in value):
        return None
    return value


def spot(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return round(float(value), 1) if 0 <= value <= 100 else None


def whole(value, low, high):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if value != int(value):
        return None
    return int(value) if low <= value <= high else None


def writ_items(lua):
    """The item IDs the shipped writ list asks for."""
    lua.execute("ns = {}")
    chunk = lua.eval("function(path) return assert(loadfile(path)) end")(WRITS)
    chunk("Blackthornes_TS", lua.eval("ns"))
    found = set()
    writs = lua.eval("ns.CRAFTSMANS_WRITS")
    for i in keys(writs):
        writ = writs[i]
        if lua_type(writ) == "table" and writ["item"] is not None:
            found.add(int(writ["item"]))
    return found


def clean(item_id, row, items, short=False):
    """One customer as a dict, or None when anything in it is not what the
    writ list keeps. `short` reads the shape Contribute sends (z, n, m, l)."""
    try:
        item = int(item_id)
    except (TypeError, ValueError):
        return None
    if item not in items or lua_type(row) != "table":
        return None
    zone = words(row["z"] if short else row["zone"])
    x, y = spot(row["x"]), spot(row["y"])
    if not zone or x is None or y is None:
        return None
    raw_name = row["n"] if short else row["name"]
    name = words(raw_name)
    if raw_name is not None and not name:
        return None
    raw_map = row["m"] if short else row["mapID"]
    map_id = whole(raw_map, 1, MOST_MAP) if raw_map is not None else None
    if raw_map is not None and map_id is None:
        return None
    from_log = (row["l"] if short else row["fromLog"]) is True
    return {"name": name, "zone": zone, "mapID": map_id, "x": x, "y": y, "fromLog": from_log}


def read_save(lua, path):
    with open(path, encoding="utf-8") as f:
        db, why = lua.eval(READ_SAVE)(f.read())
    if why:
        print(f"could not read {path}: {why}", file=sys.stderr)
    return db


def from_save(db, items):
    favor = db and db["merchantsFavor"]
    customers = favor["writCustomers"] if lua_type(favor) == "table" else None
    found = {}
    for item_id in keys(customers):
        row = clean(item_id, customers[item_id], items)
        if row:
            found[int(item_id)] = row
    return found


def from_shared(db, items):
    """Every sender's writ spots, newest sender last, so it wins a tie."""
    shared = db and db["sharedData"]
    senders = []
    for sender in keys(shared):
        entry = shared[sender]
        if lua_type(entry) == "table" and lua_type(entry["writs"]) == "table":
            at = entry["at"] if isinstance(entry["at"], (int, float)) else 0
            senders.append((at, entry["writs"]))
    senders.sort(key=lambda pair: pair[0])
    found = []
    for _, writs in senders:
        batch = {}
        for item_id in keys(writs):
            row = clean(item_id, writs[item_id], items, short=True)
            if row:
                batch[int(item_id)] = row
        found.append(batch)
    return found


def shipped(lua, items):
    """What Data/ForeverWritCustomers.lua already holds."""
    if not os.path.exists(OUTPUT):
        return {}
    lua.execute("ns = {}")
    chunk = lua.eval("function(path) return assert(loadfile(path)) end")(OUTPUT)
    chunk("Blackthornes_TS", lua.eval("ns"))
    data = lua.eval("ns.WRIT_CUSTOMERS")
    found = {}
    for item_id in keys(data):
        row = clean(item_id, data[item_id], items)
        if row:
            found[int(item_id)] = row
    return found


def merge(customers, found):
    """A spot read at the customer is never replaced by one the quest log
    gave; otherwise the newer source wins."""
    for item, row in found.items():
        old = customers.get(item)
        if old and row["fromLog"] and not old["fromLog"]:
            continue
        customers[item] = row


def lua_string(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + s.replace("\n", "\\n").replace("\r", "\\r") + '"'


def num(x):
    return ("%.1f" % x).rstrip("0").rstrip(".")


def render(customers):
    lines = [
        "-- Blackthornes Tradeskills -- Data/ForeverWritCustomers.lua",
        "-- Where each Craftsman's Writ is handed in on WoW: Forever, as players'",
        "-- own play learned it. A spot the player learns in game wins over this",
        "-- (Logic/Writs.lua, Writs:GetCustomer).",
        "--",
        "-- Generated by tools/forever_writ_customers.py from spots seen in game.",
        "-- Do not edit by hand: rerun the tool.",
        "",
        "local _, ns = ...",
        "",
        "-- [item the writ asks for] = { name, zone, mapID, x, y, fromLog }",
        "ns.WRIT_CUSTOMERS = {",
    ]
    for item in sorted(customers):
        row = customers[item]
        fields = []
        if row["name"]:
            fields.append(f"name = {lua_string(row['name'])}")
        fields.append(f"zone = {lua_string(row['zone'])}")
        if row["mapID"]:
            fields.append(f"mapID = {row['mapID']}")
        fields.append(f"x = {num(row['x'])}, y = {num(row['y'])}")
        if row["fromLog"]:
            fields.append("fromLog = true")
        lines.append(f"    [{item}] = {{ " + ", ".join(fields) + " },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv):
    to_stdout = "--stdout" in argv
    with_shared = "--shared" in argv
    saves = [a for a in argv if a not in ("--stdout", "--shared")]
    lua = lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
    items = writ_items(lua)
    customers = shipped(lua, items)
    dbs = [read_save(lua, path) for path in saves]
    if with_shared:
        for db in dbs:
            for batch in from_shared(db, items):
                merge(customers, batch)
    for db in dbs:
        merge(customers, from_save(db, items))
    text = render(customers)
    if to_stdout:
        sys.stdout.write(text)
    else:
        with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"{len(customers)} writ customers written to Data/ForeverWritCustomers.lua")


if __name__ == "__main__":
    main(sys.argv[1:])
