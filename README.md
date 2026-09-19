# Blackthornes_Tradeskills

Tradeskill addon for WoW: Forever. It works out which crafts are worth making,
scans the auction house for the prices that answer depends on, and manages a
craft queue, a shopping list and a posting list around it.

Built without Ace3 or LibStub, which are not known to be ported to Forever. The
framework in `Core/` is about 200 lines and is ours, which is a better trade
than a hard dependency on somebody else's port schedule.

## Layout

| Folder | What is in it |
|---|---|
| `Core/` | Module registry, slash commands, settings, client capability detection, serialization, CVar persistence, and the auction house request queue |
| `Data/` | Everything read from the game: prices, auction scans, recipes, bags and bank, your own listings, vendor prices |
| `Logic/` | Craft cost, profit, the queue, starting crafts, posting, and export/import |
| `UI/` | Theme, reusable widgets, the main window, the auction house side panel, and the seven tabs |
| `Probe/` | `/bts probe` diagnostics, which interrogate the live client instead of assuming what the API looks like |

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

The checks exist because WoW silently disables an addon whose first TOC file
fails to compile, and because a call to a method that no longer exists is valid
Lua that fails only when that line runs.

`tools/` requires `lupa` (`python -m pip install --user lupa`).

## A note on saved data

`Data/Snapshot.lua` ships empty and must stay that way in this repository.
`tools/restore.ps1` regenerates it from your own SavedVariables to carry a
database between sessions, and the result contains your characters, your prices
and your auctions. Check `git diff Data/Snapshot.lua` before committing after
running it.

## API findings

`docs/FOREVER_API_FINDINGS.md` records what the client actually does, captured
with `/bts probe` rather than taken from documentation. Worth reading before
changing anything that touches the auction house or profession APIs.
