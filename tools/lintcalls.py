"""Find calls to addon methods, and constants, that are never defined.

A missing method is valid Lua: `self:Foo()` compiles fine and fails only when
that line runs, often deep in an event handler where it is easy to miss. A
constant deleted during a refactor is worse: it is nil, so the error surfaces
inside whatever Blizzard API received it rather than at the line that lost it.

The syntax check cannot see either, so this walks the addon's own code and
reports both.

Only checks the addon's own names, never Blizzard APIs, which are checked at
runtime by Compat instead.
"""

import collections
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DEFINITION = re.compile(r"^function\s+(\w+)[:.](\w+)\s*\(", re.MULTILINE)
NS_CALL = re.compile(r"\bns\.(\w+):(\w+)\s*\(")
SELF_CALL = re.compile(r"\bself:(\w+)\s*\(")
MODULE = re.compile(r'^local\s+(\w+)\s*=\s*ns\.NewModule\("(\w+)"\)', re.MULTILINE)

# ALL_CAPS names are this addon's file-local constants. The trailing boundary
# matters: without it "C_CVar" yields a bogus "C_CV".
CONST_USE = re.compile(r"(?:^|[^A-Za-z0-9_.:])([A-Z][A-Z0-9_]{2,})(?![A-Za-z0-9_])")

COMMENT = re.compile(r"--[^\n]*")
DQ_STRING = re.compile(r'"[^"\n]*"')
SQ_STRING = re.compile(r"'[^'\n]*'")
LONG_STRING = re.compile(r"\[\[.*?\]\]", re.DOTALL)

CONST_ASSIGN = re.compile(r"([A-Z][A-Z0-9_]{2,})[ \t]*(?:,[ \t]*[A-Za-z0-9_]+)*[ \t]*=")
LOCAL_ASSIGN = re.compile(r"local[ \t]+([A-Z][A-Z0-9_, \t]*?)[ \t]*=")

# Methods attached dynamically rather than with `function X:Y()`.
DYNAMIC = {
    "SetText", "SetEnabledState", "ApplyBaseColor", "SetValue", "GetValue",
    "SetOptions", "SetChecked", "GetChecked", "SetData", "GetData", "Refresh",
    "SetProgress", "Select", "IsRunning", "GetProgress", "Start", "Cancel",
    "UpdatePosition", "GetCharacterRecord", "UpdateRange", "FitContent",
}

# Widget methods: inside an OnDragStart or similar, `self` is the frame, not
# the module, so these are not undefined module calls.
FRAME_METHODS = {
    "SetScript", "StartMoving", "StopMovingOrSizing", "Show", "Hide",
    "SetPoint", "ClearAllPoints", "SetShown", "GetWidth", "GetHeight",
    "SetWidth", "SetHeight", "SetSize", "GetFrameLevel", "SetFrameLevel",
    "SetAllPoints", "CreateTexture", "SetFocus", "ClearFocus", "GetText",
    "HighlightText", "SetTextColor", "SetColorTexture", "GetPoint",
}

# Constants owned by WoW or Lua rather than by us.
KNOWN_GLOBALS = {
    "DEFAULT_CHAT_FRAME", "ITEM_QUALITY_COLORS", "UISpecialFrames",
    "BACKPACK_CONTAINER", "NUM_BAG_SLOTS", "BANK_CONTAINER",
    "REAGENTBANK_CONTAINER", "NUM_BANKBAGSLOTS", "SOUNDKIT",
    "LE_ITEM_CLASS_TRADEGOODS",
    # Localised UI strings.
    "YES", "NO", "ACCEPT", "CANCEL", "OKAY", "CLOSE", "NONE", "UNKNOWN",
}


def strip_prose(source):
    """Blank out comments and string literals.

    Both are full of capitalised words -- column headings, status text, font
    paths -- and none of them are identifiers.

    Strings go first. This addon writes plenty of user-facing text containing
    "--", and stripping comments first eats the closing quote and leaves the
    rest of the string looking like code.
    """
    source = LONG_STRING.sub("[[]]", source)
    source = DQ_STRING.sub('""', source)
    source = SQ_STRING.sub("''", source)
    source = COMMENT.sub("", source)
    return source


def main() -> int:
    files = sorted(glob.glob(os.path.join(ROOT, "**", "*.lua"), recursive=True))
    files = [f for f in files if "tools" not in os.path.relpath(f, ROOT).split(os.sep)]

    defined = collections.defaultdict(set)   # holder -> methods
    local_to_module = {}                     # local name -> module name
    sources = {}

    for path in files:
        with open(path, encoding="utf-8") as handle:
            source = handle.read()

        sources[path] = source

        for local, module in MODULE.findall(source):
            local_to_module[local] = module

        for holder, method in DEFINITION.findall(source):
            defined[holder].add(method)

    # A module's methods can be defined via its local alias.
    for local, module in local_to_module.items():
        defined[module] |= defined.get(local, set())
        defined[local] |= defined.get(module, set())

    problems = []

    for path, source in sources.items():
        relative = os.path.relpath(path, ROOT)

        for module, method in NS_CALL.findall(source):
            if method in DYNAMIC:
                continue
            if module in defined and method not in defined[module]:
                problems.append((relative, "ns.%s:%s" % (module, method)))

        # self: calls inside a file that defines exactly one module
        modules_here = MODULE.findall(source)
        if len(modules_here) == 1:
            local, module = modules_here[0]
            known = defined[module] | defined[local]

            for method in set(SELF_CALL.findall(source)):
                if method in DYNAMIC or method in FRAME_METHODS or method in known:
                    continue
                problems.append((relative, "self:%s (in %s)" % (method, module)))

        # Constants used but never assigned in the same file.
        code = strip_prose(source)

        assigned = set(CONST_ASSIGN.findall(code))
        for match in LOCAL_ASSIGN.finditer(code):
            for name in match.group(1).split(","):
                assigned.add(name.strip())

        for name in set(CONST_USE.findall(code)):
            if name in assigned or name in KNOWN_GLOBALS:
                continue
            problems.append((relative, "%s (constant never assigned)" % name))

    if problems:
        print("names with no matching definition:\n")
        for relative, call in sorted(set(problems)):
            print("  %-28s %s" % (relative, call))
        print("\n%d problem(s)" % len(set(problems)))
        return 1

    print("no undefined names found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
