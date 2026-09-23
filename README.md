# Blackthornes_Tradeskills

Tradeskill addon for WoW: Forever. It works out which crafts are worth making,
scans the auction house for the prices that answer depends on, and manages a
craft queue, a shopping list and a posting list around it.

Built without Ace3 or LibStub, because neither is known to work on Forever yet.
The small framework in `Core/` is written for this addon instead, so it does not
have to wait for anyone else to update theirs.

## Layout

| Folder | What is in it |
|---|---|
| `Core/` | Slash commands, settings, checking what the game supports, saving your data between sessions, and spacing out requests to the auction house |
| `Data/` | Everything read from the game: prices, auction scans, recipes, bags and bank, your own listings, vendor prices |
| `Logic/` | Craft cost, profit, the queue, starting crafts, posting, and export/import |
| `UI/` | Theme, reusable widgets, the main window, the auction house side panel, and the seven tabs |
| `Probe/` | `/bts probe`, which checks what the running game actually supports instead of guessing |

`Blackthornes_TS.toc` lists every Lua file in load order. A file that is not in
it does not load, and WoW says nothing about it.

## Development

Not shipped to the client: `tools/`, `docs/`, `deploy.ps1`. `deploy.ps1`
excludes them.

```powershell
.\deploy.ps1              # syntax check, lint, then mirror into Interface\AddOns
.\deploy.ps1 -SkipCheck   # skip the checks (not recommended)
```

```bash
python tools/syntaxcheck.py   # parse every Lua file with a real 5.1 parser
python tools/lintcalls.py     # find calls to methods, and constants, never defined
python tools/runtests.py      # run the pure-logic tests outside WoW
```

These checks matter because WoW quietly turns off an addon when one of its
files has a typo in it, and a call to a function that no longer exists only
fails when that line of code runs.

`tools/` requires `lupa` (`python -m pip install --user lupa`).

## A note on saved data

`Data/Snapshot.lua` ships empty and must stay that way in this repository.
`tools/restore.ps1` regenerates it from your own SavedVariables to carry a
database between sessions, and the result contains your characters, your prices
and your auctions. Git tracks the file, so `.gitignore` cannot protect it.

A pre-commit hook refuses any commit that would carry it. Git does not install
hooks when a repository is cloned, so run this once per clone:

```powershell
.\tools\install-hooks.ps1   # or: git config core.hooksPath .githooks
```

If the hook stops a commit, unstage the file with
`git restore --staged Data/Snapshot.lua`, or put the empty version back with
`git checkout -- Data/Snapshot.lua`. Neither touches the deployed copy in
`Interface\AddOns`, so the snapshot keeps working in game.

`.github/workflows/guard-saved-data.yml` runs the same check on GitHub, which
catches a snapshot pushed from a clone where the hook was never installed.

## API findings

`docs/FOREVER_API_FINDINGS.md` records what the game actually does, as found
with `/bts probe` rather than taken from documentation. Read it before changing
anything to do with the auction house or professions.
