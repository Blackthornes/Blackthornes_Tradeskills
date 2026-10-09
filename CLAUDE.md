# Notes for Claude

Read this before working in this repo. The owner also runs a separate Claude
project for his other addon, **Blackthornes_Farmer**
(`Blackthornes/Blackthornes_Farmer`), and that project has made changes here.
The two projects cannot read each other's memory, so what one of them needs to
know about the other lives in the repos, in this file and in Farmer's
`CLAUDE.md`. Keep it current: when work here changes something Farmer depends
on, or a new standing rule from the owner applies to both addons, add it to both
files.

Nothing private goes in this file (no local paths, emails or account names).
It never ships: `.pkgmeta` leaves it out of the zip and
`tools/check_package.py` refuses it.

## What the Farmer project did here

- **Release setup (PR #77, merged 2026-09-25).** Pushing a `vX.Y.Z` tag on
  `main` runs `.github/workflows/release.yml`: `tools/check_release.py`
  (CHANGELOG.md must open with `## X.Y.Z`), the tests, a packager build with
  nothing uploaded, `tools/check_package.py` (the clear-to-post scan), then the
  upload of that same checked folder. The TOC version is `@project-version@`
  and is never typed by hand. Details are in the README under Releasing.
- **CurseForge.** Project IDs: Tradeskills **1710638**, Farmer **1710618**.
  The upload uses the `CF_API_KEY` repository secret, which the owner set himself;
  never ask him to paste a token anywhere. The hand-uploaded original counts
  as 0.1.0.
- **v0.2.0 was tagged and uploaded to CurseForge on 2026-09-25.** Nothing has
  changed here since, so there is no newer release yet.
- **The CurseForge page.** The Farmer project wrote the Tradeskills
  description and its animated GIF and screenshots. They are not in this repo;
  The owner pasted and uploaded them on CurseForge himself. Description rules
  below.

## How Farmer uses Tradeskills

Farmer prices mob drops (worth per kill, rankings, fishing and gathering
value) from Tradeskills' auction data when both addons are loaded. It reads,
at runtime, inside a pcall and read only:

```lua
_G.BlackthornesTS.Prices:GetValue(itemID)   -- no second argument: "market"
```

It expects a copper number, or nil when there is no price. Since
2026-10-06 `GetValue` also follows a price the player set on the Prices tab
(`Prices:GetMine`, saved in `myPrices`): "use" replaces the scanned price,
"floor" lifts it, and "rival" stays the auction house's. `GetScanValue` is
the scans alone. It copies no data,
writes nothing, and has no TOC dependency; without Tradeskills it falls back to
vendor prices. So keep all three stable: the `_G.BlackthornesTS` global
(`Core/Init.lua`), `ns.Prices` on it, and `Prices:GetValue(itemID)` defaulting
to the smoothed market value (`Data/Prices.lua`). If one has to change, change
Farmer's `Logic/Value.lua` in the same breath and tell the owner both need
updating.

## How Tradeskills uses Farmer

The Gather tab's **Set goal** button (`Logic/FarmerGoals.lua`) turns a
material the queue still needs into a Farmer gathering goal. It shows only
when Farmer is loaded (`## OptionalDeps: Blackthornes_Farmer` in the TOC) and
calls, inside a pcall:

```lua
_G.BlackthornesFarmer.Goals:Find(name)            -- optional, to say "updated"
_G.BlackthornesFarmer.Goals:Set(name, amount)     -- goal table, or nil and why
_G.BlackthornesFarmer.GoalsUI:Show()              -- opens Farmer's Goals panel
```

`name` is the item's plain name and `amount` the row's NEED. Farmer's goals
belong to the character that set them, so `Find` and `Set` act on the
character playing. Farmer's `CLAUDE.md` asks its side to keep these stable;
if one changes, change `Logic/FarmerGoals.lua` in the same breath.

## How Tradeskills uses Equipment

Gear that **Blackthornes_Equipment** (`Blackthornes/Blackthornes_Equipment`)
calls an upgrade for the character playing gets the green arrow on its icon,
everywhere Tradeskills draws item icons (`Theme.SetItemIcon` asks
`Logic/Upgrades.lua`). Equipment is optional (`## OptionalDeps` in the TOC);
without it nothing is drawn. It calls, inside a pcall and read only:

```lua
_G.BlackthornesEquipment.Compare:IsUpgrade(item)   -- item ID or link; true or false
```

Most windows ask by item ID. Bag rows on the Disenchanting tab pass the carried copy's link (`Theme.SetItemIcon(icon, itemID, link)`),
so random-suffix gear ("of the Monkey") is judged as that copy; Equipment's
`CLAUDE.md` already promises links. Answers are kept per item ID, or per
item string for a link, and forgotten on gear, level, talent and
item-info events. Setting: `showUpgradeArrows`. Equipment's `CLAUDE.md` asks
its side to keep the call stable; if it changes, change `Logic/Upgrades.lua`
in the same breath.

Equipment calls back one way: when a player changes their own stat weights
in Equipment's weights window, or picks a spec there, it calls, inside a
pcall:

```lua
_G.BlackthornesTS.Upgrades:RedrawSoon()   -- forget kept answers, redraw what shows arrows
```

So keep `ns.Upgrades` on the global and `Upgrades:RedrawSoon()` stable too;
if it changes, change Equipment's `Weights:Changed` (`Logic/Weights.lua`).

Equipment's upgrade finder also lists crafted gear (who can make it, what
the materials cost). Its `Logic/Crafting.lua` reads, inside a pcall and read
only:

