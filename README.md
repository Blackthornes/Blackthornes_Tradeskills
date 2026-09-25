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

Since WoW: Forever build 1.60.1.70009 (2026-09-24) the game keeps the addon's
saved data (`BlackthornesTSDB` and `BlackthornesTSCharDB`) across a restart,
so nothing else is needed. The old workarounds, a generated data addon and
storage in macros, were removed; `Core/OldMacros.lua` deletes the leftover
`BTSd` macros on a login where the saved data loaded. The CVar store in
`Core/Persist.lua` stays as a fallback and stands down whenever the saved data
loads. `/bts db` and `/bts persist` show what loaded.

## API findings

`docs/FOREVER_API_FINDINGS.md` records what the game actually does, as found
with `/bts probe` rather than taken from documentation. Read it before changing
anything to do with the auction house or professions.
