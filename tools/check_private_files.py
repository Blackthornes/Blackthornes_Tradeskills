"""Refuse files that must never be in the repo. Run: python tools/check_private_files.py

The repo is public, so a game save, a WTF folder, a keys file or a .env file
committed by mistake would be on show to everyone. This runs on every push and
pull request and fails if the repo holds one:

- anything inside a folder named WTF or SavedVariables
- a file named keys.txt, .env or .env.<anything> (.env.example is allowed)
- a .lua file outside tools/ that reads like a saved variables file the game
  wrote (a line such as `BlackthornesFarmerDB = {`); the made-up saves the
  tests use live under tools/
- a .bak copy of a .lua file

It checks every file git tracks, by name, and reads only .lua files.
"""

import os
import re
import subprocess
import sys

FOLDERS = {"wtf", "savedvariables"}
NAMES = {"keys.txt", ".env"}
SAVE_LINE = re.compile(r"^\w+DB = \{\s*$", re.M)


def problem(path, read):
    """Why `path` must not be committed, or None. `read(path)` gives its text."""
    parts = path.replace("\\", "/").split("/")
    name = parts[-1].lower()
    if any(p.lower() in FOLDERS for p in parts[:-1]):
        return "inside a WTF or SavedVariables folder"
    if name in NAMES or (name.startswith(".env.") and name != ".env.example"):
        return "a keys or .env file"
    if name.endswith(".lua.bak"):
        return "a backup of a Lua file"
    if name.endswith(".lua") and parts[0] != "tools":
        try:
            text = read(path)
        except OSError:
            return None
        if SAVE_LINE.search(text):
            return "looks like a saved variables file the game wrote"
    return None


def check(paths, read):
    """Every (path, reason) among `paths` that must not be committed."""
    found = []
    for path in paths:
        why = problem(path, read)
        if why:
            found.append((path, why))
    return found


def tracked():
    out = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


def read_file(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)
    found = check(tracked(), read_file)
    for path, why in found:
        print(f"NOT ALLOWED: {path} ({why})")
    if found:
        print(f"{len(found)} file(s) must come out of the repo before this can merge.")
        return 1
    print("No saved variables, WTF folders, keys or .env files in the repo.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
