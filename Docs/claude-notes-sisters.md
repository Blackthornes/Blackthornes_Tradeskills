# Claude notes: sister addons

Moved verbatim from CLAUDE.md (what Farmer, Equipment and Butler call here, and what Tradeskills calls there). Grep a heading, then read about 150 lines at a time.

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

Farmer's top farm alert (2026-10-14) also asks to hear when a scan
finishes, inside a pcall:

```lua
_G.BlackthornesTS.Prices:WatchScans(fn)   -- fn({ items, at }) after each scan that wrote prices
```

`Prices:ScanFinished(result)` (from `UI:OnScanComplete`, only for a scan
that recorded prices) calls each watcher in a pcall and moves
`Prices.scanCount`. Keep `WatchScans` stable; if it changes, change
Farmer's `Logic/TopFarm.lua` too. Tested in `tools/test_scanwatch.lua`.

## How Tradeskills uses Farmer

The Gather tab's **Set goal** button (`Logic/FarmerGoals.lua`) turns a
material the queue still needs into a Farmer gathering goal. It shows only
when Farmer is loaded (`## OptionalDeps: Blackthornes_Farmer` in the TOC) and
calls, inside a pcall:

```lua
_G.BlackthornesFarmer.Goals:Find(name)            -- optional, to say "updated"
_G.BlackthornesFarmer.Goals:Set(name, amount)     -- goal table, or nil and why
_G.BlackthornesFarmer.GoalsUI:Show()              -- opens Farmer's Goals panel
_G.BlackthornesFarmer.Goals:Remove(name)          -- the queue no longer needs it
```

