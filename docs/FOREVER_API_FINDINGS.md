# WoW: Forever beta — API findings

Captured from the live client by `/bts probe`, not from documentation.
Client `1.60.1` build `69913`, interface `16001`.

## Settled

| Question | Answer | Consequence |
|---|---|---|
| Do SavedVariables persist? | **No.** Written at logout, never handed back: `BlackthornesTSDB` and `BlackthornesTSCharDB` both read `nil` at `ADDON_LOADED`. The `loadCount = 3` that once said otherwise was counting the CVar store, inside one client process | Nothing survives on its own. See *Keeping data between sessions* below. |
| Auction house API | **Modern retail.** 85 functions in `C_AuctionHouse`; all 16 legacy globals absent | Single scanner path. No Classic fallback needed. |
| Commodities? | **Yes.** Linen Cloth, Copper Ore, Peacebloom, Coarse Stone, Silverleaf all `isCommodity = true` | Reagents are region-wide unit-priced pools. Unit price handling differs from per-stack items. |
| `ReplicateItems`? | **Present** | Full sweep is one request + a read loop, not hundreds of throttled pages. |
| Copper granularity | `SupportsCopperValues() = true` | Prices stay copper-exact; no silver rounding needed. |
| Profession API | **Modern.** 146 functions in `C_TradeSkillUI` | Schematic-based recipe model. |
| Reagent quality tiers? | **No.** `qualityTiersObserved = false`; every reagent slot has `reagentChoices = 1` | Cost engine stays flat — no quality-tier permutation logic. Significant simplification. |
| Does a recipe report how hard it is? | **Yes, on `GetRecipeInfo().relativeDifficulty` only.** 60 of 60 recipes read answered, out of 477 visible; `Enum.TradeskillRelativeDifficulty` is present and the values match it by name (`0` = Optimal, `3` = Trivial). `C_TradeSkillUI.GetRecipeDifficulty` is **absent**, and so is the classic `GetTradeSkillInfo` list | Skill-up marking works. Read it through `Logic/SkillUp.lua`, which tries the other three sources too and reports which answered — see `/bts skillup`. |
| Which tooltip API? | **Retail's `TooltipDataProcessor`.** Measured 2026-09-22: `/bts tip` reported `hooks that have fired TooltipDataProcessor (113)` after a session's hovering, with the older `OnTooltipSetItem` script hook and the `hooksecurefunc` setter hooks installed alongside it and never firing | Item tooltips can be decorated. `UI/ItemTooltip.lua` still installs all three shapes and lets the duplicate guard sort it out, since this is one client on one build — see `/bts tip`. |
| Is `GetItemInfo`'s sell price what a vendor pays? | **Not always.** Seen 2026-10-03: Greater Magic Wand (11288) shows `Sell Price: 1c` on its tooltip while the Vendor Flips tab, reading `GetItemInfo`'s 11th return, said 15s 35c (Classic's price). Forever's server changed some sell prices and only the tooltip has the new one | The tooltip's `SellPrice` line (`C_TooltipInfo.GetItemByID`, line type 11, `price`) wins over `GetItemInfo` everywhere (`Util.GetTooltipSellPrice`). `/bts sellprice <item>` prints both. |

## Keeping data between sessions

**Update 2026-09-24: fixed by the game.** From build 1.60.1.70009, both
SavedVariables and SavedVariablesPerCharacter load after a full quit
(`/bts db` read `saved data type: table` and `per-character: table`). The data
addon and macro storage described below were removed; this section is kept
as the history of build 1.60.1.

Three paths, and only one of them crosses a restart.

**SavedVariables are written and never read.** The file on disk is correct and
complete -- `tools\restore.ps1` reads it -- so the data is not lost, it is only
never handed back. That makes the file the recovery point, and the reason the
addon must not be allowed to overwrite a good one with an empty session's
write. WoW keeps exactly one generation in `.bak`, so two empty sessions spend
the backup.

**CVars survive a `/reload` and character select, and nothing more.** Neither
ends the client process, so a value that never leaves memory is
indistinguishable from one the client keeps. Everything that read as proof the
CVar store persisted -- the canary's `loadCount`, the soak test, 1321 prices
carried across -- was measured on one of those two paths. The soak test even
asked for character select in its own instructions, so the control varied the
wrong thing.

`Core/Persist.lua` now stamps `BTS_session` with `time() - GetTime()`, the wall
clock at which the client process started. Same number at the next login means
the same process; a different one means a real restart. `/bts persist` reports
it, so no result depends on anyone remembering which they did.

**Registration order matters on a cold start.** Every CVar read used to happen
after a `RegisterCVar` call carrying a default. Within a process that is a
no-op. On a cold start the name is not registered yet, and registering it with
a default is indistinguishable from writing the default over whatever the
client loaded. The addon now reads raw first, registers second, and puts back
anything registration cleared -- counted, and reported by `/bts persist` as
`registration`, because if it ever counts above zero that is the bug.

**The restart-proof path is a second addon.** `tools\restore.ps1` writes
`Interface\AddOns\Blackthornes_TS_Data` from the game's own saved file, under
the global `BlackthornesTSSnapshot`. Addon files load normally on this client,
so this is the one mechanism known to work. `tools\play.ps1` runs it and then
starts the game, which puts the hand-off in the only gap where it fits.

## How the established auction addons do it

Checked against current sources, September 2026, because the answer decides
whether any of the above is necessary.

**All of them use SavedVariables, and none of them has a second channel.**
Auctionator and RECrystallize store plain uncompressed Lua tables.
Auctioneer's `Auc-ScanData` packs its image into Lua *source text* through a
`StringRope`, chunked at `2^22` bytes, and culls anything older than 30 days
— for load time, not disk size. TSM3 keeps a whole realm's scan as one
serialised string in `TSM.db.realm.scanData`; TSM4 embeds LibDeflate and
LibSerialize. Archivist exists purely to compress large data into
SavedVariables. There is no native compression and Blizzard has not added
any.

**The one exception is the model this addon now uses.** TSM's desktop
application does not write SavedVariables. It rewrites
`TradeSkillMaster_AppHelper\AppData.lua` — an ordinary Lua source file in the
addon's load order — and the addon reads the global it defines, then nils it.
Two independent projects on this same Forever build reached the same design
from the other direction: `forever-addon-kit` and `forever-addon-dev` both
copy the client's written SavedVariables into seed files that run as addon
code before the real addon loads. `Blackthornes_TS_Data` is that pattern.

**CVars were never going to work.** warcraft.wiki.gg on
`C_CVar.RegisterCVar`: registered CVars "will persist after relogging/
reloading but not after closing the game". `forever-addon-kit` measured the
same thing on build 1.60.1: registered CVars survive `/reload` but never
reach `config-cache.wtf`, even after a clean logout. So the symptom is
documented behaviour, not a Forever bug.

**Macros are the one in-game store that does survive a cold start here** —
server-side since patch 3.0.2, and measured surviving on this build. The
ceiling is small: 255 characters of body, 16 of name, 120 account-wide plus
18 per character, so about 30KB in total, and it spends the player's own
macro slots. Enough for settings, nowhere near enough for a price database.
`ForeverCDM` in `forever-addon-kit` is a working implementation to copy if
settings ever need to outlive a restart on their own.

**Worth ruling out before building anything further:** `forever-quest-markers`
reports the saved global arriving *late* rather than never, and got
persistence working by binding it in place at `PLAYER_LOGIN` instead of
creating one at `ADDON_LOADED`, preferring the per-character table.
`Config:CheckLateSavedVariables` now watches for exactly that and says so.
If it ever fires, the CVar store and the data addon both become unnecessary.

Sources: [C_CVar.RegisterCVar](https://warcraft.wiki.gg/wiki/API_C_CVar.RegisterCVar) ·
[Console variables](https://warcraft.wiki.gg/wiki/Console_variables) ·
[CreateMacro](https://warcraft.wiki.gg/wiki/API_CreateMacro) ·
[WoWUIBugs #410](https://github.com/Stanzilla/WoWUIBugs/issues/410) ·
[forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) ·
[forever-addon-dev](https://github.com/imperial64/forever-addon-dev) ·
[forever-bugs #34](https://github.com/ClassicWoWCommunity/forever-bugs/issues/34) ·
[TSM AppHelper toc](https://github.com/ddrobner/wow-addons/blob/master/TradeSkillMaster_AppHelper/TradeSkillMaster_AppHelper.toc) ·
[Auc-ScanData](https://github.com/nanenj/wow-addons/blob/master/Auc-ScanData/ScanData.lua) ·
[Archivist](https://github.com/Stanzilla/Archivist)

## Gotchas found in real data

**`GetProfessionInfo` does not exist.** Use `GetProfessionInfoBySkillLineID` or
`GetBaseProfessionInfo`. Enumerate with `GetAllProfessionTradeSkillLines`.

**`GetAllProfessionTradeSkillLines` returns duplicate professions** under two
skill-line ID spaces — a modern one and a legacy one:

| Profession | Modern ID | Legacy ID |
|---|---|---|
| Leatherworking | 2945 | 165 |
| Skinning | 2947 | 393 |
| Alchemy | 2937 | 171 |
| Blacksmithing | 2938 | 164 |
| Enchanting | 2940 | 333 |
| Engineering | 2941 | 202 |
| Herbalism | 2944 | 182 |
| Mining | 2946 | 186 |
| Tailoring | 2948 | 197 |

Both IDs report the same skill level. Deduplicate by profession name or recipes
will be counted twice.

**`Test Profession [DNT]`** (skill lines 2933, 2934) is a Blizzard internal test
entry and must be filtered out of any profession list.

**`GetAllRecipeIDs` returns empty unless a profession window is open.** Recipe
caching has to be opportunistic — harvest when the window opens, persist, and
serve from cache afterwards.

**Bags are not the four bags.** `C_Item.GetItemCount` counts a bag the character
is *wearing* as one of that bag, so the addon walks the containers instead. The
walk then has to know how many containers there are: a reagent bag is a sixth
one sitting past the ordinary four, and a walk of 0–4 never opens it. Reagents
kept where the game most encourages you to keep them counted as reagents you do
not own — the Profit tab said a recipe was unmakeable, and the sell list had
nothing to offer.

The index is read from the client rather than assumed: `Enum.BagIndex.ReagentBag`
first, then `NUM_TOTAL_EQUIPPED_BAG_SLOTS` being larger than `NUM_BAG_SLOTS`, and
nothing if neither says so. The guard matters — on a client laid out the older
way, container 5 is the *first bank bag*, and walking it would report bank
contents as things you can craft with right now.

`Data/Inventory.lua` owns the list (`Inventory:GetCarriedBags`); `Logic/Posting.lua`
and `Data/Scanner.lua` read it rather than keeping ranges of their own, which is
how the count and the sell list came to disagree. `/bts stock <item>` prints the
containers it walked and what each held.

## Sample data

604 recipes visible with Leatherworking open. Sampled schematics:

```
1263079 "Sewing Machine"  -> item 279945, qty 1-1
   1x 273130, 5x 8170 (Rugged Leather), 1x 14341 (Rune Thread)
1263031 "Tanning Rack"    -> item 279941, qty 1-1
   5x 2319 (Medium Leather), 3x 2321 (Fine Thread), 2x 4470 (Simple Wood)
1229432 "Camp Tent"       -> item 279978, qty 1-1
   5x 2318 (Light Leather)
```

All reagent slots are `reagentType = 1` (basic required reagent).
Recipe and output item IDs are in new high ranges (1.2M+ / 279k+), while
reagents are classic-era IDs.

## Posting from an addon: unresolved

`C_AuctionHouse.PostItem` calls are accepted and produce nothing. Symptoms seen,
in order, all of which mislead:

- the call returns without error
- sometimes the server answers "Internal auction error"
- sometimes nothing happens at all
- "Interface action failed because of an AddOn" appeared **once**, from a call
  made in a `C_Timer` callback -- which taints by definition and proves nothing
  about a call made from a real click

Things tried that did not help: every bid/buyout combination, several durations,
posting from a hardware event, and a `SendSellSearchQuery` price quote first.

**`issecurevariable` is not evidence of protection.** It reports whether a
variable is currently untainted, which is true of nearly every Blizzard function
an addon has not overwritten. This was misread as proof that `PostItem` and
`C_TradeSkillUI.CraftRecipe` were protected, and both features were removed on
that basis. They have since been restored.

The realm's auction house was independently found to be broken (see below),
which may account for every posting failure observed. Retest once it recovers.

## Realm-side: manual posting can fail

Blizzard's own Sell tab intermittently fails with **"Internal auction error"**
on this beta. Confirmed with the addon **disabled entirely**, so it is not
taint and not caused by any addon.

Worth knowing because it looks exactly like an addon bug, and it was chased
as one: the addon's `IsSellItemValid`, `GetAvailablePostCount` and
`CalculateItemDeposit` calls were suspected of tainting the sell frame and
were removed, then restored once the error reproduced with no addons loaded.

The realm build (`1.60.1.69800`) is older than the client (`69913`), which
may be related.

**Partly explained since.** At least one of these errors was a price with
copper in it on an item auction, which fails silently in exactly this way --
see the whole-silver section below. Whether the earlier addon-disabled
reproductions were the same cause is not known, because the prices used were
not written down.

## The throttled channel is shared, and so is the search state

Two things about `C_AuctionHouse` that the symptoms do not make obvious.

**The throttle allowance is not per-addon.** Blizzard's Sell tab, its Create
Auction button and its search box send down the same throttled channel the
addon does. Going over it produced **"You're doing that too fast"** on the
player's *own* manual listing while the addon was mid-scan. The addon was the
one over budget; the error appeared on Blizzard's button.

**`IsThrottledMessageSystemReady` reserves nothing.** It answers "may I send
one right now". Two callers polling it on their own timers both see `true` in
the same frame and both send, so an addon can look paced at every call site and
still be over budget. Anything that sends has to queue behind one shared gate
(`Core/AHQueue.lua`) rather than ask this question for itself.

Worst offender found: `RequestMoreBrowseResults` fired the instant each page of
results landed, which is one request per server reply for as long as a sweep
ran.

**Browse and search results are one slot of client state, shared with
Blizzard's frame.** Whichever query was sent last owns it. Two consequences:

- Blizzard's list shows its searching indicator for exactly as long as
  `HasFullBrowseResults()` reports `false`, and nothing will ever set it `true`
  if the query it was waiting on got dropped by the throttle. That is the stuck
  spinner -- not a frame bug, a dropped request with nothing left to answer it.
- A targeted `SendSearchQuery` from the addon supersedes the sell tab's own
  search, and vice versa, so a pending search must always be given a timeout.
  There is no event for a request that was dropped.
- The same sharing cuts the other way and is worth having. The results events
  are not addressed to whoever asked: `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED`,
  `ITEM_SEARCH_RESULTS_UPDATED` and `COMMODITY_SEARCH_RESULTS_UPDATED` all fire
  for a search the *player* ran in Blizzard's own box, and `GetBrowseResults`,
  `GetItemSearchResultInfo` and `GetCommoditySearchResultInfo` answer with that
  search's rows. So every search the player makes can be read into the price
  database for no request and no throttle budget at all -- see
  "Passive capture" in `Data/Scanner.lua`. **Inferred from how the shared state
  behaves, not yet measured in game.**

  Two rules make reading them safe. Never send anything in response, or the
  addon pages through the player's search and spends the allowance their own
  posting needs. And never record an *empty* passive result: an empty shared
  set is as likely to be one cleared for the next query as an item nobody has
  listed, and clearing a real rival price on that guess is how the addon would
  list far under value. A passive observation may add a price, never remove
  one. An empty answer to the addon's *own* search is different -- that is a
  real observation and still clears the rival price.

## Owned auctions are readable; the announcement is not dependable

**`OWNED_AUCTIONS_UPDATED` exists on this client and does fire, but not when a
listing needs confirming.** Measured in game on 2026-09-19: `/bts auctions`
reported `announces changes: yes, 4 time(s) this session`.

Two earlier readings of this were wrong, and both mistakes came from the same
place. First the event was written down as absent because `ns.RegisterEvent`
returned true for it -- but registration is wrapped in a `pcall` and succeeds
for nearly anything, so that says nothing either way. Then the corrected
diagnostic was read as proving the event never arrives, when all it showed was
a session in which none had yet. **A check that reports whether a call
succeeded is not evidence about whether the thing happens.** Count real
occurrences.

What is certainly true is the symptom: the addon waited five seconds for an
announcement, gave up, and reported `could not tell whether that listing went
up` after every post, while the auction sat in the player's Auctions tab. So
the event is not a thing to hang a confirmation on, whatever it is doing.

The reads themselves are fine, and that is what the fix uses. Confirmed in game
on 2026-09-19 with two listings up:

```
QueryOwnedAuctions:   yes
GetNumOwnedAuctions:  yes
GetOwnedAuctionInfo:  yes
announces changes:    yes, 4 time(s) this session
count right now:      2
  1: item=117 qty=8 status=0
  2: item=2447 qty=3 status=0
re-querying...
after querying: 2 auction(s)
```

So verification reads the answer back itself, a few times over about five
seconds after the query goes out, rather than waiting to be told. `status=0` is
`Enum.AuctionStatus.Active`, which is what `Data/Auctions.lua` already assumes.

The timing is the part that needs care. The server's reply lands at no knowable
moment, so a read taken too early sees the old count. Only the last read of a
sequence may conclude that a listing failed: saying "it did not go up" when it
did is a worse error than the one being fixed. `/bts auctions` now reports how
many times the client has actually announced a change, so this is counted
rather than inferred.

## Item auctions take whole silver only; commodities take copper

**This is Blizzard behaviour, not a Forever quirk**, and it is documented.
Warcraft Wiki on `C_AuctionHouse.PostItem`'s `bid`/`buyout`:

> Amount in copper, only accepts gold and silver and silently fails for
> non-zero copper counts.

Measured on this realm with a Linen Bag, one price per attempt:

| Price | Result |
| --- | --- |
| 2s 50c | refused |
| 2s 99c | refused |
| 3s | listed |
| 4s | listed |

Every listing in the browse window ended in `0` copper, and 252 rivals sat at
exactly 3s with nobody a copper under -- which is what a whole-silver step
looks like from the outside.

**Commodities are not affected on this client.** Linen Cloth has listed at 29c
and 32c. The wiki carries the same sentence on `PostCommodity`'s `unitPrice`,
so either the note is wrong there or this build differs; the observation is
what the addon goes on. `PostCommodity` keeps copper precision, `PostItem`
does not.

**"Silently fails" is the part that costs time.** The call returns, nothing is
listed, and the client shows an internal auction error -- the same symptom as a
realm fault, an addon fault, or a taint problem. See the section above, which
was written before this was understood.

**What the addon does with it.** `Util.RoundToSilver` is the rounding;
`Profit:ChoosePostPrice` is the single place the listing price is decided, and
the Sell tab, the Profit tab and `/bts price` all ask it rather than working
the number out again.

Because a copper undercut does not exist on an item auction, the smallest step
down is a whole silver, which against a 3s market is a third of the price.
So an item auction **matches** the cheapest rival at its silver, and only drops
the extra silver when the sale would still clear the `minProfit` setting. An
item whose cost is unknown matches, since that is where giving gold away is
least defensible. `tools/test_silverstep.lua` covers it.

**Classic is different** and worth not confusing with this: Classic Era and the
Anniversary realms use the older `StartAuction`, which does take copper. The
1-copper undercut people remember from Classic is real there and is not
available here.

**`GetReplicateItemInfo`'s `buyoutPrice` is the whole row's price, commodities
included** (confirmed 2026-09-29 with `/bts verify 2589`: a fresh search gave
Linen Cloth 40c each, the quick scan had stored 83c as the cheapest and a
market 16 times too high). Every row is divided by its count; a commodity row
can be bigger than a stack, so it skips the stack-size guard.

## Disenchant results follow the Classic table, mostly

193 disenchants recorded in game (to 2026-10-01) all fit the built-in Classic
table in `Logic/Disenchant.lua`: green armour of item level 13 to 30 and
green weapons up to 20 gave the dust, essence and shard the table names, at
about its chances (armour 21-25: Strange Dust 76%, Lesser Astral 16%, Small
Glimmering 8%; armour 26-30: Soul Dust 70%, Greater Astral 25%, Large
Glimmering 6%; weapons 16-20: Greater Magic 85%). Wands of item level 12 and
17 broke as the table says too.

A player's Dire Wands (item level 26, needs level 21; the table says Greater
Astral) gave magic essences (2026-10-07). One guide says Forever goes by the
level needed to wear an item rather than its item level, on bands five
lower; on all the items above the two tables give the same answer, so this
data cannot tell them apart, and neither explains magic essence from a Dire
Wand. So an item's own results now win once it has been disenchanted three
times and its most likely result differs from its row
(`Disenchant.ITEM_LEARN_AFTER`, `DisenchantLog:GetItem`).

**Green weapons of item level 21 to 30 give Greater Magic Essence**
(2026-10-09). Twelve Dire Wands (item level 26) gave Greater Magic 7 times
(1-2 each), Soul Dust 3 and Large Glimmering Shard 2; a player's Forester's
Axe (item level 23) gave 2 Greater Magic. The dust and shard are the Classic
row's, only the essence is lower, and armour of the same levels still gives
astral. The table carries this as `weaponEssence` on those two rows. Not yet
seen: a green weapon above item level 30, or a weapon of 21 to 25 giving its
dust or shard.

## Still unverified

**How a profession window can be opened from the addon.** Casting is
protected, so the Queue tab lays a `SecureActionButtonTemplate` button
(type `spell`, the profession's name, or Smelting for Mining) over its craft
button and lets the player's click do the cast (`UI/ProfessionOpener.lua`).
`C_TradeSkillUI.OpenTradeSkill(skillLineID)` does NOT work from addon code:
seen in game 2026-09-25, 2945 opened nothing, and the game then reported
"Interface action failed because of an AddOn" (most likely the 165 try). Registered for key down
(with `ActionButtonUseKeyDown` on), the secure button never cast and the
mouse release fell through to the frame underneath; it now registers
`AnyUp` with `useOnKeyDown` false.

**Selling at a vendor from addon code (added 2026-10-07).** The Warcraft
Wiki marks `C_Container.UseContainerItem` as protected on current retail, so
the vendor's Sell marked button (`UI/SellMarked.lua`) is a secure button: each
click sells one stack through a `/use bag slot` macro line, set only while the
vendor is open and checked again in `PreClick`. Not the template's `item`
type, which equips gear instead of using it. `/bts selltest` (Settings, Test
selling) sells the cheapest grey item from addon code and keeps whether the
item left and gold came in (`sellTest`); `/bts probe` shows it as "sell from
addon". If it works, one click sells every marked stack, up to 12 a visit.

**Addon messages (sharing, added 2026-10-07).** `Core/Comm.lua` assumes
retail's rules: `C_ChatInfo.RegisterAddonMessagePrefix`, 255 bytes per
message, a per-prefix throttle (a short burst, then about one a second,
refused with result 3 when exceeded), WHISPER to one character on the same
realm, GUILD to the guild, and "No player named '%s' is currently playing"
in chat for a whisper to someone offline. Measured 2026-10-07 with `/bts share test`: the prefix registers; a
whisper to the first name alone finds nobody ("No player named
'First' is currently playing"), because Forever lets characters share a
first name, so whispers need the first and last name; a guild message came
back with the sender read as "First Last" (a space, no realm). The client
said "sent" to a 256-byte message and to twelve in a row, so neither the
size limit nor the throttle shows on the sending side; the addon keeps to
255 bytes and paces anyway. Retested 2026-10-07 after whispers moved to the
full name: a whisper to "First Last" arrives, with no "No player named" line,
and all fifteen test messages came back, the 256-byte one, the twelve in a
row and the guild one included, so Forever neither refused 256 bytes nor
throttled twelve. `/bts share test` (Settings, Sharing, Test messages) whispers this
character a full-size and an oversize message and twelve in a row, sends one
to the guild, and says what came back and how the sender's name reads. Also
open: whether a whisper's sender name tells apart two characters with the
same first name, since Forever allows that.

## Bank slot events fire with the bank shut

`PLAYERBANKSLOTS_CHANGED` and `PLAYERREAGENTBANKSLOTS_CHANGED` arrive on
Forever when no bank window has been opened (seen 2026-10-10: two characters'
saved bank snapshots were stamped minutes old, one of them empty, after days
away from a banker). A shut bank still reports its slot count, with nothing in
the slots. So `Data/Inventory.lua` reads the bank only between
`BANKFRAME_OPENED` and `BANKFRAME_CLOSED`; the slot events re-read it only
inside that window.

## Addon messages on a custom chat channel

Probed 2026-10-20 with `/bts share channel`. `JoinTemporaryChannel` joins a
named channel, and its join and leave lines can be kept out of chat with
`ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", ...)`.
`C_ChatInfo.SendAddonMessage(prefix, text, "CHANNEL", number)` works: the
sender hears its own message back, with the sender read as "First Last",
`channelName` the channel's name and `target` "4. Name". The throttle is
harsh: about eight at once, then result 3, and sends paced every half second
were still refused with result 8. A 256-byte message was said to be sent. So
`Logic/RealmPrices.lua` sends one message every 3 seconds and only when
nothing else of ours is waiting.

## The one window's docking (not yet seen in game)

`UI/SharedWindow.lua` (2026-10-30) docks the one window beside the game's
own windows by screen position only; it never moves, hides or writes a
Blizzard frame. What it expects of Forever's retail engine, from the
retail client, not yet seen in game: `AUCTION_HOUSE_SHOW`/`AUCTION_HOUSE_CLOSED`
with `AuctionHouseFrame`, `MAIL_SHOW`/`MAIL_CLOSED` with `MailFrame`,
`MERCHANT_SHOW`/`MERCHANT_CLOSED` with `MerchantFrame`, and
`TRAINER_SHOW`/`TRAINER_CLOSED` with `ClassTrainerFrame`. The retail
client can close these through `PLAYER_INTERACTION_MANAGER_FRAME_HIDE`
(its argument an `Enum.PlayerInteractionType`: MailInfo 17, Merchant 5,
Trainer 7, Auctioneer 21) without the old close event, so that event
undocks too. Every event is registered inside a pcall.
