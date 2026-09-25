"""Syntax-check every Lua file in the addon, and check the TOC lists real ones.

WoW silently disables an addon whose first TOC file fails to compile, with no
error and no hint, so this runs before every deploy.

The TOC check is here for the same reason. A TOC line naming a file that does
not exist is not an error in the game either: the file is simply never loaded,
and whatever was in it is missing with nothing to say so. That happened on
2026-09-20 -- a stray carriage return left behind by an edit turned
`Core\Persist.lua` into a name nothing matched, and the whole persistence
layer stopped loading while every Lua file still compiled perfectly.

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


def check_toc() -> int:
    """Every file the TOC lists must exist, spelled exactly as listed."""
    toc = glob.glob(os.path.join(ROOT, "*.toc"))
    if not toc:
        print("\n  FAIL  no .toc file found")
        return 1

    failures = 0

    for path in toc:
        # newline="" disables Python's newline translation. Without it a stray
        # carriage return is converted away before this code ever sees it, and
        # the check silently passes the exact file that broke the addon --
        # which is what the first version of this check did.
        with open(path, encoding="utf-8", newline="") as handle:
            for number, line in enumerate(handle, start=1):
                entry = line.rstrip("\n")

                if not entry.strip() or entry.lstrip().startswith("#"):
                    continue

                # Compared before stripping: trailing whitespace is invisible
                # in a diff and is exactly what broke this once already.
                if entry != entry.strip():
                    failures += 1
                    print("\n  FAIL  %s line %d: %r has stray whitespace"
                          % (os.path.basename(path), number, entry))
                    continue

                target = os.path.join(ROOT, entry.replace("\\", os.sep))

                if not os.path.isfile(target):
                    failures += 1
                    print("\n  FAIL  %s line %d: lists %s, which does not exist"
                          % (os.path.basename(path), number, entry))

    return failures


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

    failures += check_toc()

    print("\n%d file(s), %d failure(s)" % (len(files), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