`name` is the item's plain name and `amount` the row's NEED. A goal made
with Set goal follows the queue (the owner, 2026-10-11, "work for the user
almost like magic"): `FarmerGoals:Remember` keeps it in
`farmerGoalsFromQueue[characterKey][itemID] = { name, target }` (never
rename it), and a second after a burst of `Queue:Notify` calls
`FarmerGoals:Follow` sets it to the shopping list's new `needed`, or
removes it when nothing queued needs it or the bags already hold enough.
A goal whose target the player changed in Farmer, or that finished or was
removed, is let go and never touched again. "Goals follow the queue"
(`farmerGoalsFollowQueue`, on unless unticked) on the Queue page. Farmer's goals
belong to the character that set them, so `Find` and `Set` act on the
character playing. Farmer's `CLAUDE.md` asks its side to keep these stable;
if one changes, change `Logic/FarmerGoals.lua` in the same breath.

## Craft or farm (the Your time view)

The owner said yes (2026-10-15, from a mockup): the Profit tab's switch
reads MY CRAFTS, YOUR TIME, RECIPES TO LEARN (`RecipeBookView.WithSwitch`
takes `extras`). `Logic/CraftOrFarm.lua` works out, for each craft the
character playing knows, three ways: farm the materials and craft (gold an
hour), farm them and sell them as they are (gold an hour), and buy them
and craft (the Profit tab's profit for one craft, never an hour, since a
craft takes seconds). Farming time is the player's own, from Farmer,
inside a pcall, read only:

```lua
_G.BlackthornesFarmer.Pace:ForItem(itemID)
  -- { seconds, kind, source, zone, samples, perAction }, or nil and { samples }
```

Crafting time is `CraftTime:GetCast` for every cast in the tree. A
material a vendor keeps in stock is bought on every way; one a craft of
the player's makes, with no pace of its own, is followed down to what it
is made from (`DEPTH`). Without Farmer, or with under 20 of the player's
own kills or gathers behind a material, the farm ways stay "--", never
guessed from drop tables. Walking and selling are not counted. Built a few
crafts a frame (`BUDGET`), kept `KEEP` seconds, nothing saved.
`UI/YourTimeView.lua` draws it (columns `yourtime`; right-click or Queue 1
queues one). Farmer's material tooltip asks:

```lua
_G.BlackthornesTS.CraftOrFarm:ForMaterial(itemID)
  -- { name, recipeID, perHour, rawPerHour } when crafting beats selling, or nil
```

Keep both calls stable; if one changes, change Farmer's `Logic/Pace.lua`
or `UI/ItemTooltip.lua` too. Tested in `tools/test_craftorfarm.lua` and
`tools/test_yourtimeview.lua`. Not yet seen in game.

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

Enchants for your gear (a player asked, the owner said build it,
2026-10-16): an enchanting recipe makes no item, so the Level Up tab shows
its spell's icon (`Theme.SetSpellIcon`), and when Equipment says it beats
what is on the gear worn, the green arrow and "For you: Chest +3%" on the
row, the detail pane, the row's tooltip, "Best for you" on the Learn next
pane and on the enchant's own tooltip (`UI/EnchantTooltip.lua`). It
follows `showUpgradeArrows` and asks, inside a pcall, kept per recipe and
forgotten with the item answers (`Upgrades:EnchantFor`, `EnchantText`):

```lua
_G.BlackthornesEquipment.Enchants:ForRecipe(recipeID)
  -- { slot, slotID, gain, current, best }, or nil
```

Equipment's Enchants view in Where to get upgrades calls back, inside a
pcall, besides `Queue:Ensure` and `Queue:EnsureBuy`:

```lua
ns.LearnNext:WhereFor(recipeID)       -- { kind, name, zone, x, y, price } or nil, a fresh table
ns.LearnNext:ShowTheWayFor(recipeID)  -- Show the way by recipe ID; true when a pin was set
```

Keep these stable; if one changes, change Equipment's `Logic/Enchants.lua`
too. Tested in `tools/test_enchantsforyou.lua` and
`tools/test_learnnext.lua`. Not yet seen in game.

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
ns.RecipeBook:GetSkill(recipeID)       -- the skill a recipe needs on Forever, or nil
```

`GetSkill` (added 2026-10-09, after a player found Forever had moved some
Leatherworking patterns to lower skills) answers what the recipe item's
own tooltip says (`Logic/RecipeBook.lua`, `RecipeBook:LearnSkill`, kept
account wide in `recipeSkills[recipe item ID]`, never rename it), then
the players' reports in `FOREVER_SKILLS`, then Classic's book.

Keep these stable as well; if one changes, change Equipment's
`Logic/Crafting.lua` in the same breath.

Equipment's **Queue it** button (a player asked on Discord, the owner agreeing
2026-10-10; on crafted rows in Where to get upgrades and the Upgrade
quest's Crafted tab) calls, inside a pcall, through its
`Logic/TradeskillsQueue.lua`:

```lua
ns.Queue:Ensure(recipeID, quantity)         -- at least that many queued; true, or nil and why
ns.Queue:EnsureBuy(itemID, count, forItem, forRecipe)  -- that many on the list to buy for forItem; true, or nil and why
ns.Queue:ForUpgrade(itemID, recipeID)       -- "craft", "buy" or nil: what the queue holds for the gear
ns.Queue:ShowQueue()                        -- opens the window on the Queue tab
```

Gear the character or an alt can make is queued; gear it still has to
learn has its materials put on the list to buy; gear nobody makes goes on
the list itself. Since 2026-11-07 a pattern's materials come with
`forRecipe` (`crafts = 1`), so learning it queues the craft
(`QueueLearned`), `Queue:Ensure` drops lines for that recipe
(`DropBoughtFor`), and `ForUpgrade(itemID, recipeID)` finds them by
recipe. Tested in `tools/test_queuebuys.lua`. The list to buy is `queueBuys` (account wide, each line
kept for its `owner`, never rename it). A line goes when the gear's craft
is queued (`Queue:Add`), when the gear is owned or worn, with its row's x
on the Queue tab, or with Clear all. Keep these four stable; if one
changes, change Equipment's `Logic/TradeskillsQueue.lua` too.

## What Butler calls here

**Blackthornes_Butler** (`Blackthornes/Blackthornes_Butler`, the owner's
new addon, 2026-10-10) tells the player what to do with each item in the
bags. It asks Tradeskills one thing, through its `Logic/Sisters.lua`,
inside a pcall, read only, with no TOC dependency:

```lua
_G.BlackthornesTS.Butler:Advise(item)   -- item ID or the bag copy's link; a table, or nil; never raises
```

A link (2026-10-15; `Butler.TAKES_LINK` says it can) prices a random suffix ("of the Monkey") as that
suffix sells: `auction` and `auctionNow` read `Prices:GetLinkValue`, which
answers the suffix's own price when one is recent, else the item's.

`Logic/Butler.lua` answers with a fresh table, any field nil when unknown:

- `auction`: copper for one sold on the auction house, after the cut and
  the deposit (`Profit:NetFromListing` on `Prices:GetValue(itemID,
  "market")`), never below 0. nil for greys (vendor only), gear that binds
  when picked up, and items never priced.
- `auctionNow`: the same, at the cheapest listing that is not the
  player's own (`Prices:GetScanValue(itemID, "rival")`), only while the
  scan is fresh (`Prices:IsStale`); nil without `auction`. Butler holds
  an item back when it is well below `auction` (2026-10-13).
- `belowCost`: copper one costs to make, when the Sell list's price for it
  (`Posting:GetChosenPrice`, else `GetPostPrice`) is under that and
  Posting would refuse it (`Posting:BelowCost`, or `BelowCraftedCost` with
  "Never below what I paid" on); nil for anything not crafted, a price that
  covers it, or "Recommend selling at a loss" ticked. Butler holds such an
  item back instead of saying Auction (2026-10-13).
- `fast`: `Demand:Get` "high" is true, "low" false, "some" or no reading nil.
- `disenchant`: `Disenchant:GetValue`, copper for one; nil when it cannot
  be broken or its material has no price.
- `canDisenchant`: the character playing knows Disenchant
  (`Disenchanter:Knows`) and has the Enchanting the item needs; false for
  anything that cannot be disenchanted, nil while the item is not loaded.
- `enchanter`: only when the character playing cannot: the disenchanter
  typed in Settings (`QueueMail:GetDisenchanter`, up to its quality), else
  the alt on this account (not `linkedFrom`, `Queue:CanMail`) with the most
  Enchanting that is enough. The full name.
- `disenchanter`: the disenchanter typed in Settings (full name) when the
  item is gear the Mail page sends there (`QueueMail:GoesToDisenchanter`:
  green up to the quality picked, can be disenchanted, does not bind when
  picked up, not crafted (`RecipeBook:IsCrafted`: any recipe makes it),
  no upgrade for the character playing; the owner asked 2026-10-11 for
  Butler to follow that setting, for "disenchantable, non-crafted items").
  With the box empty it is the one picked for the player
  (`QueueMail:GuessDisenchanter`, 2026-10-11, "do the work for the
  player"): the alt on this account, same realm and side (`Queue:CanMail`,
  not `linkedFrom`), with the most Enchanting, if more than the character
  playing; "Pick one for me" on the Mail page (`disenchanterGuess`, on
  unless unticked, never rename it) turns that off, and then it is nil.
  `GetDisenchanter` returns the name and `true` when it was picked; the box
  shows the pick where "Character name" sits. A typed name always wins.
  `GetDisenchantDelivery` uses the same rule, so the two never disagree.
- `need`: what this character's own queued crafts use from its bags (use,
  less what it makes, less its bank), as `QueueMail:GetDeliveries` keeps back.
- `mailTo`, `mailCount`: the alt `GetDeliveries` would send the most of it
  to, full name, and how many. Since 2026-11-07 it can be a linked
  account's character (Share Craft Queue ticked on both accounts, same
  realm by `RealmKey` and side), and `Jobs()` can give the character
  playing a mail step to one. Never a craft, pickup or Log out step for a
  linked character; `FillMail` already takes its full name.
- `bought`: how many the account bought on the auction house to
  disenchant (`DisenchantBuys:Count`), nil for none.
- `forEnchanting` (the owner asked 2026-10-13): a green the character
  playing can disenchant, not crafted (`RecipeBook:IsCrafted`), whose
  likely material (chance at least `Butler.LIKELY_OUTCOME`, 0.15) its own
  Enchanting still lacks for the crafts that give a point every time:
  `{ recipe, material, materialName, short, yield }`. The orange recipes
  it knows (the profession window's reading at this skill, else up to the
  book's `yellow`) are taken cheapest first, each for the points the ones
  before do not reach, and what it owns (bags, bank, mailbox) comes off,
  so it stops once there is enough. Kept in the lookup. Butler then says
  Disenchant. Tested in `tools/test_butlerenchanting.lua`.
- `youDisenchant` (the owner asked 2026-10-14): true when the character
  playing is the disenchanter (`QueueMail:IsDisenchanterPlaying`: the name
  typed on the Mail page, else, with the box empty and "Pick one for me"
  on, this character when it has Enchanting and no character it can mail
  has more), nil otherwise; kept in the lookup. `crafted`: true for a
  green some recipe makes, asked only then. Butler's "Disenchant greens
  here" (off unless ticked) reads both. Tested in
  `tools/test_butlerenchanting.lua` and `tools/test_disenchantmail.lua`.

Bought to disenchant (the owner asked 2026-10-11): `Logic/DisenchantBuys.lua`
marks an auction house buy that follows a search sent from the
Disenchanting tab (`Intend`, then `OnBought` from `AHBuys:Confirm`, within
15 minutes). Marks are account wide, by item and count, in
`boughtToDisenchant[itemID] = { count, at }` (never rename it), so mailing
or banking keeps them; they only shrink on a disenchant
(`DisenchantLog:Record` calls `Used`) or when the account holds fewer
(`Settle`: every character's bags, bank and mail, mail on its way, auction
buys in the mail; once per burst of bag events, never while the mailbox is
open). The tab's bags list puts them first, tagged, and picks them first
for its Disenchant button; a right-click there marks or unmarks. Butler's
menu calls, inside a pcall:

```lua
_G.BlackthornesTS.Butler:SetBoughtToDisenchant(itemID, on, count)  -- true, or false and why
```

Butler asks once per bag item, a hundred in a burst, so the queue plan,
the deliveries and the characters' Enchanting are read once into a lookup,
kept until `Queue.version` (moved by `Queue:Notify`) or
`Inventory.changes` moves, or two seconds pass, and built again only on
the next question. Keep the call and the fields stable; if one has to
change, change Butler's `Logic/Sisters.lua` in the same breath.

Butler's All characters list (a player asked, the owner agreeing
2026-10-10) asks once each time that list is built, never per item:

```lua
_G.BlackthornesTS.Butler:Holdings()   -- a list, or nil; never raises; reads only
```

One entry per character on record, in `Recipes:GetCharacters`' order (the
character playing first): `key`, `name`, `short`, `realm`, `faction`,
`isCurrent`, `playing` (the character playing under any of its records,
`Characters:IsPlaying`; added 2026-10-11, never mail it), `linked` (the
character it came through, for another account of the owner's), and `bags`, `bank`, `mail` as fresh `{ [itemID] = count }`
copies with `bagsAt`, `bankAt`, `mailAt` (`time()`, nil when never read),
and `gold`, `goldAt` (copper as last seen with the bags' snapshot, live for
the character playing; nil when never recorded; added 2026-10-11 for
Butler's gold top-ups).
The playing character's bags are live (`Inventory:GetBagCounts`), the rest
the saved snapshots (`inventory`, `bank`, `mail` on its record). Keep it
stable too; Butler's `Logic/Everyone.lua` reads it.

Mail running out (the owner said build it from a mockup, 2026-11-09, for
Butler's "Mail Running Out"): each inbox read (`Mail:Read`) saves
`record.mailExpiry = { count, soonest, soon, returns, gone }` on the
character's record (never rename it; `Mail.Expiry`): how many mails the
box showed, the soonest `daysLeft` of any, how many run out within
`Mail.SOON_DAYS` (3) and of those how many go back to the sender
(`Mail.GoesBack`: the game's `InboxItemCanDelete` when it has one, else a
player's mail with money or items not sent back once already) or are
gone for good. `Holdings()` entries carry them as `mailCount`,
`mailSoonest`, `mailSoonCount`, `mailReturns` and `mailGone` (nil until
read this way), as of `mailAt`; Butler counts the days since. Tested in
`tools/test_mailrunsout.lua` and `tools/test_butler.lua`. Not yet seen in
game. If they change, change Butler's `Logic/MailRunsOut.lua` too.

Clear Items and stale alts (a player's report, the owner said build it
from a mockup, 2026-11-10: Butler's jobs mailed items long gone and gold
already collected). Each inbox read saves `record.mailMoney` (copper the
box held), and `Holdings()` entries carry `mailMoney` and `clearedAt`, so
Butler's gold notes can tell gold was picked up. The Characters tab has
**Clear Items** left of Forget character (armed, "Confirm", never the
character playing): `Recipes:ClearItems(key)` (`Recipes.CLEARED_FIELDS`)
forgets that character's saved bags, bank, mail and gold, keeps
`seenAt`, sets `clearedAt`; nothing else on the record changes. Butler's
own menu calls `Butler:ClearHoldings(key or full name)` (true and the full
name, or false and "playing", "unknown" or "error"). The job holder skips
an alt whose bags are older than `Butler.STALE_DAYS` (30;
`Butler.Stale`). Tested in `tools/test_clearitems.lua` and
`tools/test_butler.lua`. Not yet seen in game.

At a mailbox and the bank (the owner said start, 2026-10-11), Butler's
`Logic/Errands.lua` calls two more, inside a pcall:

```lua
_G.BlackthornesTS.Butler:FillMail(name, items, money)  -- true, or false and why; never raises
_G.BlackthornesTS.Butler:FromBank()             -- { [itemID] = count }, or nil; reads only
```

`FillMail` fills the Send Mail page through `QueueMail:Fill` for one of
the player's characters (`name` as Advise gave it, resolved with
`QueueMail:FindCharacter` and `MailName`; `items` a list of `{ itemID,
count }`, subject "From Blackthornes Butler"; `money`, optional copper,
goes in the gold boxes through `QueueMail.PutMoney`, gold alone being a
mail of its own, never with COD ticked and never more than the purse less
postage); the player presses Send and
QueueMail's own SendMail hook writes down what went. What did not fit
or could not be split goes in chat (`Butler.FillDone`), since Butler's
window covers the mail panel that says it; a split goes in the stack's own
bag first, then an ordinary bag, then a profession bag made for the item
(2026-10-13, herbs in a herb bag were left out). It never fills a mail
to the character playing, under any record of it (`QueueMail:IsPlaying`:
its key, a record carrying its GUID, or the old name-realm record left
beside the GUID one; a player found Butler filling one, 2026-10-11), and
answers false and "that's the character you're on"; filled, its third
return is the full name it went to, for Butler's chat line. Deliveries,
the enchanter and `FindCharacter` leave those records out too. `FromBank` is what
the playing character's own queued crafts use, less what it makes and
carries, no more than its bank holds, plus the `bank` count of its Jobs
mail for another character's craft (so Butler opens at the bank and
takes it out; 2026-10-11). Keep both stable too.

A craft step for the character playing also carries `slots` (the bag slots
making it frees, `Crafting:SlotsFreed`; nil with "Craft what frees bag space
first" off), which Butler's `Jobs.Order` sorts its plain crafts by (the
owner, 2026-10-15). Keep it stable.

Butler's step list for jobs on other characters (the owner asked
2026-10-11: "craft Medium Leather on another, then send it back") calls
two more, inside a pcall:

```lua
_G.BlackthornesTS.Butler:Jobs()            -- a list, or nil; never raises; reads only
_G.BlackthornesTS.Butler:Craft(recipeID)   -- true and "crafting" or "opened", or false and why
_G.BlackthornesTS.Butler:Profession(recipeID)  -- { name, spell, open }, or nil
```

`Jobs` is one entry per character with something to do in the queue (the
character playing first, then by name; only characters it can mail, never
`linkedFrom`): `key`, `name` (full), `isCurrent`, `steps`. A step is a
craft (`kind = "craft"`, `recipeID`, `itemID`, `name`, `count` made,
`crafts`, `forNames` in full, `ready`, `missing = { { itemID, count } }`
from `Queue:HeldBy`) or a mail (`kind = "mail"`, `to` in full, `items`,
`crafts`): the playing character's `QueueMail:GetDeliveries`, the others'
`QueueMail:GetOwedBy(key)` (made for someone, not yet mailed). A craft
held up for materials another character carries or banks names it as
that missing item's `from`, and that character gets a mail step to the
crafter first (`forCraft = true`), so Butler can send the player there
before the craft (the owner, 2026-10-11: a sub-craft whose materials are
on hand goes to the top). The character playing counts too, read live,
its item's `bank` saying how many to take out of the bank first, and the
same item in its deliveries joins that mail rather than making a second
(a player logged in on the holder and the mail step was gone,
2026-10-11). An old name-realm record of the
crafter (`SameCharacter`) counts as the crafter's own. Each missing
material carries `vendor`, the copper for one when a vendor sells it
(`Vendor:GetUnitPrice`), so Butler lists it under Buy from a vendor and
the rest under Buy or gather (the owner, 2026-10-13). Records of one
character (its GUID one and an old name-realm one) are one entry, named
by the GUID record, and no step mails a character to itself under any
of its records (a player was told to log out for the character they were
on, 2026-10-11). `Craft`
runs the playing character's queued craft of that recipe from Butler's
click: `Crafting:Start` when the profession window shows it, else
`Queue:ShowQueue()` so the Open button opens the profession. Mail
waiting for a character (the owner, 2026-10-13: "if a character needs to
visit the mail for something sent to it, butler should move that up the
priority list") is a `pickup` step put first on its line (`items`,
`forCraft`): materials its crafts count on (`Queue:HeldBy`) that are not in
its bags or bank, so sit in its mailbox or are on their way, and anything
else mailed to it and not yet seen arrive (`QueueMail:InFlightItems`).
`Profession` (2026-10-15) names the profession a recipe is made in and the
spell that opens its window (`ProfessionOpener:ProfessionFor`), with `open`
while the window shows the recipe, so Butler's Craft button can open the
profession through a secure button of its own and craft on the next click.
Tested in `tools/test_butlerjobs.lua`. Keep all three stable; Butler's
`Logic/Jobs.lua` reads them.

Butler takes over the mailbox (the owner picked it, 2026-10-11): its
window comes up at every mailbox, and while it is up there it calls

```lua
_G.BlackthornesTS.Butler:Mailbox(covered)   -- true: the mail panel steps aside; false: it comes back
```

`UI/QueueMailPanel.lua` stays hidden while `coveredByButler` is set
(cleared on `MAIL_CLOSED`), so closing Butler's window brings it back.
Butler's Always mail list names characters from `Holdings()` (same realm
and faction). Keep `Mailbox` stable; Butler's `Logic/Errands.lua` calls it.

Butler's gold goals (the owner said build it, 2026-10-13) ask what the
trainers' recipes the character playing could learn now would cost:

```lua
_G.BlackthornesTS.Butler:LearnCost()   -- { [Classic skill line] = { skill, count, cost, recipes } }, or nil
```

`recipes` (2026-10-22, a player asked which recipe it meant) is `{ {
recipeID, name, cost } }`, cheapest first; Butler names them on the goal's
hover and a click calls `LearnNext:ShowTheWayFor(recipeID)`.

Recipes with a trainer's price in the book, reached by the skill, not
learned and not grey (`LearnNext.Tier`), by profession; a profession
whose recipes were never read is left out. Kept 30 s, or until the
character's `recipesCachedAt` moves. Tested in `tools/test_learnnext.lua`.
Keep it stable; Butler's `Logic/GoldGoals.lua` reads it.

Butler's Buy from a vendor row (the owner asked 2026-10-14 for the Buy
materials button in Butler too) has the same button, calling, inside a
pcall:

```lua
_G.BlackthornesTS.Butler:VendorOffer()     -- { count, cost, items, cheaperElsewhere, buying }, or nil
_G.BlackthornesTS.Butler:BuyFromVendor()   -- true, or false and why; never raises
```

`VendorOffer` is `Vendor:GetNeeded`'s answer (nil while no vendor is open
or its list is not read), `BuyFromVendor` the button's own click
(`Vendor:BuyNeeded`, then `UI:UpdateMerchantButton`). Tested in
`tools/test_butlervendor.lua`. Keep both stable; Butler's `Logic/Jobs.lua`
reads them. While Butler is loaded and its window opens at vendors (its
`openAtVendor`, read from `BlackthornesButlerDB`), the Buy materials button
over the vendor window hides (`UI.ButlerBuysHere`, the owner 2026-10-18):
Butler's Buy row does the buying. Tested in `tools/test_merchantbutton.lua`.

Butler's tooltip line "Vendors sell it for 25c" (a player asked, the
owner said build it, 2026-10-22) asks what a vendor charges for one,
inside a pcall, read only:

```lua
_G.BlackthornesTS.Butler:VendorPrice(itemID)   -- copper, or nil
```

`Vendor:GetUnitPrice`'s answer (a price seen at a merchant, else
`Data/VendorPrices.lua`); nil for anything no vendor is known to sell.
Tested in `tools/test_butlervendor.lua`. Keep it stable; Butler's
`Logic/VendorPrices.lua` reads it.

Butler's "For your quests" line (a player asked 2026-10-14, the owner said
build it: buy what open quests need) has a Search button at the auction
house, calling, inside a pcall:

```lua
_G.BlackthornesTS.Butler:SearchAuctions(items)   -- { { itemID, count } }: true and "all" or "one", or false and why
```

Several items go in one `ShoppingLists:SearchMany` ("all"); where the game
takes one a search, the first goes through `UI:SearchAuctionHouse` with its
count for the buy box ("one"), and Butler sends the rest on the next click.
Tested in `tools/test_butlersearch.lua`. Keep it stable; Butler's
`Logic/Quests.lua` calls it.

Butler's bank alt (a player asked, the owner said build it, 2026-10-14)
can take everything on one of the player's shopping lists, so it reads
them, inside a pcall:

```lua
_G.BlackthornesTS.Butler:Lists()   -- { { name, id, items = { [itemID] = want } } }, ShoppingLists.version; or nil
```

`id` (2026-10-19) is the list's stable id (see "List rules"); Butler's
Lists page keeps its own Mail To and Keep Here for a list by it.

The player's own lists only (`ShoppingLists:Readable`), never the craft
queue's, fresh tables each time; nothing is written. Tested in
`tools/test_butlerlists.lua`. Keep it stable; Butler's `Logic/BankAlt.lua`
reads it.

Butler's "Cheapest Skill-Up" line in Jobs (a player asked, the owner said
build it, 2026-10-19; off unless ticked in Butler) shows the Level Up
tab's top pick for each profession, inside a pcall:

```lua
_G.BlackthornesTS.Butler:NextSkillUp()      -- { { profession, skill, max, recipeID, itemID, name, tier, cost, queued, toBuy } }, or nil
_G.BlackthornesTS.Butler:QueueSkillUp(id)   -- one in the queue: true, or false and why
```

The first row of each profession in `LevelUp:GetRanked`'s order that is a
sure or likely point with a priced cost (`cost` is REAL COST, below 0 when
the craft pays). A profession at its max for now (2026-10-20, the owner:
Butler names the next trainer) comes as `{ profession, english, skill, max,
capped = true }` with no recipe, from the rows and from the saved read
(`Recipes:GetLearnedProfessions`); an older Butler skips it. Kept 30 s, or
until the queue, bags, a scan, the recipes, the purse or "Can afford"
move. `toBuy` (2026-10-22) is copper to buy what the bags and bank lack
(`LevelUp.ToBuy`), and Butler shows the same red note when it is more
than the purse; with "Can afford" ticked the pick skips crafts the purse
can't cover. Tested in `tools/test_butlerskillup.lua` and
`tools/test_canafford.lua`. Keep both stable; Butler's `Logic/Jobs.lua`
reads them.

Butler's "Craft When It Pays More" (a player asked, the owner said build
it, 2026-10-19; off unless ticked in Butler) asks, only while it is on,
inside a pcall:

```lua
_G.BlackthornesTS.Butler:CraftFor(item, carried)
  -- { recipeID, name, itemID (what it makes), per, crafts, perItem, needs = { { itemID, count } },
  --   others = { { itemID, count } } }, or nil
_G.BlackthornesTS.Butler:QueueCraft(recipeID, crafts)   -- Queue:Ensure; true, or false and why
```

Only recipes the character playing knows (not a dropped profession) that
use the item. Each is valued by `Profit:Analyse` "best" after the cut and
deposit (a slow auction at `Butler.SLOW`, a derived or uncontested price
never), less the other materials (`Cost:GetCraftCost`, owned at their
worth); `perItem` is that over how many one craft uses. `needs` is what
the bags lack for those crafts; `others` (2026-11-14, for Butler's "Craft
Details:" tooltip, the owner said build it) is every other material they
use, carried or not, so Butler can say "With Tin Bar." Kept in the
lookup. Tested in `tools/test_butlercraft.lua`. Keep both stable; Butler's
`Logic/Sisters.lua` reads them.

