"""Tests for tools/check_package.py. Run: python tools/test_check_package.py

Each case builds a small fake package in a temporary folder and checks the
verdict, so a check that stops catching something fails here first.
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_package import check  # noqa: E402

TOC = ("## Interface: 16001\n## Version: v0.2.0\n\nCore\\Init.lua\n")
CLEAN = {
    "Blackthornes_TS.toc": TOC,
    "Core/Init.lua": "local _, ns = ...\nBlackthornesTSDB = {}\n",
    "Data/Data_Cloth.lua": "-- Wool Cloth\n",
    "CHANGELOG.md": "# Changelog\n\n## 0.2.0\n",
    "LICENSE": "MIT License\n",
}

checks = 0
failures = 0


def build(files):
    root = tempfile.mkdtemp()
    for rel, text in files.items():
        path = os.path.join(root, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    return root


def expect(label, files, clear):
    global checks, failures
    checks += 1
    problems = check(build(files))
    if (problems == []) != clear:
        failures += 1
        print("FAIL: %s -> %s" % (label, problems or "passed"))


def with_(extra):
    files = dict(CLEAN)
    files.update(extra)
    return files


expect("a clean package is clear", CLEAN, True)
expect("the tools folder is refused", with_({"tools/runtests.py": "print()\n"}), False)
expect("the translations are allowed",
       with_({"Locale/Locale.lua": "local _, ns = ...\n", "Locale/deDE.lua": "local _, ns = ...\n"}), True)
expect("a stray script is refused", with_({"deploy.ps1": "x\n"}), False)
expect("the README is refused", with_({"README.md": "# Readme\n"}), False)
expect("the Claude notes are refused", with_({"CLAUDE.md": "# Notes\n"}), False)
expect("the Claude notes are refused anywhere",
       with_({"Core/CLAUDE.md": "# Notes\n"}), False)
expect("a probe is allowed", with_({"Probe/Probe.lua": "local _, ns = ...\n"}), True)
expect("a saved-variables file is refused by name",
       with_({"Data/BlackthornesTSDB.lua": "-- saved\n"}), False)
expect("a saved-variables file is refused",
       with_({"Data/Saved.lua": 'BlackthornesTSCharDB = {\n\t["bags"] = {},\n}\n'}),
False)
expect("a Windows path is refused",
       with_({"Core/Util.lua": 'local p = "D:\\\\Blizzard\\\\World of Warcraft"\n'}),
False)
expect("an email address is refused",
       with_({"Core/Util.lua": "-- mail someone@example.com\n"}), False)
expect("the owner's name is refused",
       with_({"Core/Util.lua": "-- asked by " + "Tr" + "ent\n"}), False)
expect("a word that only holds those letters is allowed",
       with_({"Core/Util.lua": "-- a torrent of loot\n"}), True)
expect("a WTF account path is refused",
       with_({"Core/Util.lua": "-- WTF/Account/NAME/SavedVariables\n"}), False)
expect("a placeholder account path is allowed",
       with_({"Core/Util.lua": "-- WTF\\Account\\<id>\\SavedVariables\n"}), True)
expect("a GitHub token is refused",
       with_({"Core/Util.lua": "local t = 'ghp_" + "a" * 36 + "'\n"}), False)
expect("an API key is refused",
       with_({"Core/Util.lua": 'local api_key = "abcdefghijkl"\n'}), False)
# Our auction house window is not finished, so no package may carry it.
expect("the unfinished auction window is refused",
       with_({"UI/AuctionWindow.lua": "local _, ns = ...\n"}), False)
expect("the veil it needs is refused with it",
       with_({"UI/Veil.lua": "local _, ns = ...\n"}), False)
expect("its Browse search is refused with it",
       with_({"Logic/Browse.lua": "local _, ns = ...\n"}), False)
expect("its Browse tab is refused with it",
       with_({"UI/AuctionBrowse.lua": "local _, ns = ...\n"}), False)
expect("a TOC that loads the unfinished Browse tab is refused",
       with_({"Blackthornes_TS.toc": TOC + "UI\\AuctionBrowse.lua\n"}), False)
expect("a TOC that loads the unfinished window is refused",
       with_({"Blackthornes_TS.toc": TOC + "UI\\AuctionWindow.lua\n"}), False)


def unfinished_is_fenced():
    """The real TOC and .pkgmeta both keep the unfinished files out."""
    global checks, failures
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(root, "Blackthornes_TS.toc"), encoding="utf-8") as f:
        lines = [line.strip() for line in f.read().splitlines()]
    with open(os.path.join(root, ".pkgmeta"), encoding="utf-8") as f:
        pkgmeta = f.read()
    from check_package import NOT_FINISHED
    for rel in sorted(NOT_FINISHED):
        listed = rel.replace("/", "\\")
        fenced = False
        if listed in lines:
            at = lines.index(listed)
            before = [l for l in lines[:at] if l.startswith("#@")]
            after = [l for l in lines[at:] if l.startswith("#@")]
            fenced = (bool(before) and before[-1] == "#@do-not-package@"
                      and bool(after) and after[0] == "#@end-do-not-package@")
        for label, ok in (("the TOC keeps %s out of the package" % rel, fenced),
                          (".pkgmeta ignores %s" % rel, ("- " + rel) in pkgmeta)):
            checks += 1
            if not ok:
                failures += 1
                print("FAIL: " + label)


unfinished_is_fenced()

expect("an unset version is refused",
       with_({"Blackthornes_TS.toc": TOC.replace("v0.2.0", "@project-version@")}),
False)
checks += 1
if check(os.path.join(tempfile.mkdtemp(), "nothing")) == []:
    failures += 1
    print("FAIL: a missing package is refused")

print("  check_package: %d checks, %d failure(s)" % (checks, failures))
sys.exit(1 if failures else 0)
