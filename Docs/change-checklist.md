# Change checklist

Things we got wrong before, each with what sets it off. Before a PR, run
`python tools/checklist_for_change.py` and it prints only the items this
change touches (usually a handful). Make sure of each one, or say in the PR
why it does not apply.

When something slips through anyway (a fix that passed the tests but not the
game, a reviewer's catch), add an item here in the same PR as the fix, if the
miss can be spotted from a diff. Take an item out when the code it guards is
gone. Keep each item short: the full story lives in Docs/claude-notes.md.

Fields: `Files` is matched against each changed path, `Lines` against each
added or removed line (both are regular expressions; either one matching is
enough). `Check` is what to make sure of. `Why` is the miss behind it.

## A file shared by all five addons
Files: ^(UI/(SharedWindow|WhatsNew|SettingsPages|SharedMinimap|About|HouseKit|TooltipShift|FoldWindow|BlizzardLook|SharedChoices|TravelMap)|Logic/(Travel|ClassTraining)|Core/SisterNote)\.lua$
Check: Make the same change in each sister addon that has this file, and bump
  FILE_VERSION when the file has one (then update the FILE_VERSION line in
  every addon's CLAUDE.md).
Why: Fixes landed in one addon only, and the newest copy loaded first won.

## Dragging or placing a window
Lines: StartMoving|StopMovingOrSizing|ClearAllPoints|KeepSpot|SetUserPlaced|OnDragStart|OnDragStop
Check: Nothing places the window while it is dragged, a spot is saved only
  on the drop, and it stays on screen. The fake game cannot show a drag, so
  the PR says "Not checked: dragging in game".
Why: The one window snapped back under the cursor mid-drag (2026-11-16),
  with every test green.

## A saved key
Lines: muteSounds|muteSoundsAt|windowSpots|oneWindowDockSpots|formerCharacters|retiredInto|SavedVariables
Check: Never rename or drop a saved key. Old saves must still load: read the
  old shape, write the new one, delete nothing.
Why: Renamed keys lost players' data; old records are kept on purpose.

## Who is playing
Lines: UnitName\(\s*"player"|GetUnitName|GetRealmName|UnitGUID
Check: A character is its GUID, never a name. A GUID that will not read
  means write nothing and offer nothing for an alt. Use the one test for
  "same character" in this addon, and refuse an errand aimed at the one
  playing.
Why: Errands were sent to the character playing, and a reload wiped alts'
  saved gear (2026-10-11).

## A sound
Lines: PlaySound
Check: Every PlaySound and PlaySoundFile asks ns.Muted() first, fallbacks too.
Why: Mute All Sounds must quiet every sound in all five addons.

## Reading the client
Lines: \bC_[A-Za-z]+\.[A-Za-z]+\(|\bGet[A-Z][A-Za-z]+Info\(
Check: Client values are read inside a pcall. Inside an instance some come
  back as secret values that raise when touched. Never assume an API exists
  on Forever: note what the probe shows in docs/FOREVER_API_FINDINGS.md.
Why: Forever is a retail engine with classic rules; several calls are
  missing or locked in dungeons.

## Events, timers and redraws
Lines: RegisterEvent|OnUpdate|C_Timer\.(After|NewTicker|NewTimer)
Check: Register through ns.RegisterEvent. Coalesce bag, loot, cast and skill
  bursts. Nothing on a timer rebuilds a whole list when one thing moved, and
  hidden windows skip the work.
Why: Hitches while crafting and a once-a-second minimap redraw (2026-10-09).

## Walking a table that may change
Lines: \bpairs\(
Check: If anything inside the loop can add to or clear the table being
  walked, walk a copy instead.
Why: "invalid key to next" when a worker started another worker (2026-11).

## Player words
Lines: L\[\s*"|L\.Format\(
Check: Plain, warm, sixth grade, no em-dashes, hype or questions
  (`python tools/check_house_rules.py`). New words need the owner's yes. deDE and
  the other locales change with the English.
Why: The writing rule holds for every word a player reads.

## A call between the addons
Lines: _G\.Blackthornes|BlackthornesTS_API
Check: Calls between addons stay stable and run inside a pcall. A change to
  one is made in both repos together, after reading its section in
  Docs/claude-notes.md.
Why: A sister addon reading an old name breaks silently.

## The TOC, or a file added, removed or renamed
Files: \.toc$
Check: The reply says the game needs a full restart, not /reload. A new
  file is listed in the TOC in the right load order.
Why: A /reload does not pick up new files.

## A release version
Lines: RELEASED_VERSION|^## \d+\.\d+\.\d+
Check: ns.RELEASED_VERSION in Core/Init.lua matches the newest version in
  CHANGELOG.md (`python tools/check_release.py`).
Why: A checkout must show the real version number.

## Generated data
Files: ^Data/
Check: Data files are written by their tools/ script, never by hand.
Why: Hand edits were lost at the next fold-in.

## Defaults and settings
Lines: [Dd]efaults?\s*=|DEFAULTS
Check: Big new features start off. Never change a setting the player
  already chose.
Why: Standing rule from the owner.

## Sharing code (Tradeskills)
Files: ^Core/(Comm|Serialize)\.lua$|^Logic/Contribute\.lua$
Check: Core/Comm.lua and Core/Serialize.lua match Farmer's copies. The
  recipient lists in Logic/Contribute.lua match Farmer's and Equipment's.
Why: The two copies drifted and shared data stopped reading.

## The public price API (Tradeskills)
Lines: BlackthornesTS_API|GetPriceAge
Check: Never rename or change _G.BlackthornesTS_API, GetPrice or GetPriceAge.
Why: Other authors read it.

## Prices (Tradeskills)
Lines: GetValue|VendorPrice|SellPrice|quality\s*==\s*0
Check: Grey items are priced at vendor only; everything else is
  max(auction, vendor).
Why: Standing rule from the owner.

## A setting read by price source (Tradeskills)
Lines: TSM|Auctionator|DBRecent|DBMarket
Check: The setting is read where the number is shown, and the fallback stays
  quiet. Try the tooltip line in game: the fake TSM in tests answers whatever
  it is told, so the PR says "Not checked: real TSM in game".
Why: TSM Sold a Day (2026-11-16) passed tests before anyone saw it in game.

## Same character (Tradeskills)
Lines: Characters:(Same|IsPlaying|Canonical)|GetCharacterKey
Check: Ask Characters:Same, :IsPlaying or :Canonical, never compare by hand
  (tools/test_onecharacter.lua).
Why: One key per character.

## The fenced feature (Tradeskills)
Lines: ownAuctionHouse
Check: It stays off and out of releases until the owner says it is done.
Why: the owner's call.

## A tooltip's SetText with colours
Lines: GameTooltip:SetText\(
Check: Colours go text, r, g, b, alpha, wrap. With a wrap, put the alpha in
  too (`1, 1, 1, 1, true`); never `1, 1, 1, true`.
Why: The Profit tab's "Each craft makes" hover left out the alpha, so the
  wrap landed in the alpha slot and the game raised on every hover.

## Column headings that hide or step aside
Lines: Columns:Squeeze|Columns:Place\(.*headings|SortableHeadings
Check: The sorter's `Sync()` runs after every heading layout, not only when
  the set of hidden headings changes, and once right after the sorter is made.
Why: Recipes to Learn synced only on a change. The game laid the headings
  out while the sorter was being made, so hidden headings kept their clicks
  at their old spots, and a click on SKILL sorted by DISENCHANT.

## The game's pop-up box
Lines: StaticPopup_Show|StaticPopup_Hide|StaticPopupDialogs
Check: Never show, hide or add to the game's pop-ups from addon code. Ask in
  a window of our own (UI/PostConfirm.lua). `tools/test_gamepopup.lua` fails
  if a loaded file calls them.
Why: The List It question used the game's pop-up. The game lent the same box
  to "replace your weapon's enchant" later, and a Spellstone from the bags
  was blocked: "Blackthornes_TS has been blocked from an action only
  available to the Blizzard UI" (2026-11-19).

## An item link in a test
Files: tools/test_.*\.lua
Lines: Hitem:
Check: A test that reads a link uses Forever's shape too
  (`item:15012::::::::18:1485:::1:12722`): the old suffix field is empty
  and the suffix is a bonus ID. Copy a real link, never make one up.
Why: Suffix prices were tested with Classic links only
  (`item:1076::::::612`), so they passed while no copy in the game was
  ever matched to its suffix (2026-11-19).

## A flag whose meaning changes
Lines: counted|likely|breakdown\.outcomes
Check: When a field on a returned table comes to mean something else (or
  is now set on every row), grep every reader of it across Logic/ and UI/
  and change each one, and make the test stubs hand back the new shape.
Why: Disenchant value became an average and `counted` went true on every
  outcome; the Profit tab still picked the age's material by it and read
  the rarest one, while its test stub kept the old shape (2026-11-20).
