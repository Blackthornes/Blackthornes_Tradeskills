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
ns.Queue:EnsureBuy(itemID, count, forItem)  -- that many on the list to buy for forItem; true, or nil and why
ns.Queue:ForUpgrade(itemID)                 -- "craft", "buy" or nil: what the queue holds for the gear
ns.Queue:ShowQueue()                        -- opens the window on the Queue tab
```

Gear the character or an alt can make is queued; gear it still has to
learn has its materials put on the list to buy; gear nobody makes goes on
the list itself. The list to buy is `queueBuys` (account wide, each line
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
_G.BlackthornesTS.Butler:Advise(itemID)   -- a table, or nil; never raises
```

`Logic/Butler.lua` answers with a fresh table, any field nil when unknown:

- `auction`: copper for one sold on the auction house, after the cut and
  the deposit (`Profit:NetFromListing` on `Prices:GetValue(itemID,
  "market")`), never below 0. nil for greys (vendor only), gear that binds
  when picked up, and items never priced.
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
  to, full name, and how many.
- `bought`: how many the account bought on the auction house to
  disenchant (`DisenchantBuys:Count`), nil for none.

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
QueueMail's own SendMail hook writes down what went. It never fills a mail
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

Butler's step list for jobs on other characters (the owner asked
2026-10-11: "craft Medium Leather on another, then send it back") calls
two more, inside a pcall:

