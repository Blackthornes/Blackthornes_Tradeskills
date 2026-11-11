# Claude notes: features and history

Moved verbatim from CLAUDE.md (every feature's history and detail, plus the shared house-kit, Discord, What's New and similar notes). Grep a heading, then read about 150 lines at a time.

## Random suffix prices

A player asked (2026-10-15, the owner said build it): gear "of the Monkey"
and "of the Spirit" share one item ID, and its one price mixed every
suffix. Each suffix seen at the auction house now keeps a price of its own
beside the item's, in the item's price record as `record.suffixes[suffix]
= { market, min, rival, quantity, seen }` (never rename it; at most
`Prices.SUFFIX_MOST`, the oldest seen going first; used for
`Prices.SUFFIX_KEEP`). The item's own price is unchanged. Read from full
scans (`C_AuctionHouse.GetReplicateItemLink`, asked only for green or better
weapons and armour, `Scanner.MayHaveSuffix`), browse rows (the key's
`itemSuffix`) and item searches (each listing's `itemLink`).
`Prices:GetLinkValue(link, which)` is a copy's price: its suffix's, else
`GetValue`'s, with the player's own price still winning. The tooltip adds
"This one" for a copy whose suffix has a price, and Butler's `Advise` takes
the bag link. `GetValue(itemID)` is unchanged, so Farmer and Equipment read
as before. The screens that follow a copy's suffix (the owner, 2026-10-15:
"people want Tradeskills to respect suffixes on greens"): Post's suggested
price, worth and confirm box (`Posting:ListedCopy`, the bag copy's link,
kept until `Inventory.changes` moves; `Profit:ChoosePostPrice` takes it),
Your auctions' undercut (`MyAuctions:Judge` by the auction's link), the
Disenchanting tab's bag rows, and a "Random suffixes" row on the Prices
tab (`Prices:SuffixRows`, each on hover). For a suffixed copy whose item has
suffix readings, `GetLinkValue(link, "rival")` is that suffix's rival or
nil, never the item's mixed one. Sales, Profit and auction house search
rows stay by item: sales are money received, a craft can't pick its roll,
and the game already lists searches by suffix. Tested in
`tools/test_suffixprices.lua`. Not yet seen in game.

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

## Shuffles

A player asked for a shuffle calculator, and the owner said build it
(2026-10-25, from a mockup whose words he approved). The Profit tab's
switch reads MY CRAFTS, YOUR TIME, RECIPES TO LEARN, SHUFFLES (an extra
with `last = true` goes after the learn view in `RecipeBookView.WithSwitch`).
Pick something in the bags ("Start With:", only items some recipe uses) and
"How Many:", and every way to turn it into gold is listed, best gain first:
sell it as it is, or craft it up to `Shuffle.DEPTH` (3) crafts deep and
sell, vendor or disenchant the result. `Logic/Shuffle.lua` works it out a
few steps a frame (`BUDGET`), at most `MAX_NODES` looked at and `MAX_WAYS`
shown, kept `KEEP` seconds, nothing saved. Prices are the usual order:
`Prices:GetValue` (own scans, guild, realm, TSM, Auctionator), auction net
of the cut through `Profit:NetFromListing`, a grey vendor only
(`Util.GetVendorSellPrice`), a disenchant at `Disenchant:GetValue` with the
odds the player's own breaks gave. Other materials a craft needs are bought
(`Cost:GetReagentCost`); a craft with a material nobody prices is left out.
Each step says what stopping there is worth, the best one "Best place to
stop", one worth less than the step before "This step loses gold. Sell
before it." "Only My Recipes" (on, session only) leaves out recipes not
known. Queue It (`Queue:Ensure`, only when every craft is known) and Add to
List (a shopping list named for the start, never doubling a count).
`UI/ShuffleView.lua` draws it (columns `shuffles`). Tested in
`tools/test_shuffle.lua` and `tools/test_shuffleview.lua`. Not yet seen in
game.

## Parts an alt makes, in the profit math

