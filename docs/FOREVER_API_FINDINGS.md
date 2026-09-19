# WoW: Forever beta — API findings

Captured from the live client by `/bts probe`, not from documentation.
Client `1.60.1` build `69913`, interface `16001`.

## Settled

| Question | Answer | Consequence |
|---|---|---|
| Do SavedVariables persist? | **Yes.** `loadCount = 3`, session 2's canary read back in session 3 | The community report of broken persistence is wrong (or already fixed). Price DB persists normally; no export/import fallback needed. |
| Auction house API | **Modern retail.** 85 functions in `C_AuctionHouse`; all 16 legacy globals absent | Single scanner path. No Classic fallback needed. |
| Commodities? | **Yes.** Linen Cloth, Copper Ore, Peacebloom, Coarse Stone, Silverleaf all `isCommodity = true` | Reagents are region-wide unit-priced pools. Unit price handling differs from per-stack items. |
| `ReplicateItems`? | **Present** | Full sweep is one request + a read loop, not hundreds of throttled pages. |
| Copper granularity | `SupportsCopperValues() = true` | Prices stay copper-exact; no silver rounding needed. |
| Profession API | **Modern.** 146 functions in `C_TradeSkillUI` | Schematic-based recipe model. |
| Reagent quality tiers? | **No.** `qualityTiersObserved = false`; every reagent slot has `reagentChoices = 1` | Cost engine stays flat — no quality-tier permutation logic. Significant simplification. |

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

## Still unverified

**Whether `GetReplicateItemInfo`'s `buyoutPrice` is per-unit or per-stack.**
The addon assumes per-unit for commodities and per-stack otherwise, and
`/bts verify <itemID>` cross-checks that assumption against a targeted
`SendSearchQuery` rather than trusting it.
