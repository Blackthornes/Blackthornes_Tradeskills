"""Refuse to release a tag the changelog says nothing about.

Run by .github/workflows/release.yml before anything is packaged:

    python tools/check_release.py v0.2.0

The tag must look like vMAJOR.MINOR.PATCH (a suffix such as -beta1 is allowed,
and makes the packager mark the upload as a beta), and CHANGELOG.md must open
with a section for that version, "## 0.2.0" or "## 0.2.0 - 2026-09-25". That
is what players read on CurseForge, so a release without it is refused rather
than shipped with last version's notes.

It also refuses a CHANGELOG.md or NEWS.md section that credits a player by
name: a player's name never goes in a report.

It also checks the TOC still says `## Version: @project-version@`: a version
typed in by hand would disagree with the tag the packager builds.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAG = re.compile(r"^v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)$")
HEADING = re.compile(r"^##\s+v?(\S+)")


def check(tag, changelog, toc):
    """Return a list of problems; empty means the tag can be released."""
    match = TAG.match(tag)
    if not match:
        return ["tag %r is not like v0.2.0 (or v0.2.0-beta1)" % tag]
    version = match.group(1)

    problems = []
    headings = [HEADING.match(line).group(1)
                for line in changelog.splitlines() if HEADING.match(line)]
    if not headings:
        problems.append("CHANGELOG.md has no '## <version>' sections")
    elif headings[0] != version:
        if version in headings:
            problems.append("CHANGELOG.md has %s, but not as the newest "
                            "section at the top (that is %s)"
                            % (version, headings[0]))
        else:
            problems.append("CHANGELOG.md has no section for %s; add "
                            "'## %s' at the top saying what changed"
                            % (version, version))

    if not re.search(r"^## Version: @project-version@\s*$", toc, re.M):
        problems.append("Blackthornes_TS.toc must say "
                        "'## Version: @project-version@' so the tag sets it")
    return problems


def named_players(tag, changelog):
    """A player's name never goes in a report (the owner, 2026-10-09): look in
    this version's CHANGELOG.md and NEWS.md sections, which go to CurseForge
    and Discord, for a credited player."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from announce_discord import section
    from post_general import names_a_player
    match = TAG.match(tag)
    if not match:
        return []
    texts = [("CHANGELOG.md", changelog)]
    news = os.path.join(ROOT, "NEWS.md")
    if os.path.exists(news):
        with open(news, encoding="utf-8") as f:
            texts.append(("NEWS.md", f.read()))
    problems = []
    for name, text in texts:
        for player in names_a_player(section(text, match.group(1)) or ""):
            problems.append("%s names a player (%s); thank everyone instead"
                            % (name, player))
    return problems


def main(argv):
    if len(argv) != 2:
        print("usage: python tools/check_release.py v0.2.0")
        return 2
    with open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8") as f:
        changelog = f.read()
    with open(os.path.join(ROOT, "Blackthornes_TS.toc"), encoding="utf-8") as f:
        toc = f.read()
    problems = check(argv[1], changelog, toc) + named_players(argv[1], changelog)
    for problem in problems:
        print("Not releasing: " + problem)
    if not problems:
        print("%s is ready to release." % argv[1])
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