```lua
_G.BlackthornesTS.Butler:Jobs()            -- a list, or nil; never raises; reads only
_G.BlackthornesTS.Butler:Craft(recipeID)   -- true and "crafting" or "opened", or false and why
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
crafter (`SameCharacter`) counts as the crafter's own. Records of one
character (its GUID one and an old name-realm one) are one entry, named
by the GUID record, and no step mails a character to itself under any
of its records (a player was told to log out for the character they were
on, 2026-10-11). `Craft`
runs the playing character's queued craft of that recipe from Butler's
click: `Crafting:Start` when the profession window shows it, else
`Queue:ShowQueue()` so the Open button opens the profession. Tested in
`tools/test_butlerjobs.lua`. Keep both stable; Butler's `Logic/Jobs.lua`
reads them.

Butler takes over the mailbox (the owner picked it, 2026-10-11): its
window comes up at every mailbox, and while it is up there it calls

```lua
_G.BlackthornesTS.Butler:Mailbox(covered)   -- true: the mail panel steps aside; false: it comes back
```

`UI/QueueMailPanel.lua` stays hidden while `coveredByButler` is set
(cleared on `MAIL_CLOSED`), so closing Butler's window brings it back.
Butler's Always mail list names characters from `Holdings()` (same realm
and faction). Keep `Mailbox` stable; Butler's `Logic/Errands.lua` calls it.

## Profession cooldowns

The owner said yes (2026-10-12) to keeping profession cooldowns for every
character. `Logic/Cooldowns.lua` keeps, account wide,
`professionCooldowns[characterKey][id] = { name, group, readyAt, recipeID
or itemID, told }` (never rename it; `id` is `spell:N` or `item:N`): Classic's
cooldown crafts (`Cooldowns.KNOWN`: transmutes, Mooncloth) once the
character's recipes include them, any learned craft the game says is
cooling down (the profession window's harvest calls `Cooldowns:NoteRecipe`
with `C_TradeSkillUI.GetRecipeCooldown`; a cast by the character reads its
spell cooldown a second later), and the Salt Shaker while carried
(`Cooldowns.ITEMS`). Crafts sharing a cooldown show once, by `group` (the
name before the colon). A ready one is said in chat once each time it comes
ready (`told`), at login and from one timer for the next to come ready, and
the Characters tab's detail lists them. "Profession cooldowns" on the Look
page (`cooldownAlerts`, on unless unticked) and `/bts cooldowns`. Butler's
`Jobs()` gives each ready group as a `cooldown` step, and `Butler:Craft`
makes a ready cooldown craft once, queued or not. Tested in
`tools/test_cooldowns.lua` and `tools/test_butlerjobs.lua`. Not yet seen in
game.

## Craft requests in Trade

The owner said yes (2026-10-12) to a word in chat when someone in Trade
asks for something the player's characters make. `Logic/CraftRequests.lua`
listens to `CHAT_MSG_CHANNEL` (Trade by its channel number 2, else a name
with "Trade" or "Handel"): a line with an asking word (`ASK`: LF, WTB,
need, anyone, suche...) and no selling word (`SELL`: WTS, LFW, can make,
tips...) is matched against every character's recipes, by item or enchant
link, else by name (longest first) or an enchant's effect with its slot or
"enchant". It prints "NAME in Trade wants ITEM. You and FULL NAME can make
it." with the asker as a player link to whisper. Reads only, saves
nothing; one asker and item once per `REPEAT_GAP`; the player's own lines
skipped; every read in a pcall (chat can be secret). The names are laid
out again only when the recipe count changes (checked at most every
`REBUILD_GAP`). "Craft requests in Trade" on the Look page
(`tradeRequests`, off unless ticked, the owner 2026-10-12; never rename it) and `/bts requests`.
Tested in `tools/test_craftrequests.lua`. Not yet seen in game.

## Learn next

The owner said build it (2026-10-12), from a mockup he picked
(`mockups/tradeskills-learn-next-mockup.png` in the project files, Show
the way buttons in one column). The Level Up tab's own list goes on past
what the character knows: under a LEARN NEXT heading, the recipes they
have not learned that a trainer or vendor teaches and that raise the skill
now, cheapest way up first, then any a few points out of reach
(`LearnNext.REACH`), greyed, "At 120". `Logic/LearnNext.lua` builds the
rows (`GetRows`, `Place` picks a trainer or vendor of the player's side
that teaches that far, the zone they are in first, then a city);
`UI/Tab_LevelUp.lua` adds the LEARN, WHERE and Show the way columns (shown
only while "Learn next" is ticked, `levelUpLearnNext`, on unless unticked,
never rename it) and a detail pane with Show the way and Queue materials
(enough to craft until it turns yellow, `Queue:EnsureBuy`). Show the way
(`LearnNext:ShowTheWay`, also a right-click on the row) puts the game's
own map pin on them, or hands TomTom the place when it is installed
(`Logic/Waypoints.lua`, Equipment's trimmed to the pin), and says where in
chat; `/bts probe` has a "show the way" line.

`Data/LearnSpots.lua` is generated by `tools/make_learn_spots.py`, never
by hand: Forever's own skill to learn, yellow and grey for each recipe
(the client tables give yellow and grey; the skill to learn is Classic's
moved as much as the yellow moved), the trainers of each profession with
the highest skill they teach, and the spots of the vendors
`Data/RecipeBook.lua` names. `RecipeBook:GetAll` lays those skills over
the book (keeping Classic's as `classicSkill`); players' reports and a
recipe item's tooltip still win. Never name where the data came from in
the repo. Tested in `tools/test_learnnext.lua`. Not yet seen in game.

## Profit by method

A player asked (2026-10-11, the owner agreeing) for profit split by how it
was made. The Sales tab's **Profit by method** view (`Logic/MethodProfit.lua`,
a Period menu like Gold in and out) lists Crafted, Flipped, Vendored,
Disenchanted and Other sales, each with its items beneath. Auction sales are
read from the mail ledger: a stamped `entry.cost` is crafted, or flipped
when `entry.bought` (the average paid on the auction house, stamped in
`Mail:Describe` from `MethodProfit:BuyCost`). Vendor sales come from the
buyback list (`Vendor:ReadBuyback` hands it to `MethodProfit:NoteBuyback`;
the first look of a visit is the baseline) and disenchants from
`DisenchantLog:Record`; both are kept per realm in `methodLog[realm].events`
(never rename it), and `AHBuys:NoteCost` keeps what was paid in
`methodLog[realm].buys`. An item with no cost known counts as all profit and
the panel says how many. Tested in `tools/test_methodprofit.lua`. Not yet
seen in game.

## The public price API

The owner said yes (2026-10-12) to a documented price call for other
authors' addons. `Logic/PublicAPI.lua` sets `_G.BlackthornesTS_API` with
`version` (1), `GetPrice(item)` (`Prices:GetValue(id, "market")`, copper or
nil) and `GetPriceAge(item)` (`Prices:GetAge`, seconds or nil); `item` is
an ID or a link, and neither ever raises. The README's "For addon authors"
section documents it. Other people's addons read it, so never rename or
change these; a new call raises `version`. Tested in
`tools/test_publicapi.lua`.

## Sharing between accounts and with a guild

Asked 2026-10-07 (on Discord, the owner agreeing). Over addon
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

TradeSkillMaster (a player asked, the owner agreed 2026-10-12 and said TSM
may be named in public for this, a second exception beside TomTom):
`Logic/TSMPrices.lua` reads `TSM_API.GetCustomPriceValue("DBMarket" or
"DBMinBuyout", "i:<itemID>")` inside a pcall, no TOC dependency, kept 60 s
an item. `Prices:GetValue` asks it only when neither your scans nor guild
prices have the item ("rival" never). "TSM prices" on the Sharing page
(`tsmPrices`, on unless unticked, never rename it). So Farmer's, Equipment's
and Butler's `GetValue` can answer from TSM too; still copper or nil. TSM's
prices come from its desktop app, which may not cover Forever's realms; then
it answers nil. Tested in `tools/test_tsmprices.lua`. Not yet seen in game.
Auctionator comes after TSM (the owner said yes and allowed naming it,
2026-10-12): `Logic/AuctionatorPrices.lua` reads
`Auctionator.API.v1.GetAuctionPriceByItemID("Blackthornes_TS", itemID)`
the same way, one price for market, min and lowest. Its price is the
player's own scans, so it has Forever prices (other Forever addons read the
same call). "Auctionator prices" (`auctionatorPrices`, on unless unticked,
never rename it). Tested in `tools/test_auctionatorprices.lua`.

Farmer shares its own counts the same way (2026-10-11): its `Core/Comm.lua`
and `Core/Serialize.lua` are copies of ours (prefix `BFRshare` instead of
`BTSshare`, no test command, listening only while sharing is on), and it has
its own pairing (`shareNames`) rather than reading `linkNames`. A fix to
`Core/Comm.lua` or `Core/Serialize.lua` here belongs in Farmer's too.

## German translation

The owner said yes (2026-10-12) to German in Tradeskills, after Pets'
pilot and Farmer. Players are told the language as "Deutsch"; the code
names stay `deDE` and `Locale/deDE.lua`.

- **English is the key and the fallback.** `Locale/Locale.lua` (in the TOC
  before `Core/Init.lua`, Pets' file) makes `ns.L`, whose missing keys
  answer the key itself; `L.Format(key, ...)` is `string.format` on the
  translation and puts values named by place (`%2$s ... %1$d`) in order.
  The tests load single files with a stub `ns`, so every file that shows
  text opens with `local L = ns.L or setmetatable({ Format =
  string.format }, { __index = function(_, key) return key end })`.
- **Adding a string:** `L["English text"]` or `L.Format("English %s",
  value)`, a literal where it is written, one whole sentence a key (never
  pieces joined with `..`), both forms for a plural; add its line to
  `Locale/deDE.lua` (informal "du" and the game's words: Auktionshaus,
  Händler, Entzaubern, Herstellen, Liste for the queue, Gewinn, Stufe) and
  run `python tools/check_locale.py` (warns only; keep it at 0 missing).
  `tools/test_locale.lua` loads the locale as a German client.
- **Text compared with text:** a caller that checks a wrapped string (an
  age's "just now", a reason like "need materials") compares it with the
  same `L[...]`, never the English.
- **Left in English on purpose:** slash command words, saved and internal
  keys, mail subjects, anything matched against the client (chat
  patterns, tooltip lines, spell and profession names), data names
  (items, crates and writs, Forever's own items such as Merchant's Favor,
  whose German names nobody has seen), debug and verbose scan lines, and
  the checks players run for a report (`/bts probe`, `perf`, `openprof`,
  `mail`, `disenchant`, `value` and the like; their help lines are
  translated).
- German runs about 30% longer: fixed-width buttons got short German
  ("Los" for Craft, "Kauf" for Buy) or grow to fit; a new fixed width must
  wrap or grow, never end in "...". The Columns menu lowers capital
  umlauts itself, since Lua's `lower()` does not.

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

List rows are dark glass (the owner picked it 2026-10-10 over a gold glow
that lit every row): `glass`/`glassAlt` bands in the well with a fine line
under each, `glassHover` and the gold wash only under the mouse,
`glassActive` for the picked row. A gradient that fades goes through
`Theme.LightGradient`, which hides it at 0; faded with SetAlpha alone it
stayed lit on Forever. Equipment's gear window and finder have the same.

## The Blizzard window style

The owner asked (2026-10-10) for a choice of the game's own look beside
Titanforged, in all four addons. "Window style" in Settings (`windowStyle`,
`titanforged` or `blizzard`, Titanforged by default; read once at login,
so a change waits for /reload, as Text size does). `UI/BlizzardLook.lua`
is the same file in all four (a fix to it belongs in all four): picked, it
lays the game's colours over `Theme.colors` (grey metal, the game's gold,
plain rows with a blue bar for the one picked) and puts out the halos;
`Titanforged:Dress` hands the window to `BlizzardLook.Dress` (silver rim,
a title tab where the plate sits, a silver-ringed portrait and the game's
`UIPanelCloseButton`, with the same trim fields); and the widgets call
`BlizzardLook.Button`, `.Checkbox`, `.Tab`/`.SelectTab` (hanging tabs) and
`.Thumb` (via `Widgets.LightThumb`) to wear the game's own texture files.
It never touches a Blizzard frame. Each file is checked once
(`BlizzardLook.HasArt`); a client without one keeps that widget in the
house look, and `/bts probe` lists what is missing. Not yet seen in game.
New widgets should look right in both styles.

## Reading the probe

The owner asked (2026-10-10) for check results without screenshots, in all
four addons. `ns.KeepCheck(name, fn)` in `Core/Init.lua` runs a check that
prints to chat, keeps every line it prints (colours and links taken out, a
secret value kept as "(secret)") and saves them in the account save as
`lastProbe = { check, at, version, lines }`, replacing the last one; chat
adds "Saved for Claude, /reload to write it." It wraps `/bts probe`
(Tradeskills, saved under `BlackthornesTSDB.global`), `/beq probe` and
`/beq arrow check` (Equipment), `/bpet probe` and `/bpet arrow check`
(Pets), and `/farm arrow check` and `/farm gathering check` (Farmer, which
has no probe). Each has a Settings button. Never rename `lastProbe`; a new
check that players run for a report goes through `ns.KeepCheck` too, and a
fix to it belongs in all four.

When the owner says "read the probe": he has run the check and typed
`/reload` (or logged out). In the thread, connect to his device, ask for
his game's WTF folder (already approved; the path is in the project's
memory) and stage the addon's account save from
`WTF\Account\<account>\SavedVariables\` (`Blackthornes_TS.lua`,
`Blackthornes_Farmer.lua`, `Blackthornes_Equipment.lua` or
`Blackthornes_Pets.lua`), read only. Read its `lastProbe`: `check` says
which one ran and `at` when; one older than his message means the save was
not written yet, so ask him to `/reload`. Use only the probe lines; never
commit the save or copy anything else out of it.

## Discord

The addons share a Discord server, Blackthornes AddOns (public invite
https://discord.gg/f2geDecrw2, set up 2026-10-05). After a release uploads,
`release.yml` runs `tools/announce_discord.py`, which posts the version's
CHANGELOG section to the server's #announcements through a channel webhook
kept in the `DISCORD_WEBHOOK_URL` repository secret. The owner sets that secret
himself; never ask him to paste the webhook address anywhere. Without it the
step does nothing, and a failed post never undoes the upload. The tool is the
same in all four repos; a fix to it belongs in all four.

The owner asked (2026-10-09) for one post in #general per release too,
and (2026-10-10) for it to be short: a few bullets in plain words, a
sixth-grade reading level, warm, in his voice (short, contractions, no
jargon, no file or setting names, never his name), saying what players will
notice. Each release PR writes the new version's section in `NEWS.md`
(`## X.Y.Z`, like CHANGELOG.md; it never ships) next to the CHANGELOG
section: the bullets, then one line of thanks. After the upload
`tools/post_general.py` scans it with `check_package.py`'s PRIVATE list and
posts it through the `DISCORD_GENERAL_WEBHOOK_URL` secret, which the owner
sets himself, under a line with the addon's name and version (so each
addon's bullets are their own group) and "(full list of changes in
#announcements)", so the thanks comes last. It carries no CurseForge link and no card (link previews
are turned off). No section or no secret means no post.
A player's name never goes in a report (the owner, 2026-10-09): no
CHANGELOG, #announcements post, commit or PR text names a player, and
`check_release.py` refuses a CHANGELOG section that credits one
(`names_a_player` in `post_general.py`). The #general post is the one
exception: its last line thanks, by their Discord name, everyone who asked
for or reported the changes, each name once ("Thanks Ana and Bob for the
ideas and reports!"); leave it out when nobody asked. Find who asked from
the project's threads. This tool is also the same in all four repos.
Changes to the Discord bots, the digest or the release posting tools
(like this one) never go in a CHANGELOG, #announcements or #general
section (the owner, 2026-10-10): they are not changes to the addon.

The language is "Deutsch" in every post (the owner, 2026-10-11): a
CHANGELOG.md or NEWS.md section about the German translation or German
clients says "Deutsch", or "Deutsch (German)" where English readers need
the hint, never "German" alone. `tools/check_release.py` warns (it does
not refuse) when this version's CHANGELOG.md or NEWS.md section says
German without Deutsch. This rule is in every addon's notes; keep them
the same.

## What's New

The owner asked (2026-10-12) for the Discord #general post to show in game,
the first time it loads after an update, in one window for every addon.
`UI/WhatsNew.lua` is the same file in all five (a fix to it belongs in all
five), and so are `tools/test_whatsnew.lua`, `tools/make_whatsnew.py` and
`tools/test_make_whatsnew.py`. There is no shared core addon: every copy
signs up in `_G.BlackthornesWhatsNew` as it loads, the first to reach
PLAYER_LOGIN starts the only timer (`WhatsNew.DELAY`, 5 s, never in a
fight), and that one check gathers what is new in all of them. The copy
with the highest `FILE_VERSION` draws the window (first in
`WhatsNew.ADDONS` on a tie); raise it when a change needs the newer copy.

The words are NEWS.md's: it never ships, so `tools/make_whatsnew.py` writes
its newest three sections, bullets only (the thanks line names players and
never ships), into `Core/WhatsNewText.lua` (`ns.WHATS_NEW`; never edit it by
hand). **Every release PR that writes a NEWS.md section runs
`python tools/make_whatsnew.py` too**; `check_release.py` refuses a tag
while the file is behind, and `tools/test_make_whatsnew.py` fails on every
push. The bullets stay in English, also on a German client.

Shown once a version: each addon keeps the newest version shown in its own
account save (`whatsNewSeen`); after an update the sections newer than that
(at most three) show, and an addon that never kept one shows its newest.
"After an update" (`whatsNewPopup`) and "What's New motion"
(`whatsNewMotion`) are on unless unticked, off in all when off in any;
`whatsNewScale` is the size grip's, where the addon has one. Never rename
them. The `whatsnew` command and a Settings button open it any time, with
each addon's newest. It rises in, its divider draws out, each addon's card
slides up with its icon popping and a light crossing it, and the Got it
button glows (one looping animation the game plays, only while it shows);
Motion off lands it all at once. Not yet seen in game.

## The sister note

The owner asked (2026-10-11) for the addons to say, once, which of the
others a player does not have. `Core/SisterNote.lua` is the same file in
all five (a fix to it belongs in all five), and so is
`tools/test_sisternote.lua`. Every copy signs up in `_G.BlackthornesSisterNote`
as it loads; the first to reach PLAYER_LOGIN starts the only timer
(`SisterNote.DELAY`, 8 s, no ticker), and that one check prints one line for
all of them: the sisters not installed (`C_AddOns.DoesAddOnExist`, else
`GetAddOnInfo`'s "MISSING"), each with what it adds. One installed but
turned off is never named. Once per account: what it named is kept in every
loaded addon's account save as `sisterNoteTold[folder] = true`, so only a
sister never named before (one released later) brings it back. "Sister
addons" in Settings (`sisterNote`, on unless unticked) and the `sisters`
command on each addon: off in any is off in all, and changing it writes all.
Never rename `sisterNote` or `sisterNoteTold`. A new addon goes in
`SisterNote.ADDONS` in all the copies. It names only our own addons.

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

## The owner's standing rules (both addons)

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
