"""Tests for tools/measure_save.py. Run: python tools/test_measure_save.py"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measure_save import measure  # noqa: E402

SAVE = '''
BlackthornesTSDB = {
\t["prices"] = {
\t\t["Some Realm - Alliance"] = {
\t\t\t[2589] = {
\t\t\t\t["market"] = 120,
\t\t\t\t["history"] = {
\t\t\t\t\t1700000000, -- [1]
\t\t\t\t\t120, -- [2]
\t\t\t\t\tfalse, -- [3]
\t\t\t\t},
\t\t\t\t["name"] = "Linen \\"Cloth\\" ]] = {",
\t\t\t},
\t\t\t[2592] = {
\t\t\t\t["market"] = 300,
\t\t\t},
\t\t},
\t},
\t["Bobby"] = 1,
}
'''
SAFE = {"BlackthornesTSDB", "prices", "market", "history", "name"}

checks = 0
failures = 0


def expect(label, got, want):
    global checks, failures
    checks += 1
    if got != want:
        failures += 1
        print(f"FAIL {label}: got {got}, want {want}")


stats = measure(SAVE, SAFE)
db = ("BlackthornesTSDB",)
item = db + ("prices", "*", "*")
expect("two items added up", stats[item][1], 2)
expect("market counted on both", stats[item + ("market",)][1], 2)
expect("history readings", stats[item + ("history", "*")][1], 3)
expect("children fit in the table", stats[item + ("market",)][0] + stats[item + ("history",)][0]
       + stats[item + ("name",)][0] <= stats[item][0], True)
expect("a string with marks in it stays one value", stats[item + ("name",)][1], 1)
expect("an unknown key is hidden", db + ("Bobby",) in stats, False)
expect("an unknown key is added up as *", stats[db + ("*",)][1], 1)
expect("no realm name shown", any("Realm" in p for path in stats for p in path), False)
expect("the whole save is measured", stats[db][0] <= len(SAVE), True)

print(f"  measure_save: {checks} checks, {failures} failure(s)")
sys.exit(1 if failures else 0)
