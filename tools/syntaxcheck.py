"""Syntax-check every Lua file in the addon against a real Lua 5.1 parser.

WoW silently disables an addon whose first TOC file fails to compile, with no
error and no hint, so this runs before every deploy.

Requires: python -m pip install --user lupa
"""

import codecs
import glob
import os
import sys

try:
    from lupa import lua51 as luamod
    FLAVOR = "Lua 5.1 (matches WoW)"
except ImportError:  # pragma: no cover - fallback for older lupa builds
    import lupa as luamod
    FLAVOR = "fallback %s" % getattr(luamod, "LUA_VERSION", "unknown")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    lua = luamod.LuaRuntime(unpack_returned_tuples=True)
    compile_chunk = lua.eval(
        "function(source, name)"
        "  local fn, err = (loadstring or load)(source, name)"
        "  if fn then return true, '' else return false, tostring(err) end"
        " end"
    )

    files = sorted(glob.glob(os.path.join(ROOT, "**", "*.lua"), recursive=True))
    if not files:
        print("no Lua files found under", ROOT)
        return 1

    print("syntax check with %s\n" % FLAVOR)

    failures = 0
    for path in files:
        with open(path, "rb") as handle:
            raw = handle.read()

        # A byte-order mark makes WoW reject the file outright, so it is a
        # failure here rather than something to quietly strip.
        if raw.startswith(codecs.BOM_UTF8):
            failures += 1
            print("  FAIL  %s: starts with a UTF-8 BOM; WoW will not load it"
                  % os.path.relpath(path, ROOT))
            continue

        source = raw.decode("utf-8", errors="replace")

        ok, err = compile_chunk(source, os.path.basename(path))
        relative = os.path.relpath(path, ROOT)

        if ok:
            print("  OK    %s" % relative)
        else:
            failures += 1
            print("  FAIL  %s: %s" % (relative, err))

    print("\n%d file(s), %d failure(s)" % (len(files), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
