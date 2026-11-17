"""Catch house rule slips in the lines a change adds, before a PR opens.

    python tools/check_house_rules.py              lines added since origin/main
    python tools/check_house_rules.py --base REF   lines added since REF
    python tools/check_house_rules.py --all        every line (a report; older
                                                   lines may still break a rule)

What it looks at:

- Player words: the English text inside L["..."] and L.Format("...") in the
  addon's .lua files. It flags em-dashes, hype words and questions to the
  reader ("Writing for players" under "Standing rules in full" in
  Docs/claude-notes.md).
- List colors: the old `row` and `rowAlt` bands, which every list replaced
  with dark glass ("Every list is dark glass").

A line that must break a rule on purpose (a slash command's "?" help word, a
quote of the game's own text) ends with the comment `-- house-ok` and is
skipped. Locale files, Data/, Libs/ and tools/ are never checked: the English
is the key, so the translations follow the English.

Exit code 1 when anything is flagged, 0 otherwise. With no git base to compare
against (a shallow checkout), it says so and passes.

The same file lives in all five addons; a fix belongs in all.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SKIP_DIRS = ("Locale/", "Data/", "Libs/", "libs/", "tools/", ".github/", "Docs/")

PLAYER_TEXT = re.compile(r'L(?:\.Format\s*\(\s*|\s*\[\s*)"((?:[^"\\]|\\.)*)"')

HYPE = (
    "seamless", "effortless", "now you can", "powerful", "game-changer",
    "game changer", "supercharge", "cutting-edge", "cutting edge",
    "revolutionary", "unleash", "elevate your", "at a glance of",
    "streamline", "robust",
)

OLD_ROWS = re.compile(r'(?<![A-Za-z_])(?:rowAlt|C\.row)(?![A-Za-z_])|["\']row["\']\s*[,)\]]')

# The theme itself still names the old colors; defining them is fine.
ROW_DEFINED = re.compile(r"\s*(?:C\.)?(?:row|rowAlt)\s*=")

OK_MARK = "-- house-ok"


def problems_in_line(line):
    """The rule slips on one line of Lua, as short reasons."""
    if OK_MARK in line:
        return []
    found = []
    for match in PLAYER_TEXT.finditer(line):
        text = match.group(1)
        low = text.lower()
        if "—" in text or " -- " in text:
            found.append("em-dash in player words: %s" % text[:60])
        for word in HYPE:
            if word in low:
                found.append('hype word "%s": %s' % (word, text[:60]))
        if text.rstrip().endswith("?"):
            found.append("question to the player: %s" % text[:60])
    if OLD_ROWS.search(line) and not ROW_DEFINED.match(line):
        found.append("old row/rowAlt band; lists use glass and glassAlt")
    return found


def checked_path(path):
    path = path.replace("\\", "/")
    return path.endswith(".lua") and not path.startswith(SKIP_DIRS)


def git(*args):
    return subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    )


def added_lines(base):
    """(path, line number, text) for every line added since base, or None."""
    merge_base = git("merge-base", base, "HEAD")
    if merge_base.returncode != 0:
        return None
    diff = git("diff", "--unified=0", "--no-color", merge_base.stdout.strip(), "--", "*.lua")
    if diff.returncode != 0:
        return None
    out, path, number = [], None, 0
    for raw in diff.stdout.splitlines():
        if raw.startswith("+++ "):
            path = raw[6:] if raw.startswith("+++ b/") else None
        elif raw.startswith("@@"):
            hunk = re.search(r"\+(\d+)", raw)
            number = int(hunk.group(1)) if hunk else 0
        elif raw.startswith("+") and path:
            out.append((path, number, raw[1:]))
            number += 1
    return out


def every_line():
    out = []
    for folder, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            full = os.path.join(folder, name)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            if not checked_path(rel):
                continue
            with open(full, encoding="utf-8", errors="replace") as handle:
                for number, text in enumerate(handle, 1):
                    out.append((rel, number, text.rstrip("\n")))
    return out


def main(args):
    if "--all" in args:
        lines = every_line()
    else:
        base = args[args.index("--base") + 1] if "--base" in args else "origin/main"
        lines = added_lines(base)
        if lines is None:
            print("House rules: no %s to compare with, nothing checked." % base)
            return 0
    flagged = 0
    for path, number, text in lines:
        if not checked_path(path):
            continue
        for reason in problems_in_line(text):
            flagged += 1
            print("%s:%d: %s" % (path, number, reason))
    if flagged:
        print("House rules: %d to fix (or mark the line %s if it is on purpose)." % (flagged, OK_MARK))
        return 1
    print("House rules: clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
