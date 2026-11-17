---
name: verify
description: Check a change to this addon before committing or opening a PR. Proves a bug with a failing test first, runs the touched tests, the house rules and the change checklist, and says in the PR how it was checked.
---

# Verify a change to Tradeskills

Run this before every commit you push for review, and always before a PR.
The game itself is on Trent's PC, so most changes can only be run in our
fake game here. The point is to prove what we can, and to say plainly what
only the real game can show.

Keep the output short: every command below prints only failures and a total.

## 1. A bug fix starts with a failing test

Before changing the code, write a test (or add to the suite nearest the
bug) that fails the way the game failed: the same steps, the same wrong
result. Run it and watch it fail:

    python tools/runtests.py -q <suite word>

Then fix the code and watch the same test pass. A test that never failed
has not shown it would catch the bug. If the bug cannot be shown in the
fake game (a drag, a real tooltip, timing in game), say so in the PR
under "Not checked".

When the fake game itself was wrong (it allowed a call Forever refuses, or
answered differently), fix the stubs in the suite you touched to match the game in the same PR, so
the same kind of miss cannot pass again.

## 2. Act it out in the fake game

Tradeskills suites load the modules they need with `loadfile("Core/....lua")("Blackthornes_TS", ns)` and stub the client around them (see `tools/test_onecharacter.lua` or `tools/test_workerstart.lua`). Load every module the player's steps pass through, not only the one you changed. Write the steps as a suite in `tools/test_<topic>.lua`.

Walk the player's steps, not only the function you changed: open the
window, click the button, fire the event twice in a row, log in with an
old save.

## 3. Run the quick checks

    python tools/runtests.py -q <words for the suites you touched>
    python tools/syntaxcheck.py -q
    python tools/check_house_rules.py
    python tools/checklist_for_change.py

`check_house_rules.py` looks only at lines this change adds. Fix what it
flags, or end the line with `-- house-ok` when it is on purpose.

`checklist_for_change.py` prints the items in Docs/change-checklist.md that
this change touches. Make sure of each one, or say in the PR why it does not
apply.

Then run the whole suite once (`python tools/runtests.py -q`) before the PR.

## 4. Three tries, then ask

If a check still fails after three rounds of fixes, stop. Tell Trent what
fails and what you tried, in plain words. Never skip, delete or loosen a
test, add a wait, or rerun until it passes to get green. A flaky test gets
its cause found; if it cannot be, take it out and write down why in the PR.

## 5. Say how it was checked

Every PR body ends with these lines:

    Checked: tests | fake game | in game | none yet
    Not checked: <what only the real game can show, or "nothing">

Pick every word that is true on the Checked line. "in game" only when Trent
(or a screenshot from his PC) showed it working. Notes in
Docs/claude-notes.md keep saying "Not yet seen in game" until he has.

## 6. When something slips through

A miss the tests did not catch, that could be spotted from a diff, gets an
item in Docs/change-checklist.md in the same PR as its fix.
