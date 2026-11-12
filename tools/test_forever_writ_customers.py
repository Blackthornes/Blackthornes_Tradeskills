"""Checks tools/forever_writ_customers.py: only the writ spots are read from
a save, bad rows and items no writ asks for are skipped, a spot read at the
customer beats one the quest log gave, the save's own spots beat what players
sent, and nothing else from the save is written out.

    python tools/test_forever_writ_customers.py
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import forever_writ_customers as tool  # noqa: E402

SAVE = """
BlackthornesTSDB = {
  ["merchantsFavor"] = {
    ["writCustomers"] = {
      [3383] = { ["name"] = "Tilda Hand", ["zone"] = "Ashenvale", ["mapID"] = 1440,
        ["x"] = 34.6, ["y"] = 48.12, ["at"] = 1790000000 },
      [5996] = { ["zone"] = "Westfall", ["x"] = 50, ["y"] = 50, ["fromLog"] = true },
      [3385] = { ["name"] = "|cffff0000Bad|r", ["zone"] = "Duskwood", ["x"] = 1, ["y"] = 1 },
      [999999] = { ["name"] = "Not A Writ", ["zone"] = "Elwynn Forest", ["x"] = 1, ["y"] = 1 },
    },
  },
  ["sharedData"] = {
    ["sender-one"] = { ["at"] = 5, ["writs"] = {
      [3383] = { ["z"] = "Barrens", ["n"] = "Shared Name", ["x"] = 10, ["y"] = 10 },
      [5996] = { ["z"] = "Westfall", ["n"] = "Gryan Stoutmantle", ["m"] = 1436, ["x"] = 56.3, ["y"] = 47.5 },
      [3385] = { ["z"] = "Duskwood", ["x"] = 400, ["y"] = 1 },
    } },
  },
  ["myPrices"] = { [3383] = 999 },
}
"""

failures = 0


def check(label, got, want):
    global failures
    ok = got == want
    failures += 0 if ok else 1
    print(f"  {'ok  ' if ok else 'FAIL'}  {label:<48} {got!r}" + ("" if ok else f", wanted {want!r}"))


with tempfile.TemporaryDirectory() as folder:
    save = os.path.join(folder, "Blackthornes_TS.lua")
    with open(save, "w", encoding="utf-8") as f:
        f.write(SAVE)
    tool.OUTPUT = os.path.join(folder, "ForeverWritCustomers.lua")

    tool.main([])
    with open(tool.OUTPUT, encoding="utf-8") as f:
        empty = f.read()
    print("with no save:")
    check("ships an empty list", "ns.WRIT_CUSTOMERS = {\n}" in empty, True)

    tool.main([save])
    with open(tool.OUTPUT, encoding="utf-8") as f:
        own = f.read()
    print("the save's own spots:")
    check("keeps a customer's spot", '[3383] = { name = "Tilda Hand", zone = "Ashenvale", mapID = 1440, x = 34.6, y = 48.1 },' in own, True)
    check("keeps a quest log spot as one", "fromLog = true" in own, True)
    check("skips colour codes", "Bad" not in own and "3385" not in own, True)
    check("skips items no writ asks for", "999999" not in own, True)
    check("never writes when it was seen", "1790000000" not in own, True)
    check("reads nothing else from the save", "999" not in own.replace("1440", ""), True)
    check("leaves out what players sent", "Shared Name" not in own, True)

    os.remove(tool.OUTPUT)
    tool.main(["--shared", save])
    with open(tool.OUTPUT, encoding="utf-8") as f:
        shared = f.read()
    print("with what players sent:")
    check("the save's own spot beats a shared one", '"Tilda Hand"' in shared and "Shared Name" not in shared, True)
    check("a shared customer spot beats a log spot", '[5996] = { name = "Gryan Stoutmantle", zone = "Westfall", mapID = 1436, x = 56.3, y = 47.5 },' in shared, True)
    check("skips a bad shared spot", "3385" not in shared, True)
    check("never writes a sender id", "sender-one" not in shared, True)

    tool.main([save])
    with open(tool.OUTPUT, encoding="utf-8") as f:
        again = f.read()
    print("run again:")
    check("keeps what the file already holds", "Gryan Stoutmantle" in again, True)

if failures:
    print(f"{failures} check(s) failed")
    sys.exit(1)
print("all good")
