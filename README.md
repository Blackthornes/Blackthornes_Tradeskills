# Blackthornes_Tradeskills

Tradeskill addon for WoW: Forever. It works out which crafts are worth making,
scans the auction house for the prices that answer depends on, and manages a
craft queue, a shopping list and a posting list around it.

Built without Ace3 or LibStub, because neither is known to work on Forever yet.
The small framework in `Core/` is written for this addon instead, so it does not
have to wait for anyone else to update theirs.

## What it does

- Works out which of your recipes are worth crafting, from live auction prices
  and what your materials actually cost you.
- Scans the auction house and keeps a price history per realm and faction.
- Keeps a craft queue and a shopping list of the reagents it still needs.
- Posts your crafts, priced against the cheapest rival, with a floor so nothing
  is listed below vendor value.
- Tracks stock across your characters, their bags, their bank and the reagent
  bag.

## Install

**With an addon manager.** Search for *Blackthornes Tradeskills* and install
it. The manager puts it in the right folder and keeps it updated.

**By hand.** Download the zip from the
[releases page](https://github.com/Blackthornes/Blackthornes_Tradeskills/releases),
and unzip it into

```
World of Warcraft\_classic_beta_\Interface\AddOns
```

so that the folder `Blackthornes_TS` sits directly inside `AddOns` with
`Blackthornes_TS.toc` inside it. Restart the client, or type `/reload`.

Then type `/bts` in game.

Built for the WoW: Forever beta, interface 16001. It is not tested on retail or
on any Classic client.

## Your data stays yours

The addon stores its database in your own SavedVariables and sends nothing
anywhere. Nothing is uploaded, and no prices or character data leave your
machine. There is no telemetry, no account, and nothing to opt out of.

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
so nothing else is needed. The old workarounds -- a generated data addon and
storage in macros -- were removed; `Core/OldMacros.lua` deletes the leftover
`BTSd` macros on a login where the saved data loaded. The CVar store in
`Core/Persist.lua` stays as a fallback and stands down whenever the saved data
loads. `/bts db` and `/bts persist` show what loaded.

## API findings

`docs/FOREVER_API_FINDINGS.md` records what the game actually does, as found
with `/bts probe` rather than taken from documentation. Read it before changing
anything to do with the auction house or professions.

## Releasing

Releases are cut by pushing a tag. `.github/workflows/release.yml` builds the
player-facing zip with the
[BigWigs packager](https://github.com/BigWigsMods/packager) and uploads it
wherever a token is configured.

```bash
git tag v0.2.0
git push origin v0.2.0
```

The packager rewrites `## Version: @project-version@` in the TOC to the tag, so
the version is never edited by hand. Running straight from a clone there is no
packager, and the addon reports its version as `dev`.

`.pkgmeta` decides what reaches a player: `tools/`, `docs/`, `deploy.ps1` and
the git plumbing are excluded, which is the same set `deploy.ps1` excludes.

Uploads are opt-in per site. The workflow reads these repository secrets, and
skips any site whose secret is missing:

| Secret | Site |
|---|---|
| `CF_API_KEY` | CurseForge |
| `WAGO_API_TOKEN` | Wago Addons |
| `WOWI_API_TOKEN` | WoWInterface |

Each site also needs its project ID in the TOC — `X-Curse-Project-ID`,
`X-Wago-ID`, `X-WoWI-ID` — which exist only once the project has been created
there. They are present but commented out until then.
