"""Print the checklist items a change touches, from Docs/change-checklist.md.

    python tools/checklist_for_change.py              changes since origin/main
    python tools/checklist_for_change.py --base REF   changes since REF
    python tools/checklist_for_change.py --list       every item, by name

Each item in Docs/change-checklist.md is a "## " heading followed by:

    Files: a regular expression matched against each changed file's path
    Lines: a regular expression matched against each added or removed line
    Check: what to make sure of before the PR opens
    Why:   the miss it came from

An item needs Files or Lines (or both: then either one matching is enough).
Only the items whose trigger matches are printed, so nobody has to remember
every past miss. Uncommitted changes count too.

This only prints; it never fails. The same file lives in all five addons; a
fix belongs in all.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECKLIST = os.path.join(ROOT, "Docs", "change-checklist.md")
FIELDS = ("Files", "Lines", "Check", "Why")


def read_items(text):
    """The checklist's items as dicts with name and the four fields."""
    items, item = [], None
    for raw in text.splitlines():
        line = raw.rstrip()
        if line.startswith("## "):
            item = {"name": line[3:].strip()}
            items.append(item)
            continue
        if item is None:
            continue
        for field in FIELDS:
            if line.startswith(field + ":"):
                item[field] = line[len(field) + 1:].strip()
                break
        else:
            last = item.get("_last")
            if last and line.startswith("  ") and line.strip():
                item[last] += " " + line.strip()
            continue
        item["_last"] = field
    return [i for i in items if i.get("Files") or i.get("Lines")]


def matches(item, paths, lines):
    if item.get("Files"):
        pattern = re.compile(item["Files"])
        if any(pattern.search(p) for p in paths):
            return True
    if item.get("Lines"):
        pattern = re.compile(item["Lines"])
        if any(pattern.search(l) for l in lines):
            return True
    return False


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=False)


def change(base):
    """(changed paths, changed lines) since base, or None without a base."""
    merge_base = git("merge-base", base, "HEAD")
    if merge_base.returncode != 0:
        return None
    diff = git("diff", "--unified=0", "--no-color", merge_base.stdout.strip())
    if diff.returncode != 0:
        return None
    paths, lines = [], []
    for raw in diff.stdout.splitlines():
        if raw.startswith("+++ b/") or raw.startswith("--- a/"):
            path = raw[6:]
            if path not in paths:
                paths.append(path)
        elif raw[:1] in "+-" and not raw.startswith(("+++", "---")):
            lines.append(raw[1:])
    return paths, lines


def main(args):
    with open(CHECKLIST, encoding="utf-8") as handle:
        items = read_items(handle.read())
    if "--list" in args:
        for item in items:
            print("- " + item["name"])
        return 0
    base = args[args.index("--base") + 1] if "--base" in args else "origin/main"
    found = change(base)
    if found is None:
        print("Checklist: no %s to compare with. Run with --list to see every item." % base)
        return 0
    paths, lines = found
    hits = [i for i in items if matches(i, paths, lines)]
    if not hits:
        print("Checklist: nothing in Docs/change-checklist.md applies to this change.")
        return 0
    print("Checklist: %d of %d items apply to this change." % (len(hits), len(items)))
    for item in hits:
        print("\n## %s\nCheck: %s" % (item["name"], item.get("Check", "")))
        if item.get("Why"):
            print("Why: %s" % item["Why"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
