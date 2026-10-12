"""Checks the translations against the words the addon shows.

Run from the repository root:

    python tools/check_locale.py

Every string a player reads is wrapped in L["..."] or L.Format("...", ...)
(Locale/Locale.lua), with the English text as the key. This lists:

  * every key the code uses that a translation file (Locale/deDE.lua, and any
    other Locale/xxXX.lua) has no line for, so it would show in English;
  * every line in a translation file whose key the code no longer uses.

It only warns: it always exits 0, so a missing line never stops a build.
A key built at run time (L[variable]) cannot be seen here; keep keys as
literals where they are written.

The same file is meant for every Blackthornes addon: it finds the addon's
own folders, and a fix to it belongs in all of them once they have it.
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Folders that hold the addon's own Lua. Probe/ is for us and stays English;
# tools/ never ships; Locale/ holds the translations themselves.
SKIP = {"tools", "Probe", "Locale", ".git", ".github", "docs", "Libs", "libs"}

STRING = r'"((?:[^"\\\n]|\\.)*)"'
USE = re.compile(r'(?<![\w.])L(?:\[\s*' + STRING + r'\s*\]|\.Format\(\s*' + STRING + r')')
LINE = re.compile(r'^\s*L\[\s*' + STRING + r'\s*\]\s*=', re.M)


def strip_comments(text):
    """The Lua with its comments blanked out, strings kept."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("--[[", i) or text.startswith("--[==[", i):
            close = "]]" if text.startswith("--[[", i) else "]==]"
            j = text.find(close, i)
            j = n if j < 0 else j + len(close)
            out.append("\n" * text.count("\n", i, j))
            i = j
        elif text.startswith("--", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def lua_files(root):
    for folder, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP)
        for name in sorted(files):
            if name.endswith(".lua"):
                yield os.path.join(folder, name)


def used_keys(root):
    """{ key: [where it is used] } across the addon's Lua."""
    keys = {}
    for path in lua_files(root):
        with open(path, encoding="utf-8") as handle:
            text = strip_comments(handle.read())
        for number, line in enumerate(text.split("\n"), 1):
            for match in USE.finditer(line):
                key = match.group(1) if match.group(1) is not None else match.group(2)
                where = "%s:%d" % (os.path.relpath(path, root), number)
                keys.setdefault(key, []).append(where)
    return keys


def translation_files(root):
    return sorted(p for p in glob.glob(os.path.join(root, "Locale", "*.lua"))
                  if re.fullmatch(r"[a-z]{2}[A-Z]{2}\.lua", os.path.basename(p)))


def translated_keys(path):
    with open(path, encoding="utf-8") as handle:
        text = strip_comments(handle.read())
    return LINE.findall(text)


def main(argv):
    root = argv[0] if argv else ROOT
    keys = used_keys(root)
    files = translation_files(root)
    print("%d keys in the code" % len(keys))
    if not files:
        print("warning: no translation files in Locale/")
        return 0
    for path in files:
        name = os.path.relpath(path, root)
        lines = translated_keys(path)
        have = set(lines)
        missing = sorted(k for k in keys if k not in have)
        unused = sorted(k for k in have if k not in keys)
        twice = sorted({k for k in lines if lines.count(k) > 1})
        print("%s: %d lines, %d missing, %d unused" % (name, len(have), len(missing), len(unused)))
        for key in missing:
            print('  warning: missing in %s: L["%s"]  (%s)' % (name, key, keys[key][0]))
        for key in unused:
            print('  warning: unused in %s: L["%s"]' % (name, key))
        for key in twice:
            print('  warning: twice in %s: L["%s"]' % (name, key))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
