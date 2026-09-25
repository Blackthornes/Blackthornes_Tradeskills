"""Tests for tools/check_release.py. Run: python tools/test_check_release.py"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_release import check  # noqa: E402

TOC = "## Interface: 16001\n## Version: @project-version@\n"
LOG = "# Changelog\n\n## 0.2.0 - 2026-09-30\n\n- New.\n\n## 0.1.0\n\n- First.\n"

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


expect("the newest version releases", check("v0.2.0", LOG, TOC) == [])
expect("a beta of it too", check("v0.2.0-beta1", LOG.replace("0.2.0 -", "0.2.0-beta1 -"), TOC) == [])
expect("an older version is refused", check("v0.1.0", LOG, TOC) != [])
expect("an unwritten version is refused", check("v0.3.0", LOG, TOC) != [])
expect("a tag without the v is refused", check("0.2.0", LOG, TOC) != [])
expect("a tag that is not a version is refused", check("vnext", LOG, TOC) != [])
expect("a changelog with no sections is refused", check("v0.2.0", "# Changelog\n", TOC) != [])
expect("a hand-typed TOC version is refused",
       check("v0.2.0", LOG, TOC.replace("@project-version@", "0.2.0")) != [])

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(os.path.join(root, "Blackthornes_TS.toc"), encoding="utf-8") as f:
    expect("the real TOC is set up for tags", "@project-version@" in f.read())

print("  check_release: %d checks, %d failure(s)" % (checks, failures))
sys.exit(1 if failures else 0)
