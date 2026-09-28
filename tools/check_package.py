"""Check a built package is clear to post before anything is uploaded.

Trent (2026-09-25): "always check that it's clear to post." The release
workflow builds the package without uploading, runs this over it, and only
uploads if it passes:

    python tools/check_package.py .release/Blackthornes_TS

It fails on anything that should not leave this machine or this repository:

- a file or folder that is not part of the addon itself (tools, scripts,
  saved variables, anything unexpected);
- text that looks private: a Windows path like D:\\..., an email address, a
  saved-variables dump, a WTF\\Account path, or anything shaped like an API
  token or key;
- a TOC whose version was never filled in by the tag.

A new kind of file is refused until it is added to ALLOWED below, so the
list of what ships only grows on purpose.
"""

import os
import re
import sys

ADDON = "Blackthornes_TS"

# What a player's install is made of. Anything else is refused.
ALLOWED_TOP = {"Blackthornes_TS.toc", "Core", "Data", "Logic", "UI",
               "Media", "Probe", "LICENSE", "CHANGELOG.md"}
ALLOWED_EXT = {".lua", ".toc", ".xml", ".tga", ".blp", ".ogg", ".md", ""}

# Never shipped, wherever it turns up.
FORBIDDEN_NAMES = {"BlackthornesTSDB.lua", "BlackthornesTSCharDB.lua",
                   "Blackthornes_TS.lua", "Snapshot.lua", "deploy.ps1",
                   "CLAUDE.md", ".pkgmeta"}

PRIVATE = [
    ("a Windows path", re.compile(r"\b[A-Za-z]:\\[^\s\"']")),
    ("an email address", re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")),
    # A real account folder, not a placeholder like WTF\Account\<id>.
    ("a WTF account path",
     re.compile(r"WTF[\\/]+Account[\\/]+[A-Za-z0-9#]", re.I)),
    # What the client writes: the table opens and its first key follows on
    # the next line. The addon's own `BlackthornesTSDB = {}` is not one. The
    # saved data holds characters, prices and auctions.
    ("a saved-variables dump",
     re.compile(r"^BlackthornesTS(Char)?DB\s*=\s*\{\s*\n\s*\[", re.M)),
    ("a GitHub token", re.compile(r"\b(ghp|gho|ghs|ghu|github_pat)_[A-Za-z0-9_]{20,}")),
    ("a private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("an API key or token", re.compile(
        r"(api[_-]?key|api[_-]?token|secret|password)\s*[=:]\s*[\"'][^\"']{8,}",
        re.I)),
]

# Text files only; images are not scanned for words.
TEXT_EXT = {".lua", ".toc", ".xml", ".md", ""}


def check(package_dir):
    """Return a list of problems; empty means the package is clear to post."""
    problems = []
    if not os.path.isdir(package_dir):
        return ["no package at %s" % package_dir]

    for entry in sorted(os.listdir(package_dir)):
        if entry not in ALLOWED_TOP:
            problems.append("%s is not part of the addon" % entry)

    for folder, dirs, files in os.walk(package_dir):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(folder, name)
            rel = os.path.relpath(path, package_dir).replace(os.sep, "/")
            ext = os.path.splitext(name)[1].lower()

            if name in FORBIDDEN_NAMES or name.startswith("."):
                problems.append("%s must never ship" % rel)
                continue
            if ext not in ALLOWED_EXT:
                problems.append("%s: %s files are not part of the addon"
                                % (rel, ext))
                continue
            if ext not in TEXT_EXT:
                continue

            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
            for label, pattern in PRIVATE:
                match = pattern.search(text)
                if match:
                    line = text.count("\n", 0, match.start()) + 1
                    problems.append("%s line %d looks like %s"
                                    % (rel, line, label))

    toc = os.path.join(package_dir, ADDON + ".toc")
    if os.path.isfile(toc):
        with open(toc, encoding="utf-8") as f:
            text = f.read()
        if "@project-version@" in text:
            problems.append("the TOC version was never set from the tag")
    else:
        problems.append("%s.toc is missing" % ADDON)

    return problems


def main(argv):
    if len(argv) != 2:
        print("usage: python tools/check_package.py .release/%s" % ADDON)
        return 2
    problems = check(argv[1])
    for problem in problems:
        print("Not clear to post: " + problem)
    if not problems:
        print("Clear to post: nothing private or unexpected in the package.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
