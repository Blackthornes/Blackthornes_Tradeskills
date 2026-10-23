#!/bin/bash
# Gets a cloud session ready to run the repo's checks (tools/syntaxcheck.py,
# lintcalls.py, runtests.py and the tool tests). Only runs in the cloud;
# on a home PC it does nothing.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# lupa runs the Lua tests; numpy draws the arrow art. Both are free, from PyPI.
python3 -m pip install --quiet --disable-pip-version-check --root-user-action=ignore --break-system-packages lupa numpy