A player asked, the owner said yes (2026-10-24): a part only another of
your characters can make was priced at what buying it costs. With "Alts
Make Sub-Crafts:" ticked (`queueAltCrafting`, the switch that already
hands sub-crafts to alts in `Queue:DeriveAcrossCharacters`),
`Cost:GetCraftCost` prices such a part at the alt's materials plus postage
(`Queue.PostagePerUnit`) when that beats buying, marks it `crafted` with
`madeBy` (the alt's key, `Cost:AltRecipeFor`, `BuildAltIndex`), and the
material lines on the Profit and Level Up tabs and `/bts why` say "made by
NAME" (`Cost.MadeByName`, the whole name). Left at the buying price: a
cooldown craft (`Cooldowns:HasCooldown`: Classic's `KNOWN`, or one any
character was seen waiting on), one in `neverSubCrafts`, a dropped
profession's, an alt this character can't mail, and anything bound when
picked up. The character's own recipe always comes first. Nothing saved.
Tested in `tools/test_altpartcost.lua`.

## Craft next frees bag space first

A player asked (2026-10-14, the owner agreeing) for the queue to craft
what frees the most bag slots first. Only Craft next's pick changes, on the
Queue tab and in the profession window (`Crafting:PickNext`, called by
`GetNextReady` and `CraftPanel:GetNextReadyHere`): of the ready crafts,
the one whose materials stop taking the most stacks, less the new stacks
what it makes takes (`Crafting:SlotsFreed`, from the bags' counts and
`BagsFull.MaxStack`, kept until `Inventory.changes` or `Queue.version`
moves). Ties keep queue order, and a craft waits while a ready sub-craft
of its own (up its `forRecipes` chain) is ready. Bag space only picks within the
first profession group with something ready (below), and the crafts the
player queued come after every sub-craft.

Bars all at once (a player's report, 2026-10-19: forge, anvil, forge):
`Queue:RebuildDependencies` keeps one sub-craft per recipe and crafter
(`MergeSubCrafts`, at the deeper level, `forRecipes` joined), counts what
is held once across levels (`HeldPool`), and lays the sub-crafts out a
profession at a time, the one feeding another first, deepest first within
it (`OrderSubCrafts`, `Queue:ProfessionOf`). Nothing saved changes shape;
sub-crafts are rebuilt as before. Butler's Jobs keeps this order for its
parts. Tested in `tools/test_stationorder.lua`. The stored queue never
moves. The button's tooltip says how many slots it frees. "Craft what frees
bag space first" on the Queue page (`craftFreesSpaceFirst`, on unless
unticked, never rename it). Tested in `tools/test_freespacefirst.lua`.

## Keep in stock by profession

A player asked (2026-10-13, the owner agreeing) for Keep in stock per
profession, and the owner for per item too. `Auctions:GetLimit(itemID)`
answers in three steps and says which: the item's own number
(`postLimits`, set in the Profit tab's detail pane, an x puts it back),
else its profession's (`professionStockLimits[English name]`, account wide,
never rename it; `Auctions:ProfessionOf` from every character's saved
recipes, laid out again when a `recipesCachedAt` moves), else
`maxPostedPerItem`. A profession's 0 is no limit; an empty box is the usual
number. Settings > Queue has a KEEP IN STOCK BY PROFESSION list
(`Auctions:StockProfessions`, `Widgets.CreateNumberBox` with `allowEmpty`);
the Profit tab greys an inherited number and says where it comes from. The
export code carries them as `P<name>:<n>` in its limits section. Tested in
`tools/test_professionstock.lua`. Not yet seen in game.

## Raise Keep in stock when a craft sells out

The owner asked (2026-10-13): when every copy of a craft listed sells
before its listings run out, Keep in stock for that item goes up by 1.
`Logic/SellOut.lua`: a confirmed listing (`Posting:ResolvePending` calls
`SellOut:NotePosted`) opens or joins a window per character and item,
ending when its longest listing would; the poster's next full mailbox
read after that (`Mail:Read` calls `SellOut:MailRead`) settles it: anything
back expired or cancelled since it opened, nothing changes; nothing back
and a sale seen (ledger or heard), `Auctions:SetLimit(item, limit + 1)`,
once a window, with a gold chat line and a sound; no sale seen yet, it
waits. An item with no limit is left alone. Back down (the owner,
2026-10-16, part of the same tick box): every window that comes back
unsold counts (`sellOutUnsold[itemID]`, never rename it), and after
`SellOut.UNSOLD_ROUNDS` (3) in a row the number comes down by 1, never
below where it started (`sellOutRaised[itemID].base`, `own` when that
was the item's own number), and only while it is still the number this
set; a sell out starts the count again. Settings > Queue lists what it
changed under CHANGED WHEN SOLD OUT (`SellOut:Changed`), each with Reset
(`SellOut:Reset`: the item's own number back, or the usual one). "Raise it
when it sells out" on the Queue page (`raiseStockOnSellOut`, off unless
ticked, the owner 2026-10-13). Saved, never renamed: `sellOutWatch[realm][character][itemID]`,
`sellOutRaised[itemID]` (the Profit tab's tooltip on the number) and
`sellOutUnsold[itemID]`.
Tested in `tools/test_sellout.lua`. Not yet seen in game.

## Your auctions and undercuts

A player asked (2026-10-14, the owner said build it, from a mockup) for an
Auctions switch in the auction house drawer beside Sell and Buy:
`UI/AuctionsView.lua` draws it inside `UI/PostPanel.lua`, and
`Logic/MyAuctions.lua` works it out. It lists the auctions you have up
(`Auctions.live`, kept for the session by `Auctions:ReadOwned` with each
auction's ID; nothing new is saved), then other characters' as last read
(`Auctions:GetListings`, dimmed, never cancellable here). Undercut means
your price for one is above the cheapest listing not yours
(`Prices:GetScanValue(id, "rival")`) from a scan no older than
`MyAuctions.FRESH` (an hour); older says Unknown. Undercut ones come first
with a red edge and a Cancel button; the switch shows their count in red.
`MyAuctions:Cancel` calls `C_AuctionHouse.CancelAuction` straight from a
click, one auction a click (the game wants a click each; never queue or
loop it), refuses at a busy or closed auction house, and is read back:
gone means cancelled ("comes back in the mail"), still up after
`CANCEL_WAIT` means it did not go through. Each row says about what
listing it again costs (`GetCancelCost`, else the remembered deposit) and
warns when that is more than the gap. Cancel next at the foot takes the
one with the most money under. `/bts probe` has a "cancel auctions" line.
Tested in `tools/test_myauctions.lua`. Not yet seen in game.

Places in line (a player asked, the owner said build it from a mockup,
2026-10-20): "Cheapest" says nothing about auctions at your price listed
before yours, which sell first. Every item or commodity search that comes
back for an item you have up (the addon's, the player's own, or **Check
Places** at the foot, `MyAuctions:CheckPlaces`, one item and suffix at a
time at background priority, through each live auction's `itemKey`) is read
once more (`MyAuctions:NoteItemPlaces`, `NoteCommodityPlaces`, called first
in the Scanner's two search handlers): an item auction keeps how many
others at its price and suffix come before it (`MyAuctions.places`), a
commodity how many of others' units share its price (`MyAuctions.more`).
Session only, nothing saved, shown while under `FRESH`. A cheapest row then
ends its line with amber "34 ahead of you", green "First in line" or amber
"480 more at your price"; with others ahead (`row.behind`) it sorts first
among the cheapest, its "Cheapest" is amber and it gets Cancel. Cancel next
stays undercut only. Tested in `tools/test_auctionplaces.lua`. Not yet
seen in game.

## Can afford

A player asked, the owner said build it (2026-10-22): the Level Up tab
says when a craft's missing materials cost more than the gold on hand,
and can leave those out. `LevelUp.ToBuy(costDetail)` adds each reagent's
`shortfall` (bags and bank count as owned) times its `unitCost`; each row
carries it as `toBuy`. `LevelUp:ShortNote(row)` gives "You need about X
to buy what's missing. You have Y." in red on the row's hover and the
detail panel. "Can afford" in the toolbar (`levelUpCanAfford`, account
wide, off unless ticked, never rename it) passes `canAfford` to
`GetRanked`, which drops rows the purse (`GetMoney`) can't cover; Learn
Next and Road to 300 are unchanged. `PLAYER_MONEY` redraws the shown
list 0.3 s later. Butler's Cheapest Skill-Up follows the same box. Tested
in `tools/test_canafford.lua`.

## Legacy perks, read only

The owner said build it (2026-10-22): Forever's Legacy is a C_Traits
config (the spell "Legacy System - Create Trait Config"), and Tradeskills
reads what the player spent, never more. `Logic/Legacy.lua` finds the
config a slice a frame, 10 s after login and again after a trait event
(trait system IDs, then tree IDs; class talents never count; a config
named Legacy or holding a node in `NODE_RANGES`: 110284 to 110319 and
113506 to 113513, trees 1187 to 1189 in the Forever client's game tables,
2026-10-28), and reads each node's rank through
`C_Traits.GetNodeInfo`, every call in a pcall. It never buys a rank,
commits a config or suggests a build (the owner: "we just read what they
have set"). Master Chef (found by its English name, or
`MASTER_CHEF_NODE` once a probe shows its ID) raises a cooking recipe's
yield in `Cost:GetCraftCost` by up to `MASTER_CHEF_MOST` (50% at its last
rank), only for a recipe the character playing knows, so the Profit tab
follows it. Bartering needs nothing: vendor prices come from the real
merchant window. Nothing read, nothing changes. Nothing is saved and no
player words are new. `/bts probe` has "legacy" lines (the config, points
left, each node's rank, Master Chef's yield, currencies 3485 and 3499).
Since 2026-11-10 it also lists each perk's own words, read without
points: "legacy perk <node>" (name, spell, entry, rank), its tooltip at
rank 1, 2 and the last rank (`Legacy:PerkLines`, `RankText` through
`C_TooltipInfo.GetTraitEntry`) and its spell's text (`SpellText`); any of
the 21 perks in `PERK_SPELLS` no node showed is read by spell ID
("legacy spell <id>"). Typed only, never shown to players.
Tested in `tools/test_legacy.lua`. Not yet seen in game.

Perks in the numbers (the owner said build it, 2026-11-10, after the
probe): only ranks the player spent count; none spent, every number is as
before. `Legacy.PERKS` names each perk by spell ID (Master Chef 1225457,
Working Overtime 1225451, Performance Bonus 1225456), the node the probe
showed (110289, 110290, 110292) and the English name, and
`Legacy:PerkNode(key)` finds it in that order, so every language works.
`Legacy:Rank(key)` gives the spent rank and the most, kept until a trait
event (`Legacy:Forget`). Working Overtime is `SkillUpBonus()` (4% a rank,
20% at 5), added in `RoadPlan.Chance` between yellow and grey only
(`RoadPlan.Overtime`, capped at 1; orange stays sure and grey stays 0).
Performance Bonus is `FavorBonus()` (5% a rank of double favor, 15% at
3): `MerchantsFavor:GetRows` keeps `favor` as shown and adds `expected =
favor * (1 + bonus)`, which cost per favor and `GetPlan`'s crates use.
Master Chef's yield now reads `Rank` too. `/bts probe` adds "legacy skill
up" and "legacy favor". No new player words. Tested in
`tools/test_legacy.lua`, `tools/test_roadto300.lua` and
`tools/test_merchantsfavor.lua`.

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

## Show the way across zones and the sea

The owner said build it (2026-10-21, from a mockup) in every addon: with
"Guide Me:" ticked on the Look page (`arrowRoute`, account wide, on
unless unticked, never rename it), the arrow below leads to a trainer or
vendor in another zone or across the sea step by step (flights this
character knows, the boats and zeppelins of its side, its Hearthstone,
walks through the zones between). Without the arrow (no map for the
place) Learn next's Show the way lists the steps in chat and pins the
first stop (`LearnNext.Guide`, `Travel:Guide`). `Logic/Travel.lua`,
`Data/Travel.lua`, `Data/TravelZones.lua`, `UI/TravelCard.lua`,
`UI/TravelMap.lua`, `Media/Frame/TravelDot.tga` and the two
`tools/make_travel*.py` are Farmer's, the same in every addon (a fix to
one belongs in all; Farmer's `CLAUDE.md` has the details). It reads the
flights, crossings and Hearthstone spot the other addons saved. Tested in
`tools/test_learnnext.lua`. Not yet seen in game.

## The arrow

The owner asked (2026-10-22) for Tradeskills and Butler to guide as the
other addons do: the arrow when they point at an NPC or a place, and the
same TomTom choice. `Logic/WayArrow.lua` and `UI/WayArrow.lua` are the
house dial (Farmer's `Logic/Arrow.lua` and `UI/Arrow.lua`, by way of
Butler's copy; `tools/make_arrow_art.py` draws the same `Media/Arrow/*.tga`),
with `ns.TravelHost` at the end of `Logic/WayArrow.lua`. `WayArrow:AimAt
(place, title)` (place `{ zone or mapID, x, y }`, 0 to 100; false when no
map is found) is called first by Learn next's Show the way
(`LearnNext:ShowTheWay`) and a vendor pin's click (`VendorPins:ShowTheWay`),
which print "The arrow shows the way to NAME (WHAT)."; the old pin is the
fallback. The arrow shows only while a place is set
(`charDb.wayArrowPlace`, per character; its spot `wayArrowX`/`wayArrowY`,
account wide), and goes with its close gem or when a trainer or vendor
window opens on arrival (`WayArrow:Reached`). The dial takes no clicks and shows no hover text (the owner,
2026-10-23): drag moves it and the red gem closes it. It joins the one-arrow rule
(`_G.BlackthornesArrows`, as "Tradeskills"). `Logic/TomTom.lua` is the
shared TomTom file: "Use TomTom:" on the Look page (`useTomTom`, account
wide, on unless unticked, never rename it) hands TomTom the place
instead. Never rename `wayArrowPlace`, `wayArrowX` or `wayArrowY`. Tested
in `tools/test_learnnext.lua`. Not yet seen in game.

Our own map marker (a German player found nothing at the Crossroads; the
owner said do all six fixes, 2026-10-29, in every addon): Forever turns
the game's map pin down, so Show the way (`LearnNext:ShowTheWay`,
`VendorPins:ShowTheWay`) always lays our own gold marker on the place
(`Waypoints:Mark`, `UI/SpotMarker.lua`, the same file in Pets,
Tradeskills, Butler and Farmer; Equipment's `MapPins:Spotlight` is the
same look, a fix to one belongs in all): a gold ring with the name under
it, two waves for `WAVE_FOR` seconds then a breathing glow (Effects
Subtle a still glow, Off still). With the game's pin it goes with the
pin; without one it goes when you stand within `WayArrow.ARRIVED` of it.
"Can't pin" is said only when no marker could be laid either.
`Waypoints.ZONE_MAPS` has Forever's own zones (Mount Hyjal, Zephras
Isle, Riverglades, Shen'dralas), the same in Equipment and Pets. Tested
in `tools/test_spotmarker.lua`, `tools/test_learnnext.lua` and
`tools/test_vendorpins.lua`. Not yet seen in game.

Arrow Size (the owner, 2026-10-26, in every addon with an arrow): "Arrow
Size:" under "Guide Me:" picks 50%, 75% or 100% for the whole dial,
plate and words (`ArrowUI.SIZES`, `Scale`, `Size`, `SetSize`;
`wayArrowSize`, account wide, nil for 100, never rename it). The saved
spot is kept in the screen's own units (stored times the scale), so a new
size keeps the arrow where it was. No hover. Tested in
`tools/test_arrowsize.lua`. A fix belongs in all five.

## Road to 300

The owner said build it (2026-10-20, from a mockup whose words he
approved): the Level Up tab's switch reads Next Point (the tab's own
list), Road to 300 and Learn Next (the recipes to learn;
`RecipeBookView.WithSwitch` takes `learnText`). `Logic/RoadPlan.lua` lays
out the whole way to 300 for one profession: from the skill now, each
stretch takes the recipe cheapest a point, known or taught by a trainer
or vendor of the player's side (`RoadPlan:Candidates`, `LearnNext:Place`);
a step is one recipe in one colour, "every craft" while orange, "most
crafts" while yellow, its crafts 1 over the chance (`RoadPlan.Chance`: 1
below yellow, (grey - skill) / (grey - yellow) up to grey). Trainer steps
sit at Classic's ranks (`RoadPlan.RANKS`: Journeyman at 50 to 150 and
level 10, Expert at 125 to 225 and level 20, Artisan at 200 to 300 and
level 35), with "You're level N." while the level is short
(`LearnNext:TrainerFor` names the nearest trainer). What the bags, then
the bank, then the other characters this one can mail hold (their saved
bags, bank and, unless `countMailAsStock` is off, mail; each once by
`Characters:Same`, never the one playing or `linkedFrom`;
`RoadPlan.AltsHold`, 2026-10-31) comes off once across the steps, a
step they cover saying "You have enough for this step.", and the footer says how
much ("To 300:", "What you own already takes off X."). Steps below the
skill are done and sit at the foot of the list (`RoadPlan.Shown`; "Step N
of M", the meter and Queue All keep the plan's order). Queue Step queues a known recipe's crafts
(`Queue:Ensure`) or puts a recipe still to learn's materials on the list
to buy (`Queue:EnsureBuy`); Queue All does every step left; Show the Way
is `LearnNext:ShowTheWay`. A recipe still to buy says "You don't know this
recipe yet. Buy it from a vendor in ZONE." (the trainer's wording stays).
Its Queue Step lines keep how many crafts they were for (`forCrafts` on
the `queueBuys` line, never rename it), and once the character learns the
recipe (`Recipes:Harvest` adds it) `Queue:QueueLearned` queues those crafts
and takes the lines off, so nothing is bought twice; Learn next's lines,
which carry no crafts, are left alone (the owner said yes 2026-10-26). `UI/RoadView.lua` draws it (a profession
picker, the heading with the skill, "Step N of M" and a meter, dark glass
rows, the step to do now `glassActive`). The plan is worked out only
while the view shows, its prices a few recipes a frame
(`RoadPlan.BUDGET`), and kept until its key moves (skill, cap, level,
recipes, `Inventory.changes`, `Prices.scanCount`, `Queue.version`).
Nothing new is saved beyond Pick By. Cooking and First Aid go to 300
(the owner said build it, 2026-11-08, from a mockup whose words he
approved): Expert comes from a book (`how = { kind = "book", item, title,
sellers = { A, H } }`) and Artisan from a quest chain (`how = { kind =
"quest", chain = { A = {...}, H = {...} } }`, the last quest's giver
teaches), on their `RoadPlan.RANKS` rows from the Forever client's game
tables. `RoadPlan.HowNow` picks the player's side, walks the chain past
quests done (`C_QuestLog.IsQuestFlaggedCompleted`), names them by the
game's title and lays a seen spot (`VendorPins:SeenAt`) over the data's;
Show the Way follows it. The step says "Learn Expert NAME" or "Learn
Artisan NAME", "Buy BOOK from NAME in ZONE.", "Start with the quest QUEST
from NAME in ZONE." then "It leads to NAME in ZONE, who teaches you.", and
on the last quest "Do the quest QUEST for NAME in ZONE. Then they teach
you."; the Artisan step shows no price. Tested in
`tools/test_roadto300.lua`. "Pick By:" on the road's bar (the owner said build it, 2026-10-27, from a
mockup whose words he approved) picks Lowest Cost (the default, as before)
or Real Cost: each stretch's recipe is then chosen by what it costs less
what selling a craft brings back (`LevelUp:GetReturns`' best, kept on
`price.back`), and the footer adds "Selling what you make brings back
about X." (`plan.back`, `RoadView.FootText`). "To 300:" still counts the
gold spent. `roadPickBy` ("lowest" or "real", account wide, never rename
it; `RoadPlan.PickBy`) is part of the plan's key.
Tested in `tools/test_roadto300.lua`. Not yet seen in game.
By real cost a craft never counts for less than `RoadPlan.REAL_FLOOR`
(a fifth) of its materials (2026-11-11, a player's report: a craft that
sold for more than it cost had a cost below 0, which looked cheaper a
point the lower its chance fell, so the road stayed on it to grey, 144
yellow crafts for 20 points). The step's own gold figure is unchanged.
The drop-down lists them (the owner found only Enchanting and Tailoring,
2026-11-08): `RoadPlan:Professions` takes a line `ClassicLine` does not
know by its English name (`Recipes.EnglishProfessionName`, so a second
Forever ID for Cooking or First Aid still lands on 185 or 129), and adds
learned ones from the Professions book (`GetProfessions`,
`GetProfessionInfo`, in a pcall) when the trade skill lines leave them out.


Cooking and First Aid (a player's report via the owner, 2026-11-08: the
road was all Basic Campfire and stopped at 75): a Classic recipe that
Forever remade under the same name in the same line (Basic Campfire,
grey at 5 on Forever) is left out of `RoadPlan:Candidates`, and
`RoadPlan.Price` values a material nobody lists or sells (raw meat,
clams) at what a vendor pays for it (`RoadPlan.SellValue`,
`Util.GetVendorSellPrice`); only a material with neither leaves the
recipe off the road. Tested in `tools/test_roadto300.lua`.
## Welcome card

The owner said build it (2026-10-20, from the same mockup): the first
time the window opens on a character, a card ("Welcome", the house frame)
asks which of its professions to level, each ticked with its skill. Show
My Road keeps the ticked ones and opens Road to 300 on the first
(`LevelUpTab.ShowRoad`); Not Now closes it. Either way it never comes back
by itself (`Welcome:Due`, asked from `UI:Show`); "Road to 300:" on the
Look page of Settings opens it again (`WelcomeUI:Show`). It changes no
setting: the picks only put those roads first in the picker
(`RoadPlan:Professions`). `Logic/Welcome.lua` keeps, per character in
`BlackthornesTSCharDB`, `welcomeSeen` and `roadPicks` (Classic skill
lines in order); never rename either. `UI/Welcome.lua` draws it. Tested
in `tools/test_welcome.lua`. Not yet seen in game.

## Vendor map pins

A player asked (2026-10-18, the owner said build it, from a mockup with
the words he approved): gold pins on the world map at vendors that sell a
material the queue still needs for less than the auction house, or that
nobody lists there. Only the world map, for the map it shows; only
vendors of the player's side or of neither; gone once there are enough
(the shopping list's shortfall). Not for an item set to Buy on the Level
Up tab. `Logic/VendorPins.lua` picks them (`Wanted`, `For(mapID)`),
`UI/VendorPins.lua` draws them on the map's canvas (a key, redrawn only
when the map, zoom, queue, bags, a scan or a learned vendor moved). The
hover names the vendor, "Has what your queue needs:", each item with how
many and the cost, "Saves you X over the auction house." and "Click to set
a map pin." (or "Click for a TomTom arrow."); a click is
`Waypoints:Pin`/`TomTom`, which now take a `mapID` in place of a zone.
The look (the owner said build it, 2026-10-19, from a mockup): a gold rim
round a bag with a gem on top and a glow that breathes (an animation the
game loops, Window effects Full only), a gold badge with how many queue
items, names under the pins only zoomed in or with `NAMES_MOST` (4) or
fewer, the vendors that save less `SMALL` the size, and a beam under the
one a click pinned (`VendorPins.pinned`); `VendorPinsUI.Looks` works it
out. The hover is our own card (`ShowCard`: gold rim, dark glass rows,
rarity and coin colours), on UIParent, never GameTooltip.
Where vendors stand: `Data/VendorSpots.lua` (`ns.VENDOR_SPOTS`, Classic's
vendors of the items in `Data/VendorPrices.lua` that never run out, by
`tools/make_vendor_spots.py <quest database>`, never by hand), and every
vendor the player opens (`VendorPins:Learn` from `Vendor:Scan`: NPC ID,
map and spot, side, and its materials with whether they run out), kept
account wide in `vendorSpots[npcID]` (never rename it; at most
`MOST_VENDORS`). A learned vendor takes its shipped place; one whose stock
runs out is pinned only while the auction house has none. Butler's Buy
from a vendor row still does the buying. "Vendor Map Pins:" under AT
VENDORS on the Mail & Vendors page (`vendorMapPins`, off unless ticked,
never rename it) and `/bts vendorpins on|off`. Tested in
`tools/test_vendorpins.lua`. Not yet seen in game.

Where the game saw it wins (the owner, 2026-10-22, after a player's Show
the way led to a recipe vendor's Classic spot; his rule for every addon):
a spot seen in game always beats Classic's listed one. `Vendor:Scan`
keeps recipe-only vendors too, and a trainer's window keeps where it
stands (`VendorPins:LearnTrainer` on `TRAINER_SHOW`, account wide in
`trainerSpots[npcID] = { name, mapID, x, y, side, at }`, never rename
it). Between them and Classic sit the shipped Forever spots,
`Data/ForeverVendorSpots.lua` (`ns.FOREVER_VENDOR_SPOTS`,
`ns.FOREVER_TRAINER_SPOTS`), written by `tools/forever_vendor_spots.py
<save>` from only those two tables of the owner's save (never when it was
seen), keeping what is shipped; never by hand, and run at each release
with the other fold-ins, never announced. `VendorPins:SeenAt(name, zone,
kind)` (by name, any case, on the zone's map when known) is what Learn
next's `Place` reads first, so Show the way, the arrow and Equipment's
`WhereFor` follow; `VendorPins:Known` lays the shipped spots under the
player's own for the map pins. Tested in `tools/test_vendorpins.lua`,
`tools/test_learnnext.lua` and `tools/test_forever_vendor_spots.py`.

## Sealed writs

The owner said build it (2026-10-19): mobs drop a Sealed Journeyman's or
Expert's Writ, and tearing it open gives one Craftsman's Writ, so the
addon learns what each opens into. `Writs:NoteOpenings` (from `OnBags`):
a sealed writ (`Writs.IsSealedName`, "Sealed ... Writ") leaving the bags
and a Craftsman's Writ coming in within `MATCH_SECONDS` is one opening,
kept account wide in `merchantsFavor.sealedWrits[sealedID] = { opens,
writs = { [item the writ asks for] = count }, name, at }` (never rename
it). The item tooltip (`ItemTooltip:AddSealedLines`, `Writs:SealedInfo`)
says "You opened N", up to five writs with "3 of 6" and "Writ inside
worth about" once every writ it gave has a price; a writ row's tooltip
on the Writs view says "Came from NAME: 3 of 6" (`Writs:SealedSources`).
Nothing is opened for the player. Tested in `tools/test_writs.lua` and
`tools/test_itemtooltip.lua`. Not yet seen in game.

Coin bags (the owner said build it, 2026-10-24, after a player noticed
each rank's bag shares one item ID): an item that comes into the bags
with a learned turn-in is that level's bag, account wide in
`merchantsFavor.writBags[tier] = { [itemID] = time }`; one leaving the
bags with money coming in within `MATCH_SECONDS`, never at a vendor,
mailbox, auction house or trade, is an opening, kept in
`merchantsFavor.coinBags[itemID] = { opens, copper, at }` (never rename
either). `Writs:BagWorth(tier)`, the average, is added to `GetReward`'s
money, so it comes off a turn-in's cost and shows as Money back. No new
words. Tested in `tools/test_writs.lua`. Not yet seen in game.

## The favor goal

The owner said build it (2026-10-20, from a mockup): a Merchant's Favor
goal on the Favors and Writs tab. "Favor Goal:" takes a number
(`favorGoal`, nil for none, never rename it; `MerchantsFavor.Goal`,
`SetGoal`). `MerchantsFavor:GetPlan` works out the cheapest way there
from the first priced row of `GetRows` (crates and bundles held come off
the gold), `FavorHave` reads the favor (its currency by ID once seen,
`favorCurrency`, else its item, `favorItem`, else the currency list by
name), and `Steps` lays it out a crate and a bundle at a time. The strip
(`UI/DealsFavor.lua`) shows a gold bar with tenth ticks, You Have, Still
to go, Cheapest way and Gold to get there; Add to a List fills a list
named Merchant's Favor (`AddToList`, set, never doubled). `CheckGoal`
chimes each new tenth and cheers the goal with the game's own sounds by
ID; the first look only notes where it stands. A crate's tooltip shows
what it costs and pays (`ItemTooltip:AddCrateLines`, `RowForItem`;
"Crate Costs:" on the Look page, Off, Shift or Always, `tooltipCrateCosts`
on unless unticked and `tooltipCrateShift`, never rename either). While a
goal is set the auction house drawer has a Favors switch
(`UI/FavorsView.lua`, `PostPanel:LayTabs`): the steps, and Buy Next buys
one listing a click (a crate by a search, a bundle by
`StartCommoditiesPurchase`, then Pay with the game's total); a buy is
counted until the bags or bank show it (`FavorsView.bought`). Nothing is
bought without the player's click. Tested in `tools/test_favorgoal.lua`.
Not yet seen in game.

## Recipes Forever added

The owner (2026-10-17): "always add new recipe finds to tradeskills".
`Data/ForeverRecipes.lua` is written by `tools/make_forever_recipes.py
<tables folder> --build <build>` from the Forever client's game tables
(SkillLineAbility, SpellName, SpellEffect, SpellReagents, Item,
ItemEffect, ItemXItemEffect, ItemSparse); never edit it by hand, never
commit the tables or name where they came from. It lays every profession
recipe in Forever's own spell range (`FOREVER_FIRST`, 1,000,000 and up;
below are other Classic seasons' leftovers) that the book lacks into
`ns.RECIPE_BOOK`, in the book's row shape with `f = 1` and `y`/`g` for
yellow and grey, and its recipe items with their vendor price. So they
show among the recipes to learn and on enchant tooltips before anyone
opens a profession window; a window's own recipe still wins. They are
never matched to a Classic recipe by what they make or their name
(`record.forever`). Where to learn most is not known, so Learn next
leaves them out, and Recipes to learn says "New on Forever". **Rerun it
whenever the client tables are pulled again** (the Saturday check), and
after `make_recipe_book.py`. Tested in `tools/test_foreverrecipes.lua`.

## Sales details on the item tooltip

A player asked (2026-10-13, the owner agreeing, from a mockup) for more
under the tooltip's Demand line. `ItemTooltip:AddDemandLines` adds "Sold
a day" (`Prices:GetUnitsSoldPerDay`, listings gone per day from the kept
readings, an estimate and said so), "Listed now" (the last scan's count
and its age), "Last 7 days" (inline bars from `Prices:GetDailySales` and a
trend once four whole days were scanned) and "You sold" (`Demand:Week`,
this week's sales and expiries from the ledger). Each price record keeps
`daily` for it (`Prices.NoteDaily`; never rename it). "Sales Details:" on
the Look page, Shift or Always (`tooltipSalesShift`, true for Shift, off
unless picked, never rename it; see "Off, Shift or Always on tooltips"). Tested in `tools/test_tooltipsales.lua`. Not yet seen in
game; the bars are the game's inline texture escape.

## The Stats tab

The owner asked (2026-10-14, from a mockup) for a tab like Farmer's
Stats tab, one item at a time. `UI/Tab_Stats.lua` (order 9, after
Prices) lists what you craft, star and sell (sold most in 30 days first;
a search finds any priced item by its saved name) and draws the picked
item: four numbers (worth now against a week ago, profit each, sold a
day, you sold this week), the price graph, then cards: cheapest times
by day and hour, where each sale goes, your listings, sales by week
(the best week lit, cheered once a week with a sound, "Best week of
sales", `statsCheer`, on unless unticked), listed at each scan, price by
source, the last 90 days, who else sells it, how fast yours sell and
the last 30 days by method. `Logic/ItemStats.lua` builds it (each part
in a pcall), only while the tab shows and again only when
`ItemStats:Key` moves, a moment after. `Data/StatsLog.lua` keeps what
nothing else did, for tracked items only (`PriceHistory:IsTracked`),
per realm, never renamed: `statsDays` (day, cheapest, sold; 90 days,
from `Prices:Record`), `statsSellers` (how many sell it and the shares,
from `CommitScan` with the full scan's `seller`; never a name),
`statsPosts` and `statsSellTimes` (your postings from `Posting`, timed
when the mail ledger writes the sale) and `statsCheered`. `/bts stats
[item]`, a Settings row on the Look page and a Stats button on the
Prices tab's detail pane open it. The Sold a day tile shows demand as the
market's numbers, not High, Some or Low (a player asked, 2026-10-16):
"18% of stock sells a day" with a bar coloured by `Demand.MarketLevel`, and
a hover (`StatsUI.MarketLines`) with sells a day, up for sale now, time to
sell what's up and your own listings, all from `stats.market`
(`ItemStats` `Market`). Tested in `tools/test_itemstats.lua`.

## Disenchant results on tooltips

A player asked, the owner said build it (2026-10-29): on a character that
disenchants, an item's tooltip lists under "Disenchant value" each thing it
can break into, its count and its chance, most likely first
(`ItemTooltip:AddDisenchantResults`, from `Disenchant:GetOutcomes`: the
built-in table, or your own results once there are enough). Who disenchants
is `ItemTooltip.CanDisenchant`: `Disenchanter:Knows`, else Enchanting on the
playing character's own record, since Forever's spell checks can say no for
one that does. "Disenchant Results on Tooltips:" on the Look page, Off,
Shift or Always, Shift unless picked (`tooltipDisenchantResults`, on;
`tooltipDisenchantShift`, true; Shift key "disenchant"; never rename
them). Tested in `tools/test_disenchantresults.lua`. Not yet seen in game.

## Enchant costs on tooltips

A player asked (2026-10-14, the owner agreeing) for an enchant's material
cost on its tooltip. `UI/EnchantTooltip.lua` hooks spell tooltips
(`TooltipDataProcessor` for Spell and RecipeRankInfo, `OnTooltipSetSpell`,
and ItemRefTooltip's `SetHyperlink` for a linked enchant; the other
setters only when neither hook took). A recipe's ID is its spell ID, so an
Enchanting recipe that makes no item (`EnchantTooltip:RecipeFor`: a known
recipe first, else the book's, read only once `RecipeBook.merged` is built)
gets Materials with its total, each material's cost (`Cost:GetCraftCost`
with `valueOwned`, so the usual price order), You're short (bags and bank)
and Known by. Lines are kept per spell until `Inventory.changes` moves or
`KEEP_FOR` passes. "Enchant costs on tooltips" on the Look page
(`tooltipEnchantCosts`, on unless unticked, never rename it); `/bts tip`
counts them. Tested in `tools/test_enchanttooltip.lua`.

## The one window

The owner approved the mockups and said build it (2026-10-30): one
house-look window with a rail down its left side, a button for each
Blackthornes addon loaded (Farmer, Tradeskills, Equipment, Pets, Butler),
and the picked addon's own tabs beside it; one size, one size grip, one
fold gem, one place. It was built first in the Classic Era copies and
copied here by hand for Forever; nothing here reads or changes the Classic
repos. `UI/SharedWindow.lua` is the same file in all five Forever addons
(a fix to it belongs in all five), and so is `tools/test_sharedwindow.lua`;
like the shared minimap button, every copy signs up in
`_G.BlackthornesWindow`, each addon joins with `SharedWindow:Join` (beside
its `SharedMinimap:Join`), and the copy with the highest `FILE_VERSION`
builds the window. Forever counts its own `FILE_VERSION` from 1. An addon
whose pages have moved in gives `host = { enter(area), leave() }`; until
then its rail button opens its own window, so every addon works as before.
On unless unticked ("One Window:" on the General page; nil reads as on,
and a player who ticked or unticked it keeps that). Saved in every loaded
addon's account save, account wide, never rename them: `oneWindow`,
`oneWindowAt` (the newest wins), `oneWindowPick`, `oneWindowLeft`,
`oneWindowTop`, `oneWindowScale`. Floating pieces (Kills & Loot, arrows,
plaques, the loot feed, the XP bar, Feed buttons, the upgrade quest panel
and the like) stay their own.

Docking: while the game's auction house, mailbox, vendor or trainer window
is open and the one window is up, it sits beside it
(`SharedWindow.PLACES`, `Arrived`, `Dock`, by screen position only, never
in a fight), its rail a row of emblems along the top. Moving it there
saves nothing. When the game's window closes it goes back to its own place
(`Undock`) and to the addon open before (`Left`, `hub.back`). Forever's
client can close those windows through the interaction manager without
the old close event, so `PLAYER_INTERACTION_MANAGER_FRAME_HIDE` undocks
too (`SharedWindow.InteractionPlace`: `Enum.PlayerInteractionType`'s
MailInfo, Merchant, Trainer and Auctioneer, else 17, 5, 7 and 21); a later
close event for the same place changes nothing. At the auction house only
Tradeskills is needed (`PLACES.auction.only`). Tested in
`tools/test_sharedwindow.lua`. Not yet seen in game.

Kept beside (2026-10-31, FILE_VERSION 3): while a game window is open, a
watcher on the one window (`SharedWindow.Keep`, every `KEEP_EVERY`
seconds, only while shown, never in a fight) docks it once the game shows
its window late, and places it beside again when the game's window moves
or the one window changes width or scale (`hub.spot`). A window too wide
for the room left was pulled back over the auction house by the screen's
edge, then narrowed to the Auction House tab where it stood. Dragged by
hand while docked, it stays. Tested in `tools/test_sharedwindow.lua`.

Closed by the player (2026-11-01, FILE_VERSION 4): closed while a game
window is open (its close gem, or Escape, which closes the vendor too),
it stays closed when that window goes; it never comes back by itself. Only
an addon closing it on leaving a place, `SharedWindow.Close(true)`, lets it
go back to the addon open before (`hub.byItself`, read in OnHide). Butler
passes it from `UI:LeftVendor` and `LeftPlace` (`ButlerTabs:Closed(frame,
byItself)`). Tested in `tools/test_sharedwindow.lua`. Docked or undocked while folded with the fold gem (2026-11-05, FILE_VERSION 6: a player found it squashed after unfolding), the sizes are worked from the size it opens back up to (`SharedWindow.FullSize`, FoldWindow's `state.width`/`state.full`), never the folded strip's, so it opens at the right size.

Tradeskills' tabs have moved in (2026-10-30): the host is `TSTabs` in
`UI/Main.lua` (`TSTabs.host`, given to `SharedWindow:Join`). With One
Window on, opening the window or Settings opens the one window on
Tradeskills (`TSTabs:Route`), laid into its area bare of its own rim and
grip, its tabs hung under the one window. A tab hiding only closes the
one window when it is in the area and no swap is under way
(`TSTabs:Closed`, `leaving`), so picking another addon on the rail never
drops Tradeskills back to its own window. "One Window:" sits on the
General page. Tested in `tools/test_onewindow.lua`.

The Auction House tab (the owner approved the mockup and its words,
2026-10-30): while the one window is docked at the auction house, it
shows its own row of tabs, Auction House (picked first: the drawer's
header and its Sell, Buy, Lists, Auctions and Favors), Prices, Profit,
Queue, Disenchanting, Favors and Writs, then Settings flush right
(`UI.AUCTION_TABS`, `UI.ahTabStrip`, `UI.ahContainer`); Gather, Level Up,
Sales and Characters wait until it leaves. `TSTabs:AtAuctionHouse` (from
`AttachToAuctionHouse`) opens the one window once a visit and docks it;
`TSTabs:Settle`, also called after every dock and undock through
`One.Watch`, lays the drawer in (`PostPanel:IntoOne`) or hands it back
(`OutOfOne`) and swaps the tab rows (`HangStrips`), back to the tab picked
before. "auctionhouse" is never saved as the tab to open on. In a fight,
or with One Window off, the drawer stays its own beside the auction house.
Nothing new is saved. Tested in `tools/test_onewindow.lua`.

## The shared minimap button

A player asked, the owner said build it from a mockup (2026-10-28), in all
five addons: one minimap button for every Blackthornes addon loaded, whose
click opens a small menu (the house frame, "BLACKTHORNES" on the plate, a
dark glass row for each addon with its icon and name; since 2026-10-29 no line under the name, and the menu is as wide as its longest name, measured). A
row's left-click opens the addon, right-click its settings; Farmer's
middle-click brings back its panels and Equipment's Shift-click toggles
the upgrade quest. `UI/SharedMinimap.lua` is the same file in all five (a
fix to it belongs in all five), and so is `tools/test_sharedminimap.lua`.
There is no shared core addon: every copy signs up in
`_G.BlackthornesMinimap`, each addon joins with its own button
(`SharedMinimap:Join`), and the copy with the highest `FILE_VERSION` draws
the shared button and menu. It is on by default (the owner, 2026-10-28):
"Combine Addon Buttons:" in each addon's Settings, ticked unless unticked;
unticked, every addon keeps its own button. Only our own buttons are hidden
or shown, never the game's. Saved in every loaded addon's account save,
account wide, never rename them: `minimapButton` ("shared" or "each", nil
reads as shared), `minimapButtonAt` (the newest answer wins) and
`minimapSharedAngle`. Never call it "One for All" (another addon's name).
Every addon's own button also takes left-click to open and right-click for
settings. Its face is the Blackthornes sign, a gold B in a ring of thorns on
a dark round face (the owner picked it over the anvil, 2026-10-28):
`Media/Frame/MinimapBadge.tga`, drawn by `tools/make_minimap_art.py` (the
same tool in all five; rerun it, never edit the TGA). Not yet seen in game.

## Off, Shift or Always on tooltips

A player asked (2026-10-18, the owner said yes): each tooltip line
Tradeskills adds can be Off, Shift (only while Shift is held) or Always.
`UI/TooltipShift.lua` is the same file in all five addons (a fix to it
belongs in all five); nobody's settings change, so a line that was on
reads Always and one that was off reads Off. Whether a line is on stays in
its own setting; Tradeskills keeps the Shift choice in Config (it sets
`TooltipShift.Read`/`Write` in `UI/ItemTooltip.lua`, `ItemTooltip.SHIFT_SETTINGS`):
`value` (`showValueOnItemTooltips`, every value line, Shift in
`tooltipValueShift`), `sales` (the sales lines under Demand, no Off: their
Shift is the old `tooltipSalesShift`), `trend` (`tooltipTrend`,
`tooltipTrendShift`), `recipe` (`showRecipeValueOnTooltips`,
`tooltipRecipeShift`) and `enchant` (`tooltipEnchantCosts`,
`tooltipEnchantShift`; asked when the lines are written, never kept in
`EnchantTooltip`'s cache). Never rename any of them. A line held back adds
"Hold Shift for more." once a tooltip (`TooltipShift:Held`), and the shared
frame redraws GameTooltip when Shift moves, only while a line is on Shift.
Dropdowns on the Look page (`ShiftDropdown`, `ShowShiftMode` in
`UI/Tab_Settings.lua`); the row once "Sales Details on Shift:" is "Sales
Details:". Tested in `tools/test_tooltipshift.lua`. Not yet seen in game.

## Find a material

A player asked (2026-10-16, the owner said build it, from a mockup) what
to break, make or farm for the best odds at one enchanting material, and
what had given it before. The Disenchanting tab's "Find a material" tick
box (at the toolbar's right end; the other views' tick boxes step aside)
and a material picker show it, under headings: YOU'VE GOTTEN IT FROM
(your own disenchants, `DisenchantLog`, with "You made it" or "Looted,
MOB"), BREAK WHAT YOU HAVE, BUY AND BREAK, MAKE AND BREAK (crafts this
character knows; Queue one) and FARM AND BREAK (Farmer's own kills;
Show in Farmer). Columns COST EACH (price over how many one gives on
average), ODDS and WHERE (`disenchantmaterial`). `Logic/MaterialFinder.lua`
works it out from the tab's own rows (`GetBagRows`, `GetAuctionRows`,
`GetCraftRows`; a row keeps its `source`, so a bag or auction row's detail
is the usual one), kept per material until the bags, prices, queue,
recipes or disenchants move or `KEEP` passes. Nothing is saved; the
material picked lasts the session (`FirstPick`: the best your disenchants
have given). Farmer is asked inside a pcall, read only:

```lua
_G.BlackthornesFarmer.DisenchantFarm:Best(gives, max)   -- gives(itemID): how many one gives
  -- { { mob, zone, shownZone, kills, perKill, seconds, perHour, items = { { id, name, corpses } } } }
_G.BlackthornesFarmer.DisenchantFarm:DroppedBy(itemID)  -- the mob that dropped it most, or nil
_G.BlackthornesFarmer.DisenchantFarm:Show(mob)          -- opens its loot table
```

Without Farmer the farm heading and "Looted" are left out. Tested in
`tools/test_materialfinder.lua`. Not yet seen in game.

## The Characters tab by side

The owner asked (2026-10-16, from a mockup) for the Characters tab to split
Horde from Alliance and show more about each character. `UI/Tab_Characters.lua`
is one full-width table: a heading row per side (the side playing first,
then the other, then OTHER for a record saved before its side was kept)
with how many, their gold and time played; a click folds it. Columns
CHARACTER (class colour, race and class under it), LEVEL (purple XP bar),
RESTED (blue bar, Full at 150%), GOLD, PROFESSIONS (two, then "+N"), MAIL
(items waiting), ZONE, PLAYED and LAST SEEN, each sortable within its side
and hideable (`ns.Columns` list "characters"). Realm: (a player asked,
the owner said yes 2026-10-18) is first on the bar: This Realm (the
default, the realm of the character playing; a character saved with no
realm stays under it), All Realms, then each realm by name, matched
without case or spaces. Realm, Show: Both, Horde, Alliance and the search
(name, profession, zone) last the session. A click on a
character opens a line under it with its best crafts, cooldowns, bags and
bank age, and Forget character (arms first, never the one playing). The
Bank view is unchanged.

`Logic/CharacterNotes.lua` keeps what it shows on the character's own
record in `characters[guid]`, only once the GUID is known: `race`,
`classFile`, `xp`, `xpMax`, `restXP`, `resting`, `zone`, `played` and
`seenAt` (never rename them). Played time is asked of the game
(`RequestTimePlayed`, which prints in chat) once, for a character never
read, and counted on from there. Rested for a character not playing grows
by Classic's rule from when it was last seen (`CharacterNotes.Rested`,
marked a guess in the row's tooltip). `Recipes:AddNotes` gives them to
`GetCharacters`, and AccountLink carries them for the other account's
characters. Tested in `tools/test_characternotes.lua` and
`tools/test_uifit.lua`. Not yet seen in game.

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

Farmed (the owner said build it, 2026-10-16): an auction sale with no cost
known goes under Farmed, not Other sales, when Blackthornes Farmer says
you looted, gathered or fished it yourself (`MethodProfit:Farmed`, asked
once an item per Summary, inside a pcall, read only):

```lua
_G.BlackthornesFarmer.Looted:Has(itemID)   -- true or false; its own records only
```

Without Farmer it stays Other sales. If Farmer changes the call, change
`MethodProfit:Farmed` too.

## What the other addons want kept (the Sell list)

The owner said build it (2026-10-16): the auction house drawer's Sell list
and List all used to offer the whole bag, holding back only what the craft
queue needs. `Logic/SisterKeeps.lua` asks the sisters what they would keep,
through the calls they already make for Butler, inside a pcall, read only:

```lua
_G.BlackthornesFarmer.Butler:Advise(itemID)             -- a goal: up to its target
_G.BlackthornesFarmer.Value:Contents(name)              -- a clam worth more opened
_G.BlackthornesEquipment.Butler:Advise(link, bag, slot) -- upgrade, alt, tool
_G.BlackthornesPets.Butler:Advise(itemID)               -- eats (not buff food)
_G.BlackthornesButler.Verdicts:Choice(itemID)           -- keep, bank, mail
_G.BlackthornesButler.Verdicts:InSet(itemID)            -- an equipment set
_G.BlackthornesButler.Quests:Reason(itemID)             -- an open quest
```

`Posting:GetPostable` takes off what is held (`line.kept`, `keptWhy`); one
held whole is left out, or with `showHeld` (the drawer) kept as a dimmed
row whose detail is why (`line.held`), its own List button still working.
`GetNextPostable` and `GetSummary` never pick a held line, so List all and
Post Crafted never post one; the drawer's summary counts them. Answers are
kept per bag copy until `Inventory.changes` moves or `KEEP` seconds pass. An upgrade
(for you or, ticked, an alt) is held only as many copies as a character
wears, one or two rings or trinkets (`SisterKeeps.Wears`, 2026-10-18); the
spares sell, as Butler's own window says.
"Keep What Other Addons Need" on the Pricing page (`sellHoldsSisterKeeps`,
off unless ticked since the owner asked the same day; `Config:SisterKeepsOffOnce`
turned off the true the first default saved, once, `sisterKeepsOffOnce`;
never rename either). Gear Equipment calls an upgrade
for another character (its `alt`) is held only while "Keep Upgrades for
Alts" is ticked (`sellHoldsAltUpgrades`, off unless ticked, the owner
2026-10-16, never rename it). Tested in
`tools/test_sisterkeeps.lua`. If a sister changes a call, change this file
too. Not yet seen in game.

Also from the sisters (2026-10-16): the Gather tab's tooltip says how fast
you farm a material and how long the rest would take (`CraftOrFarm:PaceOf`,
the Your time view's Farmer call), and crafted gear that's an upgrade for
another of your characters says so after its name on the Profit, Level Up
and Queue tabs (`Upgrades:AltFor`, `AltText`, `WithAltText`, from
Equipment's `Butler:Advise` `alt`; off with the upgrade arrows; tested in
`tools/test_altupgradecrafts.lua`). Those lines show only while "Show
Equipment Upgrades" is ticked (the owner, 2026-10-17): a box at the right
of the Profit and Level Up switch rows (`spec.corner` in
`RecipeBookView.WithSwitch`) and after the Queue's heading, all one saved
value (`showAltUpgrades`, off unless ticked, never rename it;
`Upgrades:ShowsAlts`, `SetShowsAlts`, `CreateAltCheckbox`), shown only
while Equipment is loaded.

## Keep on this character

A player asked (2026-10-18, the owner said build it, "bigger number"):
the Sell list's x hides an item on every character, so there was no way
to keep a few potions on one character and sell the rest on another.
Right-click a row on the Sell list (`UI/KeepBox.lua`, the house frame,
Save and Keep All) to keep a number of it on the character playing;
Settings, Queue page, KEEP ON THIS CHARACTER lists them with Clear.
`Logic/KeepHere.lua` keeps them account wide by GUID,
`keepOnCharacter[GUID] = { [itemID] = count }` (never rename it; a
character whose GUID isn't known reads and writes nothing; 9999,
`KeepHere.MOST`, is Keep All). `SisterKeeps`' keep-here hold takes the
bigger of this number and Butler's own (its `KeepHere:Count`), ticked or
not, and Butler reads this one back the same way, inside a pcall, read
only:

```lua
_G.BlackthornesTS.KeepHere:Count(itemID)   -- how many to keep here, or nil
_G.BlackthornesTS.KeepHere.IsAll(count)    -- true for Keep All
```

Keep both stable; if one changes, change Butler's `Logic/KeepHere.lua`
too. Tested in `tools/test_sisterkeeps.lua`. Not yet seen in game.

## Goblin Gold

The owner said build it (2026-10-17, from a mockup): a small bar on
screen with the gold on every character of this realm and side, and a
goal cheered a tenth at a time. Off unless ticked. `Logic/GoldGoal.lua`
adds it up from `ns.db.characters` (the character playing at `GetMoney`,
the rest as last seen, one character under two records once through
`Characters:Same`, the other account's characters counted; guild data
never), keeps the goal in `goldGoals[realmKey] = { goal, setAt, best,
reachedAt }` (never rename it) and cheers once each time `best`, the
highest tenth reached, moves (a goal starts at the tenth you are on, so
a dip and a climb back cheers nothing). A cheer waits while you fight,
at the auction house or with a game panel open (`GoldGoal:Busy`).
Today, this week, the best day and where most of it came from are
`GoldLog`'s, gold moved between your characters left out; new gold
floats up off the bar from `GoldLog:Record` (`GoldGoal:OnRecord`), never
a transfer. `UI/GoldGoal.lua` draws it: the total counting up, a fill
with lit ticks, coins and a line at each tenth, a window at the goal with
how long it took and a box for the next, the hover card listing every
character in dark glass, drag to move, its own size grip. Sounds are the
game's own by ID. Settings, Look page, GOBLIN GOLD ("Gold Tracker:",
"Gold Goal:", "Gold Tracker Place:") and "Goblin Gold:" under SOUNDS;
`/bts gold [on|off|goal N|reset]`, and `/bts gold test [goal|float]`
(typed only, not in the help line) shows a cheer without saving anything.
Saved, account wide, never renamed: `goldTracker` (off unless ticked), `goldTrackerSound`,
`goldTrackerScale`, `goldTrackerX`, `goldTrackerY`. "Count Gold On:" (a player asked,
the owner said build it, 2026-10-21) picks All Characters or This
Character (`goldTrackerCount`, "all" unless picked, never rename it):
counting one character, `GoldGoal:Members` keeps only the one playing and
its goal is its own, by GUID in `goldGoalCharacters[guid]` (the same
fields; never rename it), so the realm's goal stays as it was. Today,
this week and the sources stay the realm's, since `GoldLog` is per realm. Like every cheer, it
is never announced. Tested in `tools/test_goldgoal.lua`. Not yet seen in
game.

The Sales tab's gold chart under This Character (a player's report,
2026-11-09): its bars and key now follow the pick too. `GoldLog:Record`
also adds each change under the playing character's GUID in
`goldLog[realm].sourcesByCharacter[guid] = { hours, days }` (same bucket
shape, pruned the same; never rename it), and `GoldLog:Bins(..., who)`
reads it when `who` is "character". Days before this update show nothing
there. Untagged gold at the mailbox that matches an inbox amount takes
that mail's kind (`GoldLog:MailMatch`: sold is an auction sale, outbid
an auction buy, your own character a transfer); two kinds with the same
amount stay Mail. Tested in `tools/test_goldlog.lua`.

Where the gold came from (the owner said build it, 2026-10-20, from a
mockup whose words he approved): the hover card ends with THIS WEEK
(Quests with how many were handed in and gold each, Mobs with kills and
gold each counting their loot, "Their loot is worth", Auction sales and
Vendor sales) and ALL TIME (Quests done, Mobs killed, Gold from quests,
Gold looted). `GoldGoal:Sources` reads `GoldLog`'s week by source,
`GoldLog:QuestsDone` (every hand-in counted from this update, in
`goldLog[realm].questsDone[YYYYMMDD]`, never rename it) and the game's
Statistics (`GoldGoal.STATISTICS`, `GoldGoal.Statistic`: a statistic the
client does not give is left out; `/bts probe` has a "statistics" line).
Kills and loot worth are Blackthornes Farmer's, inside a pcall, read only:

```lua
_G.BlackthornesFarmer.Stats:KillsAndLoot(7)   -- { kills, loot, coin } over the last 7 days
```

Without Farmer the Mobs row is its gold alone. If the call changes, change
`GoldGoal:Sources` too. `UI/GoldGoal.lua`'s `GoldGoalUI.SourceLines`
builds the rows. Tested in `tools/test_goldsources.lua` and
`tools/test_goldlog.lua`.

## The public price API

The owner said yes (2026-10-12) to a documented price call for other
authors' addons. `Logic/PublicAPI.lua` sets `_G.BlackthornesTS_API` with
`version` (1), `GetPrice(item)` (`Prices:GetValue(id, "market")`, copper or
nil) and `GetPriceAge(item)` (`Prices:GetAge`, seconds or nil); `item` is
an ID or a link, and neither ever raises. The README's "For addon authors"
section documents it. Other people's addons read it, so never rename or
change these; a new call raises `version`. Tested in
`tools/test_publicapi.lua`.

## Sending data to Blackthornes

The owner said build it (2026-10-18), as Farmer's "Sending drops to
Blackthornes": players can opt in to send what their disenchants gave
(`disenchantLog.items`: casts and each material's times and total) and the
skill each recipe needs on Forever (`recipeSkills`, the number only) to his
characters. Prices are never sent. Off by default (`shareData`, never
rename it), never announced: one tick box on the About page of Settings,
"Share your data with Blackthornes to improve the Tradeskills AddOn.", no
hover, only on North American clients (`Contribute:InRegion`,
`GetCurrentRegion` 1 or 110, else `GetCurrentRegionName` "US"), and
`/bts share data on|off|log` (typed only, not in the help line).
`Logic/Contribute.lua` whispers a hello (`Q<id>:<hash>`) over Comm to each
name in `Contribute.RECIPIENTS` (full names, only in code, never shown; the
same three as Farmer's and Equipment's lists, change all three together) 30 s after login and
every five minutes (the owner, 2026-10-26). Only those characters ask
(`R<id>`), one sender at a time, the next as soon as one is done (or given
up after `SYNC_TIMEOUT`), each at most every five minutes, and the sender
answers only a recipient asking for its own id, at most every `SEND_GAP`.
The sender builds and hashes its table at most every `PAYLOAD_KEEP`
(`Contribute:Built`, kept per id; the hello and the answer send the same
build, so a hash a recipient heard always matches what it then keeps), and
the receiver waits `SYNC_TIMEOUT` (30 minutes, a big table takes a while
at Comm's pace) before giving one up. The table (`K`) is checked by `Contribute:Clean` and
kept apart on the receiver in `sharedData[id] = { at, hash, disenchants,
skills }`, each sender's newest replacing the last (at most `MAX_SENDERS`);
it never joins the receiver's own logs. A chat line, a sound and a screen
line say "Got disenchants and recipe levels from NAME.", and `sharedDataLog`
(`/bts share data log`, the newest `LOG_KEEP`) keeps who sent. Never rename
`shareDataId`, `sharedData` or `sharedDataLog`. Nothing is folded into the
shipped data yet. Tested in `tools/test_contribute.lua`. Not yet seen in
game.

## Sharing between accounts and with a guild

Asked 2026-10-07 (on Discord, the owner agreeing). Over addon
messages (`Core/Comm.lua`, prefix `BTSshare`):

- `Logic/AccountLink.lua`: the player names characters on another account
  of theirs (`linkNames`); both sides must name each other. Their
  characters arrive as ordinary `characters[guid]` records marked
  `linkedFrom` (never rename it), so everything that reads alts (Farmer
  aside, Equipment's crafting included) sees them. A copy never replaces
  one of the account's own characters and is never sent on. Their
  listings (Share Auctions) come under the sender's realm key, which on
  Forever names another server for each account (see the realm fix in
  1.9.7), so `AccountLink:Accept` files a realm that matches ours by
  `RealmKey` under our own `GetRealmKey()`, where Keep in stock reads it
  (`OurRealmKey`); `FileListings` moves ones saved before, at login
  (2026-11-05, a player's report). Account link never sends price scans:
  prices cross accounts only through guild or realm prices.
  Share Craft Queue (Trent, 2026-11-07, a player with three accounts):
  `linkShareQueue`, off unless ticked, never rename it, never announced.
  Ticked, each own character's payload carries `queueNeeds`
  (`AccountLink:QueueNeeds`: what its queued crafts use, less what it
  makes and `Queue:HeldBy`; at most `MAX_NEEDS` items) and `mailAt`.
  The receiver keeps `queueNeeds` only while its own tick is on
  (`CleanNeeds`), and `QueueMail:LinkedNeeders` adds those characters
  (same realm and side, never the one playing) to `GetDeliveries`, less
  `InFlight` to them, so Butler's Advise and Jobs mail steps follow.
  Never relayed. Tested in `tools/test_linkqueue.lua`.
  Share Sales (the owner, 2026-11-07): `linkShareSales`, off unless ticked
  on both sides, never rename it, never announced. Ticked, each own
  character's payload carries `sales` (`AccountLink:OwnSales`: its own
  `mailLedger` entries of kind sold, expired or removed, never `linked`
  ones, never the buyer, the newest `MAX_SALES`, by realm key). The
  receiver keeps them apart in `linkedSales[realmKey][guid] = { at,
  entries }` (never rename it), filed by `OurRealmKey`, cleaned and
  deduped (`CleanSales`), each marked `linked` with `who` the sender's
  GUID, replacing what that character sent before; only while its own
  tick is on, and dropped by `Forget` and `Recipes:ForgetCharacter`.
  Ticking it calls `AccountLink:AskAgain` (clears `linkHash` so the
  partner resends). `Mail:Entries()` (kept by a key with `salesVersion`)
  merges them by time into what the Sales tab (summary, By item, Recent
  sales), `MethodProfit`, `ItemStats` and the Stats tab read; anything
  that writes, and stock decisions (Demand, SellOut, lists), stay on
  `GetLedger`. A linked entry is never rolled up. A new sale does not
  wait for the ten-minute `Check` (the owner, 2026-11-07): when
  `Mail:Reconcile` writes a ledger entry it calls
  `AccountLink:SalesChanged(guid)`, which, while the tick is on, calls
  `AccountLink:SendSoon(guid)`. That marks the character and sends a
  manifest of only the marked characters (`Manifest(only)`) to online
  partners `SOON_DELAY` (5) seconds after the last call, a burst going
  as one, never later than `SOON_MOST_WAIT` (30) after the first. Offline
  partners are left to the usual check. `SendSoon` is the reusable way to
  send any one character's change quickly. Tested in
  `tools/test_linksales.lua`.
  Share Shopping Lists (the owner, 2026-11-07, quick build): "Share
  Shopping Lists:" under YOUR OTHER ACCOUNT, `linkShareLists`, off unless
  ticked on both sides, never rename it. Only the account's own lists
  (name, item IDs, want, have) and its craft queue's list
  (`ShoppingLists:QueueLines`) go (`AccountLink:OwnLists`, at most
  `MAX_LIST_ITEMS`), never what it took from a partner, so nothing is
  relayed. The manifest carries their hash under `lists`
  (`AccountLink.LISTS_KEY`; "off" while unticked; older versions skip the
  key, it is no GUID); a new hash is asked for with V and answered with U
  `{ hash, data }`. The receiver keeps them, only while its own tick is
  on, in `linkedShoppingLists[partner name key] = { from, at, hash, lists,
  queue }` (never rename it; `CleanLists` strips colour codes, junk and
  bad counts), dropped when either side unticks (`ListsTicked`,
  `DropLists`, an "off" hash) or by `Forget`. `ShoppingLists:Linked()`,
  `LinkedList(key)` and `LinkedLines(key)` show them read only, keyed
  `link:<partner>:q` and `link:<partner>:<n>`, named "Craft queue (NAME)"
  and "LIST (NAME)", at the end of the Lists view (Search works, no
  tools, "Other account has N, needs M"), and Snipe's My Lists takes what
  they still need. A list change (`ShoppingLists` `Changed`, not `Touch`)
  or `Queue:Notify` calls `AccountLink:ListsChanged`, which uses
  `SendSoon(LISTS_KEY)`, so it goes in about 5 s. Tested in
  `tools/test_linklists.lua`. Not yet seen in game.
  Prices across the link (the owner, 2026-11-07: "If they are sharing
  accounts thats enough already"): no tick box; whenever the accounts name
  each other (`AccountLink:PricesOn`, `linkNames` set) each one's own scan
  prices for its realm and side (market, cheapest listing, when seen, up
  to `PRICES_USE_FOR` old) go across. The manifest carries `prices`
  ("<last scan b36>@<realm key>" or "off"); E asks for what was seen
  after a time, O is one plain batch, each complete in itself and at most
  255 bytes, taken only `PRICES_TAKE_FOR` after asking. Never a price
  taken from a partner, the guild or the realm, so nothing is relayed.
  Kept in `linkedPrices[realm key][partner key] = { at, count, items }`
  (never rename it), pruned after `PRICES_KEEP`. `Prices:GetValue` uses
  `AccountLink:PriceFor` before the guild and realm, when it was seen
  after this account's own record. A scan finishing (`WatchScans`) sends
  in about 5 s (`SendSoon(PRICES_KEY)`). The Sharing status adds "N prices
  from their scan AGO". Tested in `tools/test_linkprices.lua`. Not yet
  seen in game.
- `Logic/GuildPrices.lua`: on by default since 2026-10-07 (`guildPrices`). Guildmates'
  prices are kept apart in `guildPrices[realm][itemID]` and only fill gaps
  in `Prices:GetValue`: an item never scanned, or one gone stale while
  theirs is newer. So Farmer's `GetValue` can now answer from a guild
  price unless the player turned it off; still copper or nil.
  Catching up (a player's report, 2026-10-22): `ASK_AFTER` seconds after
  login a guildmate sends `G<newest scan held>`, and anyone whose own scan
  is newer (under `ANSWER_SCAN_AGE`) waits, the newer the sooner, and sends
  it again unless another scan went out since (`OnAsk`, `Resend`, at most
  every `ANSWER_EVERY`). "Guild Status:" on the Sharing page is
  `GuildPrices:Status()`, from the save (`guildPricesSent` now keeps
  `count`). Comm sends 8 in a burst, then one a second.

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
same call). A stale price of your own also gives way to it when Auctionator
saw the item a whole day later (the owner said yes to a player's idea,
2026-10-22; `AuctionatorPrices:NewerThan`, from
`Auctionator.API.v1.GetAuctionAgeByItemID`, kept 60 s), as guild and
realm prices may; only for a stale price neither of those replaced. "Auctionator prices" (`auctionatorPrices`, on unless unticked,
never rename it). Tested in `tools/test_auctionatorprices.lua`.
"Price Order:" under them on the Sharing page (the owner, 2026-10-26)
picks TSM First (the default) or Auctionator First for items nothing else
has priced (`priceOrder`, "tsm" or "auctionator", account wide, never
rename it; `Prices:Order`, `OrderedOthers`). The stale-price rule above
holds either way. Farmer has the same choice (its `Value:PriceOrder`).

Farmer shares its own counts the same way (2026-10-11): its `Core/Comm.lua`
and `Core/Serialize.lua` are copies of ours (prefix `BFRshare` instead of
`BTSshare`, no test command, listening only while sharing is on), and it has
its own pairing (`shareNames`) rather than reading `linkNames`. A fix to
`Core/Comm.lua` or `Core/Serialize.lua` here belongs in Farmer's too.

## Guildmates who can make it

A player asked (2026-10-24) to see, on a craft, who else using the addon
online knows the recipe and whisper them; the owner said guild only, never
the realm. Off unless ticked: "Guild Crafters:" under YOUR GUILD on the
Sharing page (`guildCrafters`, account wide, never rename it).
`Logic/GuildCrafters.lua` talks over `Core/Comm.lua`: a guild hello
(`B<hash>`, `:1` the first a session) 40 s after login and every ten
minutes, a whispered ask (`N`) when the hash is new, and the list whispered
back (`L`, `{ h, r }`, recipe IDs in base 36), each guildmate at most every
ten minutes, answers to a first hello spread over a few seconds. Only names
and recipe IDs go. A whisper is taken only from someone whose guild hello
came first, or in the minute after our own first hello (`OPEN_FOR`), and
once the roster is read only names on it show (`members`); one it shows
offline, or not heard for `ONLINE_FOR`, is dropped. Nothing is saved.
The Profit tab's detail pane lists them under "Guildmates who can make
it:" (`UpdateCrafters` in `UI/Tab_Profit.lua`), a click whispers by full
name (`GuildCrafters.Whisper`). Tested in `tools/test_guildcrafters.lua`.
Not yet seen in game.

## Sharing with your realm

The owner asked (2026-10-20) for live prices without an app, a server or a
cost, picked a hidden in-game channel, and said build it from a mockup whose
words he approved. Tradeskills only: Farmer never shares past the guild.
`Logic/RealmPrices.lua`, on unless unticked since the owner asked
2026-10-28 (`realmPrices`, YOUR REALM on the Sharing page, `/bts share
realm on|off`, typed only like guild). Release notes may say it is
there, never that its setting was turned on (the owner, 2026-10-28). Saves made before
kept `false` from the old default, so `Config:RealmPricesOnOnce` turns it
on once (`realmPricesOnOnce`, never rename it); unticked after that stays
off. No price table ships with the addon (the owner, the same day: one
region's prices don't fit another's). When on it
joins a hidden channel for the side (`BTSPrices` plus A, H or N), hides its
join lines, and shares the last scan (Y announce, then Z prices, the guild's
batches) one message every `SEND_GAP` seconds, never in a fight, at most once
an hour, and not when `MIN_SENDERS` others covered that scan. Kept by a hash
of the sender's name, never the name, in `realmPrices[realm][itemID]` and
`realmPricesSent` (never rename either). A price is used only once 3 players
sent one, the middle of the last 5, and only to fill a gap after your own
scans and your guild's (`Prices:GetValue`), before TSM and Auctionator. A
price far from a fresh one of your own is refused. `Comm` hands handlers the
channel's name and target as fourth and fifth arguments. Tested in
`tools/test_realmprices.lua`. Not yet seen in game.
Left by hand (a player's report, 2026-11-06): a `YOU_LEFT` notice for our
channel joins it again `REJOIN_DELAY` seconds later (`OnNotice`), a join
that did not take is followed by `JoinChannelByName` (`triedTemporary`),
and the Settings status says "You're not in the price channel right now."
while it is out (`InChannel`).

## A quick scan when you open the auction house

The owner asked (2026-10-28): with "Auto Scan:" ticked (`autoScan`, on
unless unticked, the auction page), opening the auction house also asks
for one quick full scan when the last scan is over
`Scanner.AUTO_QUICK_AFTER` (15 minutes) old, as well as the old case
(no prices, or prices past `staleAfterSeconds`, which still scans page by
page when it must). `Scanner:ConsiderAutoScan` tries once a visit
(`autoScanTried`, reset on `AUCTION_HOUSE_SHOW`), never in a fight or
while the player is selling. `StartFullScan({ quickOnly = true })` asks
only for the quick scan: nothing while it cools down, no page-by-page
sweep when it goes unanswered or comes back empty (`StopQuickOnly`), and
nothing said in chat (`ReadReplicateResults` speaks through `ns.Debug`).
Never a continuous scan. Tested in `tools/test_autoquickscan.lua`.

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

## Simplified Chinese, French, Spanish and Russian

The owner asked (2026-10-18) for Simplified Chinese, French, Spanish and
Russian in every addon, after a player asked for Chinese. They work like
German: written by us from the English keys, never from a player's or
anyone else's file (the owner turned down a player's zip for safety).
`Locale/zhCN.lua`, `Locale/frFR.lua` ("tu"), `Locale/esES.lua` (one
Spanish for both Spanish clients: it loads on "esES" and "esMX", neutral
words, "tú") and `Locale/ruRU.lua` ("ты"), each in the game's own words,
listed in the TOC after deDE. Lines shared with the other addons (About,
the sister note, What's New, Settings) use the same wording as theirs.
Forever's own item names and "Overcutting" stay English, as in German.
Talk to the owner about "Simplified Chinese", "French" and so on, never
the codes. Every new string gets a line in all five files;
`tools/check_locale.py` checks them all. Tested in
`tools/test_locale.lua`. Not yet seen in game.

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

## The auction house drawer

The owner picked it from a mockup (2026-10-13), after trying and reverting a
Tradeskills tab under the auction house (#616, reverted in #618; don't
re-offer the tab). `UI/PostPanel.lua` is one drawer beside the auction
window, its full height: the Titanforged plate reads "Tradeskills", its
close gem puts it away until the next visit (`CloseForVisit`), and its
header is `UI/Main.lua`'s auction bar (`UI:GetAuctionBar`, made inside the
drawer, placed by `PostPanel:PlaceBar`): the fold button, "Ready to sell" and
its worth, the scan's status and progress, and Post Crafted and Scan as
quiet metal buttons. Post Crafted is off the header for now (the owner,
2026-10-16): its code stays, and `UI.POST_CRAFTED_BUTTON = true` in
`UI/Main.lua` brings it back. Folded, the drawer is that header
(`PostPanel.FOLDED_HEIGHT`), so Scan stays in reach. Rows are dark glass,
names whole (`Theme.SetRowName`), List quiet metal; the one gold button is
List all at the foot (`PostPanel:ListNext`, one listing a click, most
valuable first of what Sell shows). Beside it on Sell, a Duration box (2, 8 or 24
hours, opening upward) sets the same `postDuration` as the Post tab's. Tested in `tools/test_postdrawer.lua`.
Not yet seen in game.

## Fast listing

Players kept asking (the owner said build it, 2026-10-14) for posting
faster than about five seconds a listing. The wait was ours, not the
game's: every click searched for its one item, then asked Yes or No, and
each search and read back counted against `AHQueue`'s budget. The game
only asks for a real click per listing. Now (`Logic/Posting.lua`, "Fast
listing"): List all's first click checks every price on Sell in one
search (`Posting:CheckAll`, `C_AuctionHouse.SearchForItemKeys`, at most
`CHECK_ALL_MOST`), read back by `Posting:OnCheckResults` from the
scanner's browse handler. An item counts as checked (`NoteChecked`,
`IsFresh`, for `FRESH_FOR` seconds; also after any one-item search) only
when the cheapest is someone else's (`Posting.RivalFromRow`) and not under
`CHECK_ALL_FAR_UNDER` of market (a lone low one is the one-item search's to
judge); a copy with a random suffix is never fast. While fresh, a click
(List all, a row's List, Post Crafted, the price editor) calls `Post`
straight away with no Yes/No box (`CanListOnClick`; a listing under what
it cost to make still asks), and `Post`'s guards all still run. List all
passes over an item still being confirmed (`GetNextPostable`'s
`skipSettling`), so nothing goes up twice. Listings close together share
one read back (`ShareVerify`, `NewerVerifying`), and `MAX_CONFIRMING` is
6. Leaving the auction house forgets every check. The button says what its
next click does (the owner, 2026-10-16): "Check Prices - N to list" when
it would only check prices (`Posting:WouldCheckAll`, the same test as
`PostPanel:ListNext`, read again with the wait labels since a check goes
stale), else "List Next - N remaining", and its hover
(`PostPanel.ListNextTooltip`, through the button's `tooltipFunc`) previews
the next stack: item, how many at what price, total, after the cut,
deposit, market, vendor, disenchant, cost to make, then what comes after. "Fast listing" on the
auction page (`fastListing`, on unless unticked, never rename it). Tested
in `tools/test_fastlisting.lua`. Not yet seen in game.

No Yes/No box by default (the owner, 2026-10-28: less in the way). "Ask
Before Listing:" on the auction page (`askBeforeListing`, off unless
ticked, never rename it; `Posting:AsksFirst`) brings the box back as it
was. Off, a click on a checked price lists it (`CanListOnClick`, fast
listing ticked or not, a copy with a random suffix once that suffix was
searched, `checkedSuffix`), and a click on one not checked searches, says
"Click again to list it" and the next click lists; `Post` and
`RefusesEarly` still refuse what the box warned about. "Sell at a Loss:"
(`allowPostingAtALoss`) defaults on the same day, which reaches only new
installs: a saved value is kept. The old `confirmBeforePosting` is still
unread.

A scan's prices count as checked (the owner's report, 2026-11-09: it took
two clicks to list, both saying List, since the auto scan's prices were
never marked fresh and the first click only searched). When a scan commits
prices, `Posting:NoteScanned(itemIDs)` stamps every item it priced through
`NoteChecked`, from both commit paths in `Data/Scanner.lua` (the whole-list
replicate's `CommitScan` and a page by page scan's `CommitBrowseResults`),
so for `FRESH_FOR` (two minutes) one click lists at the scan price with no
search and no "Click again". The search for the whole list (`CheckAll`)
stamps `bulkTried` only once the request really goes out, inside its
`send`, never before: one that waited in the queue and was given up asked
nothing, so the next click asks again instead of falling to one item at a
time for two minutes. `Posting:CheckPending(itemID)` says whether such a
search is still queued, or sent and not yet answered within
`CHECK_ALL_WAIT`; `BulkTried` answers true meanwhile, so the label stays
List Next while a check is out. Tested in `tools/test_fastlisting.lua`.

## The mouse wheel at the auction house

A player asked (2026-10-16, the owner said build it, off by default): with
"Mouse Wheel" ticked on the Auction house page (`mouseWheelListing`, off
unless ticked, never rename it), while the drawer shows, wheel up does List
Next (`PostPanel:ListNext`) and wheel down Cancel next
(`MyAuctions:CancelNext`). `UI/AuctionWheel.lua` binds the wheel with
override bindings to two named buttons (`BlackthornesTSWheelList`,
`BlackthornesTSWheelCancel`), so each notch is the click the game asks
for; they go when the drawer hides, wait out a fight, and a flick does one
thing (`AuctionWheel.GAP`). A list under the mouse still scrolls; the
camera does not zoom while it is bound. Tested in
`tools/test_auctionwheel.lua`. Not yet seen in game.

Kept working (the owner's report, 2026-11-07: it "keeps breaking and
stops working randomly"). It used to bind once and trust a flag, so
anything that bound the wheel after it (another addon, the game) took it
until the drawer closed. `AuctionWheel:Holds` asks the game what each
wheel key really does (`GetBindingAction(key, true)` against
`AuctionWheel.ACTIONS`), and `Update` binds again (cleared first, so ours
is newest) when it isn't ours: as the drawer opens, on `UPDATE_BINDINGS`,
`AUCTION_HOUSE_SHOW`, `PLAYER_ENTERING_WORLD`, after a fight, from the
drawer's OnUpdate every `CHECK_EVERY` seconds (`Tick`, only while it
shows) and when Refresh drops a Snipe or Favors view. The drawer counts
only while `frame:IsVisible()` (a hidden One Window used to keep it
bound). While bound, the drawer lists (Sell, shopping, Auctions, Snipe,
Favors, Lists) take the wheel only when they have more rows to show
(`list:WheelPass`, `list.canScroll` in `UI/Widgets.lua`'s scroll list), so a
turn over a short list lists instead of doing nothing.

Passed over (the owner, 2026-11-08: wheel up "still breaks and stops
working"): the Sell list's next stack was picked at the price it was
drawn with, then refused at the checked price (`RefusesEarly`: under the
floor or its cost) or asked about in the box, and it stayed next, so
every click and turn hit it again. Now a refused stack, one the game
won't auction, or one Skipped in the box (not a box replaced by the
next, `reason == "override"`) is passed over for the visit
(`Posting:PassOver`, `IsPassedOver`): `GetNextPostable` and
`GetSummary` skip it. `SetChosenPrice` and `ForgetChecks` (leaving the
auction house) give it another go. A busy auction house, a throttle or a
full queue never passes over. Nothing saved. Tested in
`tools/test_passover.lua`.

The quiet auto scan never holds listing back (the owner's report,
2026-11-09: after the auction house auto scanned, the wheel did nothing).
`ConsiderAutoScan`'s `quickOnly` scan held `isScanning` for up to 30
seconds, and every Posting guard (`CanPost`, `SecondsUntilPostable`,
`WouldCheckAll`, `CheckAll`) refused with "wait for the scan to finish",
so each wheel notch and click was swallowed. They now ask
`Posting:ScanBlocks()`, which is true only for a scan that is not
`quickOnly`; `StartBrowseScan` sets `quickOnly = false`, so a player's own
page by page scan still makes listing wait as before. Tested in
`tools/test_fastlisting.lua`.

## Odd scans and the price floor

A player's Fine Leather Cloak sold for about 10s for days, then one scan saw
only two listed at 150g each, and the usual price jumped to 45g; the price
floor (a fifth of market) then refused to list it at 55s, Sell at a Loss or
not (the owner, 2026-10-28, on Classic; brought to Forever 2026-10-31).
Two fixes: `Prices.Smooth` holds back a scan
whose market value is over `Prices.ODD_RATIO` (3) times above or below the
running one, and after `Prices.ODD_SCANS` (3) such scans in a row the same
way the running value jumps straight there (`record.odd = { up, n }`, also
on suffix entries; never rename it). And `Posting:GetPriceFloor` takes a
fifth of the lower of market and the cheapest listing from a scan under
`Posting.FLOOR_LISTED_FRESH` (a day) old (`Posting.ListedRecently`), so a
price near what others list it for is never called a mistake. A 1 copper
slip is still refused. Saved prices are read as they are. Tested in
`tools/test_oddscan.lua` and `tools/test_ownprice.lua`.

## Overcutting

The owner said build it (2026-10-15, from a mockup, and picked the name):
an option to post just under the big stack instead of 1c under a few cheap
listings that sell first. `Profit:Overcut` (asked by `ChooseMarketPostPrice`
for stackable goods only, `status == true`, never a random suffix) walks the
scan's price steps (`record.ladder`, now `Prices.LADDER_STEPS` 10, with
`record.ladderAt` when they were read): the first step after the cheapest
with at least `OVERCUT.WALL_MIN` and `WALL_RATIO` times everything cheaper is
the big stack, and it posts 1c under it (Undercut by) only while the
cheaper ones add up to no more than `Prices:GetUnitsSoldPerDay`, the steps
are under `FRESH` old and still start at the cheapest rival, Demand is not
low and the price is within `CAP` of the scanned market value. Basis
"overcut"; Your auctions calls such an auction "overcut", not undercut
(`MyAuctions:Judge`). "Overcutting" on the Pricing page and beside Hide
losses on Sell (`overcutting`, off unless ticked, never rename it). The
setting's tooltip is `Profit.OVERCUT_HELP`. Tested in
`tools/test_overcutting.lua`. Not yet seen in game.

## Shopping lists

A player asked (2026-10-14, the owner said build it) for named shopping
lists. The auction house drawer's switch is Sell, Buy and Lists
(`UI/ShoppingListsView.lua`): "From your craft queue" first (the Buy view's
items, never saved, Save as a list keeps a copy), then the player's own
lists, each with a gold Search that looks up every item still needed (one
`C_AuctionHouse.SearchForItemKeys` through `AHQueue` where the client has
it, else one at a time with a "Next 2/5" button), and per item how many are
owned, the price, a box for how many are wanted, its own Search and an x.
The foot box adds an item (part of a name in any case, "linen 20", an ID,
or a Shift-click anywhere while a list is open and no chat box is typed in:
`View:TakeItem`, hooked after `HandleModifiedItemClick`, `ChatEdit_InsertLink`
and `ChatFrameUtil.InsertLink`, and from `Widgets.ItemShiftClick`; a player
found Shift-click and part names did nothing, 2026-10-14). Names above the
box come from `ShoppingLists:Suggest` over `BuildNames` (prices, recipes and
their materials, bags, stars, the ledger; only names the client has loaded,
built a slice a frame, kept 60 s), dark glass rows, Up/Down, Tab and Enter;
it also names a new list, renames, shows a list's
copy line (`BTSlist1:<name>:<id>x<want>,...`) or takes a pasted one. Delete
takes a second click. `Logic/ShoppingLists.lua` keeps them account wide in
`shoppingLists = { { name, items = { { id, want } } } }` (never rename it).
Tested in `tools/test_shoppinglists.lua` and
`tools/test_shoppinglistsview.lua`.

## List rules

The owner said build it (2026-10-19, from a mockup; he approved the words):
a list can carry rules every item on it follows, like a group in other
auction addons. A **Rules** button on each list's row opens "Rules for
NAME" (`UI/ListRulesWindow.lua`, the house frame, dark glass rows): WHEN
YOU SELL Lowest Price, Keep Listed (stacks at a time), Post For, Keep in
Bags (of each); WHEN YOU BUY Most I'll Pay (each); Clear. The row shows
"N rules". `Logic/ListRules.lua` keeps them on the list itself,
`shoppingLists[i].rules = { floor, listed, duration, bags, maxPay }`, and
each list gets a stable `id` from `shoppingListNextId` (never rename
`rules`, `id` or `shoppingListNextId`). None is set on a new list, so
nothing changes until the player sets one. An item follows the first list
on the Lists view that holds it and has a rule (`ListRules:For`, laid out
once per `ShoppingLists.version`). Where they reach: `Profit:ChoosePostPrice`
(Lowest Price, basis "list", unless the Prices tab has the item's own
price: that wins), `Posting:GetPostable` (Keep in Bags, the bigger keep
wins with `SisterKeeps`; Keep Listed against `Auctions:GetOwnPostedCount`,
"Waiting, already N up"), `Posting:DurationFor` (Post For) and
`BuyQuantity:Fill` (Most I'll Pay fills the box only with units at or
under it, `BuyQuantity.UnitsUpTo`). The Sell list tags a row with its list
or "Own price" (`PostPanel._ListTag`). Tested in `tools/test_listrules.lua`.
Not yet seen in game.

## Price limits

The owner said yes (2026-10-28) to three limits on a price the player
sets. A "Never below" price on the Prices tab can carry **Highest**
(`myPrices[realm][itemID].high`, copper: never list above it) and **When
Cheaper** (`.under = "wait"`: while others sell under the floor it stays in
the bags; nil lists at the floor, as before). `Prices:GetMyLimits`,
`SetMyHigh`, `SetMyWait`; `SetMine` keeps both when the price changes, and a
"use" price ignores them. A list's rules get the same (`high`, `wait`) and a
Lowest Price as a percent (`floorMarket`, `floorCost`, 1 to
`ListRules.MAX_PERCENT`; one floor kind at a time). % of Cost is the last
craft (`CraftedCost`), else the caller's costing for the item's recipe,
else `Cost:GetMaterialValue` (`ListRules.CostOf`); no base, no floor. Never
rename any of these. `Profit:ChoosePostPrice` returns basis "highest" over
Highest (whole silver for an item auction; one under the floor is left
out) and a 5th return `waits`, never for a "derived" or "uncontested"
price; `Posting:GetPostable` then holds the row ("Waiting, others are
selling for less"), so List all skips it, its own List still lists it and a
typed price wins. `GetValue` is unchanged. The screens (the owner said
build it from the mockup `previews/ts-price-limits/`, words approved,
2026-10-28): the Prices tab's own price shows "Highest:" (gold, silver,
copper) and "When Cheaper:" (List Anyway or Wait) only under "Never
below", and its line adds "Never above X." (`UI/Tab_Prices.lua`, the graph
hangs from `my.foot`); the Rules window (`UI/ListRulesWindow.lua`, now
420 wide) has Lowest Price with a Set Price, % of Market or % of Cost
drop-down (`FLOOR_KINDS`, `PickFloor`), Highest Price and When Cheaper;
the Sell list adds "(the most you set)" to a row at Highest. Tested in
`tools/test_myprices.lua`, `tools/test_listrules.lua` and
`tools/test_ownprice.lua`. Not yet seen in game.

## The fold gem

A player asked, the owner picked the mockup (2026-10-24), in all five
addons: a small gold gem left of a window's red close gem folds the window
down to its plate and opens it back up. `UI/FoldWindow.lua` is the same
file in all five (a fix to it belongs in all five), and so are
`tools/make_fold_art.py` (draws `Media/Frame/FoldGem.tga`; rerun it, never
edit the TGA) and `tools/test_foldwindow.lua`. `FoldWindow:Add(frame,
{ onToggle, canFold })` after `Titanforged:Dress`; it sits on the trim, so
`Titanforged.lua` and `BlizzardLook.lua` are untouched. Folded, the window
keeps its place and width and is `FoldWindow.HEIGHT` tall: the rim, fill
and halo stay (`FoldWindow.Keeps`, by where each lies), the bottom corners
and everything else on it hide and stay hidden while folded, and it can
still be dragged. The gem again, closing it, or opening it by a command or
the minimap button opens it full (`Unfold`). In a fight it will not fold
over a button the game guards. With the Blizzard style it is the game's
own minimize and maximize art when the client has it. Tooltips "Collapse
this window" and "Expand this window"; nothing is saved. Here: the main window (`UI/Main.lua`).

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
has no probe). None has a Settings button (the owner, 2026-10-23: checks and debug are typed only, so players never see them; `RegisterHiddenCommand` keeps them out of help, Tradeskills' short help leaves them out). Never rename `lastProbe`; a new
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

Release notes go only to #announcements (the owner, 2026-10-30): the
release workflow no longer posts in #general. `tools/post_general.py` stays
in the repo unused, and the #general paragraph below is history.

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
#announcements)". It carries no CurseForge link and no card (link previews
are turned off). No section or no secret means no post.
A player's name never goes in a report (the owner, 2026-10-09): no
CHANGELOG, #announcements post, commit or PR text names a player, and
`check_release.py` refuses a CHANGELOG section that credits one
(`names_a_player` in `post_general.py`). The #general post is the one
exception: its last line thanks, by their Discord name, everyone who asked
for or reported the changes, each name once ("Thanks Ana and Bob for the
ideas and reports!"); leave it out when nobody asked. Find who asked from
the project's threads.
The thanks line no longer goes out with the webhook post (the owner,
2026-10-13: thank each player with a real @mention, so they get a
notification): `post_general.py` leaves out the paragraph that starts
"Thanks" (`without_thanks`), and the owner's bot, on his PC, posts it under
the release post with the mentions once he approves the wording, looking
the Discord names up there. Discord IDs never go in a repo. NEWS.md keeps
the thanks line, by Discord name, as before; ask the owner for any name
that isn't known.
This tool is also the same in all four repos.
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
hand). The window shows new features only (the owner,
2026-10-13): a section's
fixes and other changes go under a "Fixes and changes:" line, which go to
Discord but not the window, and every line is plain words with no hype,
no questions to the reader, no exclamation marks and no dashes as
punctuation (the tool notes one that trips `STYLE`). **Every release PR that writes a NEWS.md section runs
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

## The About page and the note

The owner asked (2026-10-13) for a note on how the addons are made, once at
the top of What's New and kept on an About page in every addon's Settings.
`UI/About.lua` is the same file in all five (a fix to it belongs in all
five): `About.NOTE` is the owner's wording, a paragraph a key; change it
only when he asks, in all five, with each `Locale/deDE.lua`. `About:Note`
and `About:Info` build the page's two columns (the version, the Discord in
a box to copy, how to report a bug, a thank-you that names no player, a
What's New button and the other Blackthornes addons from
`SisterNote.ADDONS`); each addon's Settings places them on its "about"
page. `UI/WhatsNew.lua` (FILE_VERSION 3) puts the note at the top of the
next window that comes up by itself, alone when nothing is new, then sets
`aboutNoteSeen` in every sister's account save (never rename it); with the
window turned off it waits. Tested in `tools/test_whatsnew.lua`.

One-time cards (the owner, 2026-10-13): an addon can put cards in
`ns.WHATS_NEW_TIPS`, each `{ key, title, icon, paragraphs, hint, button,
run, due }`. The next window that comes up by itself shows each one after
the note, only when `due()` says so (in a pcall), with a button that calls
`run()` and closes the window. Looked at once either way: the key goes in
that addon's account save as `whatsNewTipsSeen[key]` (never rename it), so
a card never comes back; with the window turned off it waits.
`UI/WhatsNew.lua` is at FILE_VERSION 4 for it. Equipment's
`Logic/UpgradeQuest.lua` has the first, for the upgrade quest, due while
it is off.

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

## One look across the addons (the house kit)

The owner said build all of it (2026-10-29), from the unified look's
mockups (22 cards and 9 fixes, `reviews/unified-ui/` in the project
files). These files are the same in all five addons; a fix to one
belongs in all five:

- `UI/HouseKit.lua`: `Widgets.CreateViewTabs(parent, tabs, onSelect,
  opts)` (small tabs on top of a list, one a view: Tradeskills' My Crafts
  and Your Time, Farmer's This Session and Overall; each as wide as its
  words, never cut), `Widgets.CreateChip` (the filter chip),
  `Widgets.CreateEmpty` (the emblem faint, one short line, a gold button
  when there is a next step: "Clear Search", "Show All") and
  `Widgets.CreatePanelGems(header, { onFold, onClose })` (the gold fold
  gem and red close gem for panels that stay up while you play; folded,
  only the header shows; nothing saved).
- `UI/RowMenu.lua`: a right-click on any row opens its menu, what a click
  does first, then the rest. Shift-click and Alt-click still work; what
  the game guards (a craft, a cast, a sale) stays a button.
- `UI/Notice.lua`: one note slot under the top of the screen for every
  addon (`ns.Notice:Show(text, { icon, hold, key })`, signed up in
  `_G.BlackthornesNotice`), so two notes never land on each other.
- `UI/SharedChoices.lua`: Text Size, Window Style, Effects, Use TomTom,
  Guide Me and Arrow Size, changed in one addon, are written to every
  loaded addon (`_G.BlackthornesSharedChoices`); each keeps its own saved
  key and name, and nothing moves until the player changes one.

The rules that came with it:

- A list's footer is a count or a result on the left and the version on
  the right, nothing else. What a click does is the last line, dim, of
  the row's hover. Settings' footer reads "Changes save as you make them."
- Settings: the General page holds the look (Window Style, Text Size,
  Effects, Combine Addon Buttons), TRANSPARENT and ADDONS; Settings is
  the last tab, flush right.
- Rows are one line: a second line under a name moves to the hover.
- A sort picked by a column heading lasts the session; nothing is saved.
- Buttons are Title Case ("Show the Way", "Queue It", "Got It"), and
  "Show the Way" is our map marker and the arrow (TomTom when picked).
- Buttons out on the screen on their own wear the gold plaque
  (`UI/Plaque.lua`).

Tradeskills' part (2026-10-29): the Profit and Level Up switches and the
auction drawer's Sell, Buy, Lists, Auctions and Favors are view tabs
(`RecipeBookView.WithSwitch`, `PostPanel`); Sales keeps its View drop-down.
Stats is no longer its own tab: the Prices tab has Details and Stats view
tabs (`ns.PricesUI:ShowView`, `StatsUI.view`, `StatsUI:Pick`; `/bts stats`
and an old saved `stats` tab open it there, `MOVED_TABS`), so there are
ten tabs. Settings' Look page is LOOK (Goblin Gold, tooltips, columns and
an ARROW section) and a General page holds WINDOWS, ADDONS and SOUNDS.
The header is the version past the portrait, the scan's age as a chip
(items priced and recipes known on its hover) and Scan Auctions in gold.
A right-click on a Profit, Level Up, Deals or Disenchanting row opens the
row menu (`Widgets.CreateScrollList`'s `menu`: Queue One, Show the Way,
Bought to Disenchant, Search the Auction House), and what a click does is
the row's hover's last line (`clickHint`), not the footer. Empty lists
wear the house block (`Widgets.DressEmpty`, `EmptyAction` for Clear
Search). Characters rows are one line, race and class on the hover. The
transfer box has the close gem; Buy Materials at a vendor and Sell Marked
wear the gold plaque; Contribute and disenchant notes go in the shared
note slot. Headings sort with the house arrow (`Media/Frame/SortArrow.tga`).

## The Snipe tab

The owner approved the mockup and its words (2026-11-03). `Logic/Snipe.lua` and `UI/SnipeView.lua`: a Snipe view tab in the auction drawer, off unless ticked ("Snipe Tab:" on the auction page, `snipeTab`; never rename any snipe key: `snipeCap`, `snipePct`, `snipeSound`, `snipeWatch`, `snipeStripOpen`, `snipeWheel`). Start Sniping is a click, never automatic; a session ends on Stop, the auction house closing or the Spending Cap, and clears the finds. It searches a few items at a time, one search at a time, cheapest page only (`AHQueue`), held while the player sells or buys, and keeps listings at or under worth times Snipe Below (default 70). Watch is Priced Items or To Disenchant (green or better gear the character or the Mail page's disenchanter can break; buys are marked through `DisenchantBuys:Intend`). Below Vendor (`snipeWatch` "vendor", 2026-11-03, a player asked) watches against `Disenchant:GetSellPrice` with no cut, greys in, unsure charged prices out, any listing under it a find (`IsDealFor`), Snipe Below greyed, biggest profit a unit first (`Better`). Big buys ask "Confirm". "Wheel Buys:" (`snipeWheel`) makes wheel up buy the best find on that tab only (`AuctionWheel`). The bell is `Media/Sounds/snipe-bell-single.ogg`, once a batch, never in a fight. Tested in `tools/test_snipe.lua`. Handoff and words awaiting his yes: `Docs/handoff/snipe.md`. Not yet seen in game.

My Lists (Trent said build it, 2026-11-06, from a mockup whose words he saw): a fourth Watch, `snipeWatch` "lists", watches the items on the player's shopping lists. "List:" (only in that mode) picks All Lists or one list, saved account wide as `snipeList` (the list id, nil for All Lists; a gone list reads as All Lists; never rename it). Each item's limit is its own Most I'll Pay (a list item's optional `maxPay`, copper, `ShoppingLists:SetMaxPay`, `MaxPayOf`), else its list's `ListRules` maxPay, else worth times Snipe Below (`Snipe:LimitFor`); an item on two lists follows the first that holds it (`Snipe.ListItems`). The limit stands in for worth, so buying, the cap, Confirm and the bell are unchanged. An item drops out once the player has what the list wants (`Snipe.Need`, `DropMet`), and a buy takes no more than that (`UnitsFor`). Heads read Item, Price, Most I'll Pay, Deal. The Lists view gives each item on a list you can change a "Most I'll Pay:" money box on a third line (`View:ShowMaxPay`, the row grown through the name's `rowNeed`), "List rule, X" beside it when the list's rule applies, and "Got all you need" dimmed. The strip's labels share one column measured in the client's words and Watch: and List: one width (`SnipeView.LabelColumn`, `ChoiceWidth`, `LayStrip`); a cell head's sort arrow has its own room (`ARROW_ROOM`). Tested in `tools/test_snipe.lua` (15) and `tools/test_snipelayout.lua`.


## The Enchant strip

Trent said build it (2026-11-05) as a window beside the Enchanting
window, then (2026-11-06) picked option B of a mockup: a strip under the
game's recipe pane, since the window opened behind the queued crafts and
did not feel part of it. `UI/EnchantWindow.lua` (`EnchantWindowUI`) is our
own frame on UIParent, anchored by position to the bottom of the recipe
pane (`FindAnchor`: `ProfessionsFrame.CraftingPage.SchematicForm`, then
older frames), lifted clear of the game's Create buttons (`Lift`,
`CreateButtons`). It shows only for an enchant (`ShouldShow`), never in a
fight, and follows the game's pick through read-only hooks
(`SchematicForm.Init`, `OnRecipeSelected`) plus a look every `PICK_LOOK`
seconds. It holds the item slot (a click opens WORN / IN YOUR BAGS above
the strip), the name, the materials and cost (`InfoLine`) and Enchant or
Put It On. What it reads and casts is still `Logic/EnchantWindow.lua`.
The setting is still `enchantWindow`, off unless ticked; the old window's
saved place and size stay in the save, unread. `/bts probe` has "enchant
strip" lines. Tested in `tools/test_enchantstrip.lua`. Not yet seen in
game.

## Crafted Only on Sell

A player asked, the owner said build it (2026-11-08): a "Crafted Only" tick
box on the auction house drawer's Sell view, between Hidden and Overcutting.
Ticked, Sell shows only lines a recipe of yours makes (`line.isCrafted`,
`PostPanel.CraftedLines` in `PostPanel:ShownLines`), so List Next and List
All work through those only. Off unless ticked: `postCraftedOnly`, never
rename it. Tested in `tools/test_postcraftedonly.lua`. Not yet seen in game.

## My Auctions (the auction tracker)

Trent asked, then said build it (2026-11-11, from a mockup whose words he
approved): a small window of what you have up on the auction house. When
something sells, the row lights gold, SOLD stamps on, coins burst with the
gold, the row slides away and Sold Today: counts up. `Logic/AuctionTracker.lua`
works it out, `UI/AuctionTracker.lua` draws it (house frame, panel gems,
dark glass rows ITEM / LEFT / PRICE, "%d up" foot, "Nothing up right now.").

- The list is read only at the open auction house (`Auctions.live`); away
  from it, what it saw last (else the saved listings of the character
  playing), counting down on its own (`BAND_MOST` for a rough band).
- A sale comes from Sale Alarm's "a buyer has been found" line
  (`SaleAlarm:LogHeard` calls `AuctionTracker:Sold`), which names the item
  only: the gold shown is the buyout less 5% (`CUT`). Two listings of one
  item: the cheapest leaves. Part of a stack: the row stays with fewer.
  An auction that runs out leaves with no gold. No row of yours, no gold.
- Sold Effects Full, Subtle (no stamp or burst) or Off (row goes at once),
  never more than Effects allows (`EffectsLevel`). The sound is Sale Alarm's.
- Settings, Auction page, AUCTION TRACKER: "Auction Tracker:" (off unless
  ticked), "Sold Effects:", "Transparent:" (Off, Some, More, Most; glass
  comes back under the mouse) and "Tracker Place:" Set Default.
- Saved, account wide, never rename them: `auctionTracker`,
  `auctionTrackerEffects`, `auctionTrackerSeeThrough`, `auctionTrackerScale`,
  `auctionTrackerX`, `auctionTrackerY`, and `auctionTrackerSold[character
  key] = { day, copper, count }` (today's sales, started again each day).
- Tested in `tools/test_auctiontracker.lua` and
  `tools/test_auctiontrackerui.lua`. Not yet seen in game.
- New posts showed late or out of sight (Trent, 2026-11-11). Two causes:
  `Auctions:Refresh` dropped a non-forced ask inside its 5 s window, so a
  second post's read never went out; now `RefreshAfter` sends one more
  forced read when the window ends. And only `MOST_ROWS` (8) rows show,
  soonest to end first, so a new post (two days left) landed below them
  with no sign the list scrolled; now `Refresh` scrolls the newest new row
  into sight (never on the first read, `self.seen`) and `PlaceThumb` draws
  a slim gold thumb in the right margin while the list is longer than the
  window. No new words. Tested in `tools/test_verify.lua` and
  `tools/test_auctiontrackerui.lua`.

## The auction house window (taken out)

The owner had a full replacement auction house window started
(2026-11-11, an optional setting) and scrapped it the same day, before
any release: "scrap this idea". All of it was taken out again, so the
auction house works as it did before. Never build it again unasked. A
saved `ownAuctionHouse` may sit in a save that tried it; it is unread,
never reuse the name.
