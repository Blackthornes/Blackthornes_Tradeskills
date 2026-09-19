"""Run the addon's pure-logic tests outside WoW, against a real Lua 5.1 runtime.

    python tools/runtests.py

Every tools/test_*.lua is run, in name order. There is deliberately no list of
test files here: one used to exist, and because each new test appended to it,
any two branches adding tests collided on the same line. Four merges in one day
conflicted on nothing but that list. Discovering the files instead means a new
test is a new file and nothing else.

It also found two suites that were passing and being skipped -- test_persist
and test_serialize were never added to the list.

A suite fails by raising, which is what the assert and error calls in each file
do. All of them run regardless, so one failure does not hide the rest.
"""

import glob
import os
import sys

from lupa import lua51 as luamod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_files():
    pattern = os.path.join(ROOT, "tools", "test_*.lua")
    return sorted(glob.glob(pattern), key=os.path.basename)


def main() -> int:
    lua = luamod.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = [[%s/?.lua;]] .. package.path" % ROOT.replace("\\", "/"))
    lua.execute("lfs_cwd = [[%s]]" % ROOT.replace("\\", "/"))

    scripts = test_files()
    if not scripts:
        print("no test files found in tools/", file=sys.stderr)
        return 1

    failed = []

    for path in scripts:
        name = os.path.basename(path)
        try:
            lua.execute("dofile([[%s]])" % path.replace("\\", "/"))
        except Exception as error:          # a Lua error, surfaced as LuaError
            failed.append(name)
            print("\nFAIL -- %s\n%s" % (name, error), file=sys.stderr)

    print("\n%d suite(s) run, %d failure(s)" % (len(scripts), len(failed)))

    for name in failed:
        print("  failed: %s" % name)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
