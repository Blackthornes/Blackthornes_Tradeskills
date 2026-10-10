"""Tests for tools/check_private_files.py. Run: python tools/test_check_private_files.py"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_private_files import check  # noqa: E402

SAVE = 'BlackthornesBobDB = {\n\t["profileKeys"] = {\n\t},\n}\n'
TEXT = {
    "Core/Init.lua": "local _, ns = ...\nBlackthornesBobDB = BlackthornesBobDB or {}\n",
    "Data/Data_Cloth.lua": "local _, ns = ...\n",
    "Blackthornes_Bob.lua": SAVE,
    "Data/Copied.lua": SAVE,
    "tools/test_save.lua": SAVE,
}

checks = 0
failures = 0


def refused(path):
    found = check([path], lambda p: TEXT.get(p, ""))
    return bool(found)


def expect(label, got, want):
    global checks, failures
    checks += 1
    if got != want:
        failures += 1
        print(f"FAIL {label}: got {got}, want {want}")


for path in [
    "WTF/Account/NAME/SavedVariables/Blackthornes_Bob.lua",
    "SavedVariables/Blackthornes_Bob.lua",
    "wtf/Config.wtf",
    "keys.txt",
    "tools/keys.txt",
    ".env",
    ".env.local",
    "Core/Init.lua.bak",
    "Blackthornes_Bob.lua",
    "Data/Copied.lua",
]:
    expect(f"refuses {path}", refused(path), True)

for path in [
    "Core/Init.lua",
    "Data/Data_Cloth.lua",
    "tools/test_save.lua",
    ".env.example",
    "Blackthornes_Bob.toc",
    "README.md",
    "tools/check_private_files.py",
]:
    expect(f"allows {path}", refused(path), False)

print(f"  check_private_files: {checks} checks, {failures} failure(s)")
sys.exit(1 if failures else 0)
