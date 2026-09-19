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

## Still unverified

**Whether `GetReplicateItemInfo`'s `buyoutPrice` is per-unit or per-stack.**
The addon assumes per-unit for commodities and per-stack otherwise, and
`/bts verify <itemID>` cross-checks that assumption against a targeted
`SendSearchQuery` rather than trusting it.
