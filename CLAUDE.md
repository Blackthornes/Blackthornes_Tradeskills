# Notes for Claude

Read this before working in this repo. It is one of five Blackthornes addons
(Farmer, Tradeskills, Equipment, Pets, Butler), each in its own repo. What one
needs to know about another lives in the repos, in this file and in theirs.
Keep them current: when a change here leans on something new in a sister, or a
standing rule from the owner applies to all of them, add it to each file.

Nothing private goes in this file (no local paths, emails or account names).
It never ships: `.pkgmeta` leaves it out of the zip and
`tools/check_package.py` refuses it.

## Long notes live in Docs/

CLAUDE.md is kept short on purpose (a 144 KB one ran every session out of room). Feature histories and full call details were moved word for word, nothing deleted: `Docs/claude-notes-sisters.md` (what Farmer, Equipment and Butler call here, and what Tradeskills calls there) and `Docs/claude-notes.md` (every other feature, plus the house kit, Discord, What's New, one window, minimap and similar shared notes). Grep a heading there, read about 150 lines at a time. Add new feature notes to those files, not here. Keep here only standing rules, the big files map and the short call lists below.

## Checking a change

Before every PR, follow `.claude/skills/verify/SKILL.md`: a bug fix starts
with a test that fails the way the game failed; act the steps out in the
fake game; run `python tools/check_house_rules.py` (player words and dark
glass, lines this change adds) and `python tools/checklist_for_change.py`
(the items in `Docs/change-checklist.md` this change touches). Every PR
body ends with `Checked:` and `Not checked:` lines. After three failed
rounds, stop and ask the owner. A miss a diff could have shown gets a
checklist item in the fix's PR. Details under "Checking a change" in
`Docs/claude-notes.md`.

## Calls between addons (keep stable; details in Docs/claude-notes-sisters.md)

All read only, inside a pcall, no TOC dependency unless noted. If one changes, change the other repo in the same breath.

- **Farmer reads here:** `_G.BlackthornesTS.Prices:GetValue(itemID)` (copper or nil), `Prices:WatchScans(fn)`, `CraftOrFarm:ForMaterial(itemID)`.
- **Tradeskills reads Farmer:** `_G.BlackthornesFarmer` `Goals:Find/Set/Remove(name[, amount])`, `GoalsUI:Show()`, `Pace:ForItem(item)`, `DisenchantFarm:Best/DroppedBy/Show`, `Looted:Has(item)`, `Stats:KillsAndLoot(7)`, `Butler:Advise(itemID)`, `Value:Contents(name)`.
- **Tradeskills reads Equipment:** `Compare:IsUpgrade(item)`, `Enchants:ForRecipe(recipeID)`, `Butler:Advise(link, bag, slot)`. Equipment calls back `Upgrades:RedrawSoon()`, `Queue:Ensure/EnsureBuy/ForUpgrade/ShowQueue`, `LearnNext:WhereFor/ShowTheWayFor`, and reads `Recipes:GetAccountWide(true)`, `GetShortCharacterName`, `Config:GetCharacterKey()`, `Prices:GetValue`, `RecipeBook:GetSkill`.
- **Tradeskills reads Pets and Butler:** `_G.BlackthornesPets.Butler:Advise(itemID)`, `_G.BlackthornesButler.Verdicts:Choice/InSet`, `Verdicts:Waiting(itemID, bag, slot)` and `Verdicts:SellAnyway/SoldAnyway` (the drawer's Butler Says Wait, through `SisterKeeps:ButlerWait/SellAnyway`), `Quests:Reason`.
- **Butler reads here (`_G.BlackthornesTS.Butler`):** `Advise(item)`, `SetBoughtToDisenchant`, `FillMail(name, items, money)`, `FromBank()`, `Jobs()`, `Craft(recipeID)`, `Profession(recipeID)`, `Mailbox(covered)`, `Holdings()` (with `mailSoonest`, `mailSoonCount`, `mailReturns`, `mailGone`, `mailCount` since 2026-11-09), `LearnCost()`, `VendorOffer()`, `BuyFromVendor()`, `VendorPrice(itemID)`, `SearchAuctions(items)`, `Lists()`, `NextSkillUp()`, `QueueSkillUp(id)`, `LevelUpMaterials()` (since 2026-11-17), `CraftFor(item, carried)` (with `others` since 2026-11-14), `QueueCraft(recipeID, crafts)`, `WishlistHere()` (since 2026-11-17); also `_G.BlackthornesTS.KeepHere:Count(itemID)` and `KeepHere.IsAll(count)`.
- **Public price API for other authors:** `_G.BlackthornesTS_API` (`version`, `GetPrice`, `GetPriceAge`); never rename or change.
- **Sharing:** `Core/Comm.lua` and `Core/Serialize.lua` are the same in Farmer (prefix `BTSshare` vs `BFRshare`); a fix belongs in both. The recipient name lists in `Logic/Contribute.lua` match Farmer's and Equipment's; change all three together.
- **Shared files** the same in all five Forever addons (a fix belongs in all): `UI/SharedWindow.lua`, `UI/SharedMinimap.lua`, `UI/WhatsNew.lua`, `UI/About.lua`, `UI/HouseKit.lua`, `UI/TooltipShift.lua`, `UI/FoldWindow.lua`, `UI/BlizzardLook.lua`, `UI/SharedChoices.lua` (Mute All Sounds lives there: every sound goes through `ns.PlaySound` or `ns.PlaySoundFile` in `Core/Init.lua`, a new one too; see "Mute All Sounds" in Docs/claude-notes.md), `Core/SisterNote.lua`, `Logic/Travel.lua`.
- **Shelves and dock places** (`UI/SharedWindow.lua` FILE_VERSION 17, with the round button (`foldedWindows`, never rename) and the swap gem; nothing places the one window while it is dragged): floating pieces with no saved spot start on `SharedWindow.ShelfPlace`, and the craft pane and mail list become the one window's Crafting and Mail tabs. See "Shelves, dock places and the All Addons page" in Docs/claude-notes.md.

## Standing rules (short form; full wording in Docs/claude-notes.md, "Standing rules in full")

Every rule below still holds in full. Before work that touches one, grep its
name under "Standing rules in full" in `Docs/claude-notes.md` and read it.
They are the same in every addon's notes; keep them the same.

- **One key per character.** A character is its GUID in saved data and in
  every call between addons, never a name. A GUID that can't be read means
  "not sure who's playing": write nothing, offer nothing for an alt. Old
  "Name-Realm" records stay readable and nothing is deleted
  (`formerCharacters`, `retiredInto`, never rename). Ask
  `Characters:Same`, `:IsPlaying` or `:Canonical`, never compare by hand,
  and every errand refuses the character playing. Tested in
  `tools/test_onecharacter.lua`.
- **Writing for players.** Every word a player reads is plain, warm and
  human, at a sixth grade level: short sentences, everyday words, what the
  player sees or does. No hype, no filler, no em-dashes, no questions to
  the reader. deDE changes with the English, in "du". `About.NOTE` is the
  owner's own wording.
- **Plain prose everywhere** (the owner, 2026-11-21): notes, commits, PRs
  and replies as well as player words. Say plainly what you mean, with no
  stock figures of speech. Use a short word where one will do. Cut every
  word you can, but keep the context the reader needs. Use the active
  voice. Use everyday words or the reader's own term, not foreign phrases,
  jargon or words made up during the work. Defaults, not hard limits.
  Check all prose against them before handing it over.
- **Every list is dark glass.** `glass` and `glassAlt` in turn with a 1 px
  `border` line (0.6) under each, `glassHover` and a gold edge under the
  mouse, `glassActive` and a bright gold left edge for the picked row.
  Never `row`/`rowAlt`. Gradients fade through `Theme.LightGradient` or
  hide, never SetAlpha alone.
- **No red gems on a rim's ends** (the owner, 2026-11-22): never put red
  circles on the left and right of a window, plaque or pop-up, in any
  addon. The red close gem (the X) and the corner gems stay.
- **Check that it's clear to post.** Nothing is published or uploaded
  without the owner's go-ahead. He tags releases himself.
- **Changelogs come from git history** (`git log vX.Y.Z..origin/main
  --merges`), never from asking the owner. Claude drafts the section in a PR.
- **A checkout shows the real version.** `ns.RELEASED_VERSION` in
  `Core/Init.lua` is the newest `## X.Y.Z` in CHANGELOG.md; the release PR
  changes both, and `tools/check_release.py` refuses a mismatch.
- **Every reply that ships code says the PR is ready and whether the game
  needs `/reload` or a full restart** (full restart when a file is added,
  removed or renamed, or the TOC changes). Merging, pulling and tagging go
  through the project's own steps, never by hand on github.com or in
  GitHub Desktop.
- **Grey items are priced at vendor only;** everything else is
  max(auction, vendor).
- **CurseForge descriptions are features only:** no privacy notes, no
  explaining public emotes or their switches.
- **Smooth play comes first, but never at the cost of looks.** Nothing on
  a timer or OnUpdate rebuilds a whole list when one thing moved; redo
  only what changed. Coalesce burst events (bag, loot, cast, skill,
  profession list), skip hidden windows, and spread work over hundreds of
  items across frames. Clicks and typing answer at once.
- **Never shorten a character's last name.** Show the whole name, made to
  fit by growing or wrapping (`Theme.SetRowName`, `FitText`).
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`),
  not 1.12. Read client values inside a pcall; instances hand out secret
  values that raise. See `docs/FOREVER_API_FINDINGS.md`.
- **Fold in fresh data at each release.** Its own step before every
  release, from the owner's live game folder, read only, committed as
  "Refresh shipped data", never announced, never the save or caches
  committed. If his PC can't be reached, ask once (Try again or Skip it).
  Tools: `tools/forever_vendor_spots.py <Blackthornes_TS.lua>`,
  `tools/forever_writ_customers.py --shared <Blackthornes_TS.lua>`,
  `tools/forever_trainer_recipes.py <Blackthornes_TS.lua>`, and
  `tools/make_forever_recipes.py` after a client-table re-pull.

## Running the checks (keep the output small)

A full test run used to print every passing check, about 590 KB, and that
alone ran sessions out of room (found 2026-11-16). `tools/runtests.py` is now
quiet: a passing suite prints nothing and a failing one prints its last 25
lines. Keep it that way, and never pipe a tool's whole output into a session.

- `python tools/runtests.py` runs everything and prints one line (`-q`, as
  the sister addons take it, is accepted and changes nothing).
- `python tools/runtests.py mail queue` runs only the suites with those
  words in their file name. Use this while fixing.
- `python tools/runtests.py -v uifit | tail -40` prints every check; always
  with a name and `tail`.
- `python tools/syntaxcheck.py` lists failures only (`-v` for every file).
- A new test may print each check as before; the runner holds the lines.
- `Data/ForeverVendorSpots.lua` has lines near 6000 characters: grep it with
  `-o` or `cut -c1-200`, never plain.

## Big files (read these in pieces)

Reading a huge file whole runs the session out of room. Sizes are
from 2026-11-03 and only grow. Find more with `find . -name '*.lua' | xargs wc -lc | sort -n`.

- Never read a file below whole. Use `grep -n` to find the spot, then read
  about 150 lines at a time (Read with `offset` and `limit`).
- Never read data tables or locale files whole. Grep them for one key.
- CLAUDE.md is big too. Grep it for a heading, then read that part only.
- Generated files (`Data/`) are written by their `tools/` script. Never edit
  them by hand, and never open them to see what they hold.

Data tables (generated, grep only): `Data/RecipeBook.lua` 2113 lines, 206 KB; `Data/ForeverRecipes.lua` 2029 lines, 184 KB; `Data/VendorSpots.lua` 77 KB; `Data/LearnSpots.lua` 69 KB.

Locale (grep one key, never read): `Locale/ruRU` 3348 lines, 321 KB; `frFR`, `esES`, `deDE`, `zhCN` are each about 3345 lines, 235 to 255 KB.

Code over 2000 lines:
- `Logic/Posting.lua` 3242 lines, 138 KB: listing and pricing posts.
- `UI/Widgets.lua` 2702 lines, 105 KB: shared widgets.
- `UI/Tab_Settings.lua` 2594 lines, 119 KB: Settings pages.
- `UI/Main.lua` 2588 lines, 100 KB: main window and tabs.
- `Data/Scanner.lua` 2479 lines, 104 KB: auction scans.
- `UI/CraftPanel.lua` 2344 lines, 97 KB: craft pane.
- `UI/Tab_Profit.lua` 2321 lines, 100 KB: Profit tab.
- `Logic/Queue.lua` 2103 lines, 85 KB: craft queue.
- `UI/PostPanel.lua` 2011 lines, 83 KB: auction house drawer.
- `Logic/Butler.lua` 1969 lines, 90 KB: what Butler asks here.

Over 1000 lines, same rule: `Data/Prices.lua`, `Data/Mail.lua`, `Core/Config.lua`, `Logic/Profit.lua`, `Logic/Disenchant.lua`, `Logic/QueueMail.lua`, `UI/Tab_LevelUp.lua`, `UI/Tab_Disenchanting.lua`, `UI/Tab_Sales.lua`, `UI/Tab_Stats.lua`, `UI/Tab_Prices.lua`, `UI/Tab_Queue.lua`, `UI/Tab_Deals.lua`, `UI/Tab_Characters.lua`, `UI/GoldGoal.lua`, `UI/ItemTooltip.lua`, `UI/WhatsNew.lua`, `UI/DealsFavor.lua`, `UI/MailReport.lua`, `UI/RecipeValue.lua`, `Data/Recipes.lua`, `Data/Auctions.lua`, `Logic/RecipeBook.lua`, `tools/test_uifit.lua`, `CHANGELOG.md` (1751 lines).
Over 800 lines: `UI/ShoppingListsView.lua`, `UI/SharedWindow.lua`, `UI/Theme.lua`, `UI/DealsWrits.lua`, `UI/RecipeBookView.lua`, `Logic/Travel.lua`, `Logic/MailHaul.lua`, `Logic/MerchantsFavor.lua`, `Logic/Writs.lua`, `Logic/GoldLog.lua`, `Core/Util.lua`, `tools/test_craftpane.lua`, `tools/test_mail.lua`.

The same file lives in several addons: `UI/SharedWindow.lua`, `UI/WhatsNew.lua`, `Logic/Travel.lua`, `UI/TooltipBlock.lua` (not Pets). A fix to one belongs in all.
