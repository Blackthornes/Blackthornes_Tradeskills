# Blackthornes_Tradeskills

Tradeskill addon for WoW: Forever. It works out which crafts are worth making,
scans the auction house for the prices that answer depends on, and manages a
craft queue, a shopping list and a posting list around it.

Built without Ace3 or LibStub, which are not known to be ported to Forever. The
framework in `Core/` is about 200 lines and is ours, which is a better trade
than a hard dependency on somebody else's port schedule.

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
machine. The one file that can carry saved data, `Data/Snapshot.lua`, ships
empty and a check on every release refuses to publish it otherwise.

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

`docs/FOREVER_API_FINDINGS.md` records what the client actually does, captured
with `/bts probe` rather than taken from documentation. Worth reading before
changing anything that touches the auction house or profession APIs.

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
