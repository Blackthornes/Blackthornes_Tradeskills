"""Checks tools/forever_vendor_spots.py: only the spots tables are read from
a save, bad rows are skipped, a save beats what is shipped, and when it was
seen is never written out.

    python tools/test_forever_vendor_spots.py
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import forever_vendor_spots as tool  # noqa: E402

SAVE = """
BlackthornesTSDB = {
  ["vendorSpots"] = {
    [340] = { ["name"] = "Kendor Kabonka", ["mapID"] = 1453, ["x"] = 70.1, ["y"] = 30.2,
      ["side"] = "A", ["at"] = 1790000000, ["items"] = { [2678] = true } },
    [341] = { ["name"] = "Bad Spot", ["mapID"] = 1453, ["x"] = 400, ["y"] = 30 },
    [342] = { ["name"] = 12, ["mapID"] = 1453, ["x"] = 1, ["y"] = 1 },
  },
  ["trainerSpots"] = {
    [1430] = { ["name"] = "Tomas", ["mapID"] = 1453, ["x"] = 77.5, ["y"] = 53.1, ["side"] = "A", ["at"] = 1 },
  },
  ["myPrices"] = { [2678] = 999 },
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
    tool.OUTPUT = os.path.join(folder, "ForeverVendorSpots.lua")
    with open(tool.OUTPUT, "w", encoding="utf-8") as f:
        f.write('local _, ns = ...\nns.FOREVER_VENDOR_SPOTS = {\n'
                '    [340] = { "Kendor Kabonka", 1453, 74.7, 36.5, "A", {} },\n'
                '    [99] = { "Old Shop", 1429, 1, 2, "", {} },\n}\n'
                'ns.FOREVER_TRAINER_SPOTS = {\n}\n')
    tool.main([save])
    with open(tool.OUTPUT, encoding="utf-8") as f:
        text = f.read()

check("the save's spot replaces the shipped one",
      '[340] = { "Kendor Kabonka", 1453, 70.1, 30.2, "A", { [2678] = true } },' in text, True)
check("a shipped spot the save lacks stays", '[99] = { "Old Shop", 1429, 1, 2, "", {} },' in text, True)
check("a spot off the map is skipped", "Bad Spot" in text, False)
check("a row with no name is skipped", "[342]" in text, False)
check("trainers are kept", '[1430] = { "Tomas", 1453, 77.5, 53.1, "A", {} },' in text, True)
check("when it was seen is not written", "1790000000" in text, False)
check("nothing else from the save", "999" in text, False)

print("")
if failures:
    sys.exit(f"{failures} check(s) failed")
print("  all vendor spot fold-in checks passed")