```lua
ns.Recipes:GetAccountWide(true)        -- recipes by ID (= spell ID), each with knownBy
ns.Recipes:GetShortCharacterName(key)  -- an alt's short name
ns.Config:GetCharacterKey()            -- the character playing
ns.db.characters[key].faction          -- to leave out the other faction's alts
ns.Prices:GetValue(itemID)             -- material and auction prices
```

Keep these stable as well; if one changes, change Equipment's
`Logic/Crafting.lua` in the same breath.

## Sharing between accounts and with a guild

Asked 2026-10-07 (Ezmode on Discord, the owner agreeing). Over addon
messages (`Core/Comm.lua`, prefix `BTSshare`):

- `Logic/AccountLink.lua`: the player names characters on another account
  of theirs (`linkNames`); both sides must name each other. Their
  characters arrive as ordinary `characters[guid]` records marked
  `linkedFrom` (never rename it), so everything that reads alts (Farmer
  aside, Equipment's crafting included) sees them. A copy never replaces
  one of the account's own characters and is never sent on.
- `Logic/GuildPrices.lua`: on by default since 2026-10-07 (`guildPrices`). Guildmates'
  prices are kept apart in `guildPrices[realm][itemID]` and only fill gaps
  in `Prices:GetValue`: an item never scanned, or one gone stale while
  theirs is newer. So Farmer's `GetValue` can now answer from a guild
  price unless the player turned it off; still copper or nil.

## The house frame (Titanforged)

The owner picked this look for all four addons on 2026-10-04 from two mockups
(the other was "Arcane Glass"). It's the game's own window shape with the
light turned up: a gold metal rim with corner gems, a round portrait with
the addon's emblem, the name on a plate across the top edge, a red close
gem, and tabs hanging below the window. Buttons are raised metal with gold
labels, and the main action is solid gold with dark lettering.

It lives in `UI/Titanforged.lua` (`Titanforged:Dress(frame, opts)`,
`:Opened(frame)`), with the art in `Media/Frame/*.tga`, drawn by
`tools/make_frame_art.py`. Hanging tabs are `CreateTabStrip(..., { hanging =
true })`. Tradeskills got it first. Farmer, Equipment and Pets copy the file,
the art and the tool, changing only `EMBLEM` in the tool (pick, shield,
paw). Glows and glints follow the Window effects setting.

## Discord

The addons share a Discord server, Blackthornes AddOns (public invite
https://discord.gg/f2geDecrw2, set up 2026-10-05). After a release uploads,
`release.yml` runs `tools/announce_discord.py`, which posts the version's
CHANGELOG section to the server's #announcements through a channel webhook
kept in the `DISCORD_WEBHOOK_URL` repository secret. The owner sets that secret
himself; never ask him to paste the webhook address anywhere. Without it the
step does nothing, and a failed post never undoes the upload. The tool is the
same in all four repos; a fix to it belongs in all four.

The owner asked (2026-10-09) for one friendly post in #general per release
too: plain words, a sixth-grade reading level, warm, in his voice (short,
contractions, no jargon, no file or setting names, never his name), saying
what players will notice. Each release PR writes the new version's section
in `NEWS.md` (`## X.Y.Z`, like CHANGELOG.md; it never ships) next to the
CHANGELOG section. After the upload `tools/post_general.py` scans it with
`check_package.py`'s PRIVATE list and posts it through the
`DISCORD_GENERAL_WEBHOOK_URL` secret, which the owner sets himself, with the
CurseForge link added. No section or no secret means no post.
A player's name never goes in a report (the owner, 2026-10-09): no
CHANGELOG, #announcements post, commit or PR text names a player, and
`check_release.py` refuses a CHANGELOG section that credits one
(`names_a_player` in `post_general.py`). The #general post is the one
exception: it thanks, by their Discord name, whoever asked for or reported
each change, next to that change ("thanks Ana for spotting this"). Find who
asked from the project's threads. This tool is
also the same in all four repos.

## The owner's standing rules (both addons)

- **"Always check that it's clear to post."** Anything that goes public (a
  release, a CurseForge page, a post) is checked for private or unexpected
  content first, and nothing is published or uploaded without the owner's
  go-ahead. He tags releases himself.
- **Changelogs come from git history.** Work out what changed since the last
  tag from the merged PRs and commits (`git log vX.Y.Z..origin/main --merges`);
  never ask the owner what went in. Claude drafts the CHANGELOG section in a PR;
  The owner merges, pulls `main`, tags and pushes.
- **Every reply that ships code ends with the GitHub Desktop steps,** naming
  the branch: merge the PR on github.com (Ready for review, then Merge pull
  request); in GitHub Desktop switch **Current branch** to **main** and click
  **Pull origin**; then say whether the game needs `/reload` or a full restart
  (a full restart when a file is added, removed or renamed, or the TOC
  changes). For a release, add: History, right-click the newest commit,
  Create Tag, `vX.Y.Z`, Push origin. Remind him to pull `main` first, or the
  tag lands on an old commit and nothing runs.
- **Grey (poor quality) items are priced at vendor only,** never from the
  auction house. Everything else is worth max(auction, vendor). Farmer applies
  this to every value it shows; follow it here if Tradeskills ever values grey
  items.
- **CurseForge descriptions are features only.** Leave out privacy or
  "your data stays yours" notes and any explanation of public emotes or their
  switches: "they don't care to know this." Those belong in the README and
  CHANGELOG.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Instances hand addons secret values that raise when
  compared, concatenated or formatted, so read client values inside a pcall.
  `docs/FOREVER_API_FINDINGS.md` has what the client actually does.
