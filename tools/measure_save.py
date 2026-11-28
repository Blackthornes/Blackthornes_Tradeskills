"""Show which saved tables fill a Tradeskills save. Read only.

Run: python tools/measure_save.py <path to Blackthornes_TS.lua> [--min 0.5] [--depth 6] [--ages]

The game reads the whole save at every login and /reload, so its size is
the wait Tradeskills adds there. This prints how many bytes each saved
table takes, so the work to shrink it goes where the size is.

It never writes anything and never prints a value. Keys are printed only
when they are a word the addon's own code uses (`prices`, `history`,
`market`); every other key (a realm, a character, an item, a name) is
shown as `*`, and the rows under it are added up. So the output holds no
names, prices or anything else from the player's game, and is safe to
share. Never commit a save; `tools/check_private_files.py` refuses one.

Each row: size, share of the file, how many entries were added up, path.
"""

import argparse
import os
import re
import sys

TOKEN = re.compile(
    r'\s+'
    r'|--\[(?P<eq>=*)\[.*?\](?P=eq)\]'
    r'|--[^\n]*'
    r'|"(?:[^"\\]|\\.)*"'
    r"|'(?:[^'\\]|\\.)*'"
    r'|[\[\]{}=,;]'
    r'|-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)'
    r'|[A-Za-z_][A-Za-z0-9_]*'
    r'|.',
    re.S,
)
WORD = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SKIP = ("s", "c")  # whitespace, comment


def code_words(root):
    """Every word the addon's own Lua code uses: the keys safe to print."""
    words = set()
    for folder in ("Core", "Data", "Logic", "UI"):
        base = os.path.join(root, folder)
        if not os.path.isdir(base):
            continue
        for dirpath, _, files in os.walk(base):
            for name in files:
                if not name.endswith(".lua"):
                    continue
                try:
                    with open(os.path.join(dirpath, name), encoding="utf-8", errors="replace") as f:
                        words.update(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", f.read()))
                except OSError:
                    pass
    return words


def tokens(text):
    """(kind, text, end) for each token; kind s, c, str, num, word or the mark."""
    for m in TOKEN.finditer(text):
        t = m.group(0)
        ch = t[0]
        if ch.isspace():
            kind = "s"
        elif t.startswith("--"):
            kind = "c"
        elif ch in "\"'":
            kind = "str"
        elif ch.isdigit() or (ch in "-." and len(t) > 1):
            kind = "num"
        elif WORD.match(t):
            kind = "word"
        else:
            kind = t
        yield kind, t, m.end()


def measure(text, safe, aged=None):
    """{path tuple: [bytes, entries]} for every table and value in `text`.

    With `aged` (a list), each table that holds a `seen` number adds
    (path, seen, bytes) to it, so rows can be added up by age.
    """
    stats = {}

    def name(key, is_word):
        if is_word and key in safe:
            return key
        return "*"

    def add(path, size):
        row = stats.get(path)
        if row is None:
            stats[path] = [size, 1]
        else:
            row[0] += size
            row[1] += 1

    stack = [{"path": (), "start": 0, "next": 1}]
    last_end = 0
    toks = tokens(text)
    pending = []

    def next_tok():
        if pending:
            return pending.pop()
        for tok in toks:
            if tok[0] not in SKIP:
                return tok
        return None

    while True:
        tok = next_tok()
        if tok is None:
            break
        kind, t, end = tok
        frame = stack[-1]
        if kind in (",", ";"):
            continue
        if kind == "}":
            if len(stack) == 1:
                continue
            stack.pop()
            add(frame["path"], end - frame["start"])
            if aged is not None and frame.get("seen") is not None:
                aged.append((frame["path"], frame["seen"], end - frame["start"]))
            last_end = end
            continue

        entry_start = last_end
        key, is_word = None, False
        if kind == "[":
            ktok = next_tok()
            close = next_tok()
            eq = next_tok()
            if ktok is None or close is None or eq is None:
                break
            if ktok[0] == "str":
                key, is_word = ktok[1][1:-1], bool(WORD.match(ktok[1][1:-1]))
            else:
                key = ktok[1]
            tok = next_tok()
        elif kind == "word" and t not in ("true", "false", "nil"):
            after = next_tok()
            if after is not None and after[0] == "=":
                key, is_word = t, True
                tok = next_tok()
            else:
                if after is not None:
                    pending.append(after)
        if tok is None:
            break
        if key is None:
            key = str(frame["next"])
            frame["next"] += 1
        path = frame["path"] + (name(key, is_word),)
        kind, t, end = tok
        if kind == "{":
            stack.append({"path": path, "start": entry_start, "next": 1})
            last_end = end
        else:
            add(path, end - entry_start)
            if aged is not None and key == "seen" and kind == "num":
                try:
                    frame["seen"] = float(t)
                except ValueError:
                    pass
            last_end = end
    return stats


AGES = ((14, "under 14 days"), (30, "14 to 30 days"), (90, "30 to 90 days"),
        (365, "90 days to a year"), (None, "over a year"))


def age_report(aged, min_rows=50):
    """Rows that hold a `seen` time, added up by how old they are next to the
    newest one in the save. Counts and sizes only."""
    if not aged:
        return []
    newest = max(seen for _, seen, _ in aged)
    buckets = {}
    for path, seen, size in aged:
        days = (newest - seen) / 86400.0
        for limit, label in AGES:
            if limit is None or days < limit:
                break
        row = buckets.setdefault((path, label), [0, 0])
        row[0] += 1
        row[1] += size
    order = {label: i for i, (_, label) in enumerate(AGES)}
    lines = []
    for (path, label) in sorted(buckets, key=lambda k: (k[0], order[k[1]])):
        count, size = buckets[(path, label)]
        if count >= min_rows:
            lines.append("%s %9d  %-18s %s" % (fmt_size(size), count, label, ".".join(path)))
    return lines


def fmt_size(n):
    if n >= 1024 * 1024:
        return "%7.2f MB" % (n / 1024 / 1024)
    if n >= 1024:
        return "%7.1f KB" % (n / 1024)
    return "%7d B " % n


def report(stats, total, min_share, depth):
    lines = []
    for path in sorted(stats):
        size, count = stats[path]
        if len(path) > depth or size * 100.0 < total * min_share:
            continue
        label = ".".join(path)
        lines.append("%s %5.1f%% %9d  %s%s" % (
            fmt_size(size), size * 100.0 / total, count, "  " * (len(path) - 1), label))
    return lines


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("save", help="the saved variables file to measure (read only)")
    parser.add_argument("--min", type=float, default=0.5, help="hide rows under this share of the file, in percent")
    parser.add_argument("--depth", type=int, default=6, help="how deep to show")
    parser.add_argument("--ages", action="store_true", help="also add up rows by how long since they were seen")
    args = parser.parse_args(argv)

    # Latin-1 keeps one character per byte, so sizes are true bytes.
    with open(args.save, encoding="latin-1") as f:
        text = f.read()
    total = len(text)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    aged = [] if args.ages else None
    stats = measure(text, code_words(root), aged)
    print("Whole file: %s in %d lines" % (fmt_size(total).strip(), text.count("\n") + 1))
    print("   size     share   entries  path")
    for line in report(stats, max(total, 1), args.min, args.depth):
        print(line)
    if aged is not None:
        print("")
        print("Rows by age (next to the newest scan in the save):")
        print("   size        rows  age                path")
        for line in age_report(aged):
            print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
