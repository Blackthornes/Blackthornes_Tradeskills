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

## Long notes live in Docs/

CLAUDE.md is kept short on purpose (a 144 KB one ran every session out of room). Feature histories and full call details were moved word for word, nothing deleted: `Docs/claude-notes-sisters.md` (what Farmer, Equipment and Butler call here, and what Tradeskills calls there) and `Docs/claude-notes.md` (every other feature, plus the house kit, Discord, What's New, one window, minimap and similar shared notes). Grep a heading there, read about 150 lines at a time. Add new feature notes to those files, not here. Keep here only standing rules, the big files map and the short call lists below.

## Calls between addons (keep stable; details in Docs/claude-notes-sisters.md)

All read only, inside a pcall, no TOC dependency unless noted. If one changes, change the other repo in the same breath.

- **Farmer reads here:** `_G.BlackthornesTS.Prices:GetValue(itemID)` (copper or nil), `Prices:WatchScans(fn)`, `CraftOrFarm:ForMaterial(itemID)`.
- **Tradeskills reads Farmer:** `_G.BlackthornesFarmer` `Goals:Find/Set/Remove(name[, amount])`, `GoalsUI:Show()`, `Pace:ForItem(item)`, `DisenchantFarm:Best/DroppedBy/Show`, `Looted:Has(item)`, `Stats:KillsAndLoot(7)`, `Butler:Advise(itemID)`, `Value:Contents(name)`.
- **Tradeskills reads Equipment:** `Compare:IsUpgrade(item)`, `Enchants:ForRecipe(recipeID)`, `Butler:Advise(link, bag, slot)`. Equipment calls back `Upgrades:RedrawSoon()`, `Queue:Ensure/EnsureBuy/ForUpgrade/ShowQueue`, `LearnNext:WhereFor/ShowTheWayFor`, and reads `Recipes:GetAccountWide(true)`, `GetShortCharacterName`, `Config:GetCharacterKey()`, `Prices:GetValue`, `RecipeBook:GetSkill`.
- **Tradeskills reads Pets and Butler:** `_G.BlackthornesPets.Butler:Advise(itemID)`, `_G.BlackthornesButler.Verdicts:Choice/InSet`, `Quests:Reason`.
- **Butler reads here (`_G.BlackthornesTS.Butler`):** `Advise(item)`, `SetBoughtToDisenchant`, `FillMail(name, items, money)`, `FromBank()`, `Jobs()`, `Craft(recipeID)`, `Profession(recipeID)`, `Mailbox(covered)`, `Holdings()` (with `mailSoonest`, `mailSoonCount`, `mailReturns`, `mailGone`, `mailCount` since 2026-11-09), `LearnCost()`, `VendorOffer()`, `BuyFromVendor()`, `VendorPrice(itemID)`, `SearchAuctions(items)`, `Lists()`, `NextSkillUp()`, `QueueSkillUp(id)`, `CraftFor(item, carried)`, `QueueCraft(recipeID, crafts)`; also `_G.BlackthornesTS.KeepHere:Count(itemID)` and `KeepHere.IsAll(count)`.
- **Public price API for other authors:** `_G.BlackthornesTS_API` (`version`, `GetPrice`, `GetPriceAge`); never rename or change.
- **Sharing:** `Core/Comm.lua` and `Core/Serialize.lua` are the same in Farmer (prefix `BTSshare` vs `BFRshare`); a fix belongs in both. The recipient name lists in `Logic/Contribute.lua` match Farmer's and Equipment's; change all three together.
- **Shared files** the same in all five Forever addons (a fix belongs in all): `UI/SharedWindow.lua`, `UI/SharedMinimap.lua`, `UI/WhatsNew.lua`, `UI/About.lua`, `UI/HouseKit.lua`, `UI/TooltipShift.lua`, `UI/FoldWindow.lua`, `UI/BlizzardLook.lua`, `UI/SharedChoices.lua` (Mute All Sounds lives there: every sound goes through `ns.PlaySound` or `ns.PlaySoundFile` in `Core/Init.lua`, a new one too; see "Mute All Sounds" in Docs/claude-notes.md), `Core/SisterNote.lua`, `Logic/Travel.lua`.

## One key per character

The owner asked (2026-10-11) that a character can never be mistaken for
another again. Old records had sent errands to the character playing:
Butler filled a mail to itself and told a player to mail Medium Leather to,
and log out for, the character they were on (an old "Name-Realm" record of
Tradeskills' beside the GUID one), and a reload wiped alts' saved gear in
Equipment. The rule, in every addon:

- **A character is its GUID** (`UnitGUID("player")`) in saved data and in
  every call between the addons. Never a first name, "Name-Realm" or a
  short name: Forever lets characters share a first name. Names are for
  showing and for a mail's To line only, always first and last.
- **A GUID the client won't read (a dungeon) means "not sure who's
  playing":** write nothing under another key, and offer nothing for an
  alt. Tradeskills remembers each character's GUID in its own file
  (`BlackthornesTSCharDB.guid`) for that case.
- **Old records stay readable and count as the same character; nothing is
  deleted.** Tradeskills folds an old "Name-Realm" record into the GUID one
  at login, once (`Config:AdoptLegacyCharacter`): it is kept whole in
  `formerCharacters[old key]` with `retiredInto` (never rename either), what
  the GUID record lacks is filled from it when it carries that GUID, and
  the queue's references to the old key follow. Farmer reads a goal tagged
  "Name-Realm" as the character's and tags it with the GUID once the
  character gathers toward it or changes it.
- **One test per addon answers "the same character?" and "the one
  playing?"; never compare keys or names by hand.** Tradeskills:
  `Characters:Same`, `:IsPlaying` and `:Canonical` (`Core/Characters.lua`),
  and `playing` on each `Butler:Holdings()` entry. Butler:
  `Errands:IsMe(name)` (full name, first name alone, any old record's name,
  any case, with or without a realm). Farmer: `Goals:IsOwner`. Equipment:
  `Alts.PlayerGUID()`.
- **Every errand that targets a character asks that test right before it
  acts and refuses the character playing:** a mail, a gold top-up, a Log
  out, an alt's upgrade, a learned habit, the disenchanter.
- Tested in Tradeskills' `tools/test_onecharacter.lua`, Butler's
  `tools/test_notme.lua`, Farmer's `tools/test_goals.lua` and Equipment's
  `tools/test_alts.lua`. This rule is in every addon's notes; keep them the
  same.

## Writing for players

Every word a player reads (labels, buttons, tooltips, Settings rows and
their descriptions, empty lists, chat lines, slash command help) reads the
way a friend who plays would say it: plain, warm and human. Write it at a sixth grade reading level. Short
sentences in everyday words, contractions welcome. Say what the player
sees or does, not how the addon works inside. No hype or sales words
("seamlessly", "effortlessly", "now you can", "powerful"), no filler, no
em-dashes, and no questions to the reader. The German in
`Locale/deDE.lua` changes with the English, in the same informal "du"
voice. Farmer's play cheers keep their "!" (drop-quality cheers, goal
marks, streaks, "Up to #N!", "Goal done: X!"), and `About.NOTE` is the
owner's own wording. This rule is in every addon's notes; keep them the
same.

## The owner's standing rules (both addons)

- **Every list is dark glass** (the owner, 2026-10-12: "keep this as the
  standard across all Blackthornes addons", after Farmer's Kills & Loot
  panel was given the look of Tradeskills' queue). Rows or lines take
  `glass` and `glassAlt` in turn, by place, with a 1 px `border` line
  (alpha 0.6) under each; under the mouse `glassHover` and a gold edge,
  only on that row; the row picked or open is `glassActive` with a bright
  gold edge down its left. Never the older `row`/`rowAlt` bands for a
  list, a panel's lines or cards. A gradient fades through
  `Theme.LightGradient` or is hidden, never with SetAlpha alone (it stayed
  lit on Forever). This rule is in every addon's notes; keep them the same.
- **"Always check that it's clear to post."** Anything that goes public (a
  release, a CurseForge page, a post) is checked for private or unexpected
  content first, and nothing is published or uploaded without the owner's
  go-ahead. He tags releases himself.
- **Changelogs come from git history.** Work out what changed since the last
  tag from the merged PRs and commits (`git log vX.Y.Z..origin/main --merges`);
  never ask the owner what went in. Claude drafts the CHANGELOG section in a PR;
  The owner merges, pulls `main`, tags and pushes.
- **A checkout shows the real version number** (the owner,
  2026-10-12). `ns.RELEASED_VERSION` in `Core/Init.lua` is the newest
  `## X.Y.Z` in CHANGELOG.md, shown when the packager has not filled in the
  TOC's `@project-version@` (he plays from a clone). The release PR that
  writes the CHANGELOG section changes it too; `tools/check_release.py`
  refuses a tag it does not match, and `tools/test_check_release.py` fails
  while the two disagree. This rule is in every addon's notes.
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
- **Smooth play comes first, but never at the cost of looks** (the owner,
  2026-10-09, after a hitch while crafting). Nothing on a timer or
  OnUpdate rebuilds or re-places a whole list, map or set of markers when
  only one thing moved: keep what is drawn, and redo only rows or pins
  whose inputs changed (a per-row key, a version number). Bag, loot,
  cast, skill and profession-list events arrive in bursts, several per
  craft or loot: coalesce them, read only what they changed, and skip
  work for windows that are hidden. Work over hundreds of items (recipes,
  sources, saved spots) is spread over frames (a worker with a small
  per-frame budget) rather than done in one frame, and shown when done.
  Clicks and typing still answer at once. The two causes found: Farmer's
  minimap markers gathered, sorted and re-placed every saved spot once a
  second because the clock second was in their redraw key (now only the
  fade moves, `MapMarkers:FadeMinimap`); and on every craft Tradeskills
  re-read every recipe in the profession window and repriced the whole
  craft pane in one frame (now `Recipes:NothingNewMidCraft` skips the
  re-read mid-run and `CraftPanel:RefreshInSlices` spreads the pane over
  frames). Visuals and usability are never traded away for speed. This
  rule is in all four addons' notes; keep them the same.
- **Never shorten a character's last name** (the owner, 2026-10-11:
  "they must be included in WoW Forever"). Forever names are first and
  last together, so every place a character is named shows the whole name,
  made to fit by growing or wrapping (`Theme.SetRowName`, `FitText` with a
  wording that drops words, never the surname), never "Bob B." or the
  first name alone. `Recipes:GetShortCharacterName` keeps its name for
  Equipment and Butler but returns the full name.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Instances hand addons secret values that raise when
  compared, concatenated or formatted, so read client values inside a pcall.
  `docs/FOREVER_API_FINDINGS.md` has what the client actually does.

## Fold in fresh data at each release

Every release of this addon starts with a fold-in of fresh data from the
live game (the owner, 2026-11-07), even when nothing else about the data
changed: the release thread stages the owner's account save and the game's
English caches, read only, from his live Forever folder (the path is in the
project's release steps), runs the tools below, runs the tests and commits
the data in the release PR as "Refresh shipped data". Never announced (no
CHANGELOG, NEWS, What's New or post), never the save or caches committed,
nothing else copied out of them. A release whose only change is new data
does not ship on its own. If his PC can't be reached, the thread asks him
once (Try again or Skip it); it never skips without saying. If the game
patched since the client tables were last pulled, those are refreshed
first.

- `tools/forever_vendor_spots.py <Blackthornes_TS.lua>`
  (`Data/ForeverVendorSpots.lua`, vendor and trainer spots seen in game).
- After a client-table re-pull, `tools/make_forever_recipes.py` as the
  tables routine does.

## Big files (read these in pieces)

Reading a huge file whole fills the context and the thread dies. Sizes are
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

The same file lives in several addons: `UI/SharedWindow.lua`, `UI/WhatsNew.lua`, `Logic/Travel.lua`. A fix to one belongs in all.
