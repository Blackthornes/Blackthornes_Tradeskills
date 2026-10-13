"""Write Core/WhatsNewText.lua, the release notes the in-game What's New
window shows, from NEWS.md (the #general post, which does not ship).

    python tools/make_whatsnew.py            rewrite the file
    python tools/make_whatsnew.py --check    exit 1 when it is out of date

The window shows new features only. In a NEWS.md section, bullets after a
line that starts with "Fixes" and ends with a colon ("Fixes and changes:")
are fixes and other changes: they go to Discord but never into the window,
and a section with nothing above that line is left out of the window. The
newest MOST sections that have features go in, newest first, each a list of
its feature bullets. The thanks line is left out: it names players, and a
player's name never ships in the addon.

How a bullet should read: what the feature does, in a few plain words, the
way a person would say it to a friend. No hype, no questions to the reader,
no exclamation marks, no dashes as punctuation, no "now you can". The tool
prints a note (it never refuses) for a shipped bullet that trips STYLE. Every release PR that writes a NEWS.md section runs
this in the same breath; tools/check_release.py refuses a tag whose file is
out of date, and tools/test_make_whatsnew.py fails while it is.

This tool is the same in all five addons; a fix to it belongs in all five.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NEWS = os.path.join(ROOT, "NEWS.md")
OUT = os.path.join(ROOT, "Core", "WhatsNewText.lua")

# Sections shipped: a player who skipped a release or two still sees them.
MOST = 3

HEADING = re.compile(r"^##\s+v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)\s*(?:-.*)?$")
BULLET = re.compile(r"^\s*[-*+]\s+(.*)$")
# The line that starts a section's fixes and other changes, which stay out
# of the window: "Fixes:", "Fixes and changes:", "Fixed:".
FIXES = re.compile(r"^\s*\**(?:fixes|fixed)\b[^:]*:\**\s*$", re.IGNORECASE)

# Wording that reads like an advert, noted for shipped bullets.
STYLE = [
    (re.compile("[\u2014\u2013]"), "a dash as punctuation"),
    (re.compile(r"!"), "an exclamation mark"),
    # A question mark closing a quote ("You rang?") is the quote's own.
    (re.compile(r"\?(?![\"'])"), "a question to the reader"),
    (re.compile(r"\b(seamless(ly)?|effortless(ly)?|simply|magic(al)?|"
                r"supercharge|elevate|unlock|level up your|game.changer)\b",
                re.IGNORECASE), "an advert word"),
    (re.compile(r"\b(now you can|you can now|we've|we have)\b", re.IGNORECASE),
     "a sales phrase"),
    (re.compile(r"\b(a new what's new|what's new window)\b", re.IGNORECASE),
     "the window describing itself"),
]


def plain(text):
    """Markdown a chat frame cannot show, taken out: **bold**, `code`,
    [words](link)."""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"__(.+?)__", r"\1", text)
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    return re.sub(r"\s+", " ", text).strip()


def sections(news):
    """[(version, [bullet, ...]), ...] in the file's order, newest first.
    Only bullets count; a bullet's wrapped lines are joined to it, and any
    other paragraph (the thanks line) is left out."""
    found = []
    current = None
    bullet = None
    fixes = False
    for line in (news or "").splitlines():
        heading = HEADING.match(line)
        if heading:
            current = (heading.group(1), [])
            found.append(current)
            bullet, fixes = None, False
            continue
        if line.startswith("#"):
            current, bullet = None, None
            continue
        if current is None or fixes:
            continue
        if FIXES.match(line):
            fixes, bullet = True, None
            continue
        match = BULLET.match(line)
        if match:
            current[1].append(match.group(1))
            bullet = len(current[1]) - 1
        elif line.strip() and bullet is not None and line[:1] in (" ", "\t"):
            current[1][bullet] += " " + line.strip()
        else:
            bullet = None
    return [(version, [plain(b) for b in bullets if plain(b)])
            for version, bullets in found if bullets]


def style_notes(news):
    """["1.2.0: <bullet>: <what reads wrong>", ...] for the bullets that ship."""
    notes = []
    for version, bullets in sections(news)[:MOST]:
        for bullet in bullets:
            for pattern, what in STYLE:
                if pattern.search(bullet):
                    notes.append("%s: %s: %s" % (version, bullet, what))
    return notes


def lua_string(text):
    return '"' + (text.replace("\\", "\\\\").replace('"', '\\"')
                  .replace("\n", " ").replace("\r", " ")) + '"'


def render(news):
    """The whole Lua file for this NEWS.md text."""
    out = [
        "-- Core/WhatsNewText.lua",
        "-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:",
        "-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.",
        "",
        "local _, ns = ...",
        "",
        "ns.WHATS_NEW = {",
    ]
    for version, bullets in sections(news)[:MOST]:
        out.append("    { version = %s, lines = {" % lua_string(version))
        for bullet in bullets:
            out.append("        %s," % lua_string(bullet))
        out.append("    } },")
    out.append("}")
    return "\n".join(out) + "\n"


def read(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read()


def problems(news=None, current=None):
    """Empty when Core/WhatsNewText.lua is what NEWS.md makes. A repo
    without NEWS.md has nothing to check."""
    news = read(NEWS) if news is None else news
    if news is None:
        return []
    current = read(OUT) if current is None else current
    if current is None:
        return ["Core/WhatsNewText.lua is missing; run python tools/make_whatsnew.py"]
    if current.replace("\r\n", "\n") != render(news):
        return ["Core/WhatsNewText.lua is out of date with NEWS.md; run "
                "python tools/make_whatsnew.py"]
    return []


def main(argv):
    if "--check" in argv[1:]:
        found = problems()
        for problem in found:
            print(problem)
        if not found:
            print("Core/WhatsNewText.lua is up to date.")
        return 1 if found else 0
    news = read(NEWS)
    if news is None:
        print("No NEWS.md here; nothing to write.")
        return 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(render(news))
    print("Wrote Core/WhatsNewText.lua (%d sections)." % len(sections(news)[:MOST]))
    for note in style_notes(news):
        print("Note, reads like an advert: " + note)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
