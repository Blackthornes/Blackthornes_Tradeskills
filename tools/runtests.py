"""Run the addon's pure-logic tests outside WoW, against a real Lua 5.1 runtime.

    python tools/runtests.py                 every suite, quiet unless one fails
    python tools/runtests.py mail queue      only suites with these words in the name
    python tools/runtests.py -v uifit        print every check as it runs

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


# Lua's print is swapped for one that keeps each suite's lines in a list. A
# full run used to print every passing check, about 590 KB, which nobody reads
# and which fills a terminal, a CI log or an assistant's working memory. Now a
# suite that passes prints nothing, and one that fails prints its last lines.
CAPTURE = """
__lines = {}
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    __lines[#__lines + 1] = table.concat(parts, "\\t")
end
function __tail(count)
    local first = math.max(1, #__lines - count + 1)
    return table.concat(__lines, "\\n", first)
end
"""

TAIL = 25


def main() -> int:
    args = sys.argv[1:]
    verbose = "-v" in args or "--verbose" in args
    wanted = [a for a in args if not a.startswith("-")]

    lua = luamod.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = [[%s/?.lua;]] .. package.path" % ROOT.replace("\\", "/"))
    lua.execute("lfs_cwd = [[%s]]" % ROOT.replace("\\", "/"))
    if not verbose:
        lua.execute(CAPTURE)

    scripts = test_files()
    if wanted:
        # Any part of a file name picks it: "mail" runs every test_*mail*.lua.
        scripts = [p for p in scripts
                   if any(w.lower() in os.path.basename(p).lower() for w in wanted)]
    if not scripts:
        print("no test files found in tools/", file=sys.stderr)
        return 1

    failed = []

    for path in scripts:
        name = os.path.basename(path)
        if not verbose:
            lua.execute("__lines = {}")
        try:
            lua.execute("dofile([[%s]])" % path.replace("\\", "/"))
        except Exception as error:          # a Lua error, surfaced as LuaError
            failed.append(name)
            print("\nFAIL -- %s\n%s" % (name, str(error)[:2000]), file=sys.stderr)
            if not verbose:
                tail = lua.eval("__tail(%d)" % TAIL)
                if tail:
                    print("  last lines it printed:\n%s" % tail[-3000:], file=sys.stderr)

    print("\n%d suite(s) run, %d failure(s)" % (len(scripts), len(failed)))

    for name in failed:
        print("  failed: %s" % name)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
