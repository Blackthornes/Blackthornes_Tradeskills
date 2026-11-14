# Tradeskills memory review (2026-11-14)

Items 1 and 2 are built (2026-11-14, Trent said "implement 1 and 2"); the
rest is still research only. Every idea keeps every feature, and none
deletes or renames saved data.

Sizes were measured by loading each file into a Lua 5.1 runtime (the
client's version) and reading `collectgarbage("count")` before and after.
Saved data sizes are per item, measured on records shaped like the real
ones; how many items a player has depends on how much of the auction
house they scan.

## Ranked: biggest saving for the least risk first

### 1. The merged recipe book (about 3.4 MB, plus churn)

**Built (a and b):** `NoteSeen` and `LearnSkill` mend the one record in
place when the read can't move it (same name, item made and profession);
anything else still throws the book away, and mid-sweep it waits for the
sweep's end. Reagent tables are shared by item and count and reused
across builds. Tested in `tools/test_recipebookpatch.lua` against a fresh
build. Idea c is not built.

`RecipeBook:GetAll()` (Logic/RecipeBook.lua) builds `self.merged`: a
second full copy of every recipe (2349 of them) as a table of about 18
fields, plus a reagent table of `{ itemID, quantity }` tables per recipe,
plus the `itemsFor`, `byOutput`, `byName` and `aliases` lookups. A
build of the same shape measured about **3.4 MB**, on top of the 1.66 MB
static book it is made from.

It is built nearly always: Butler's `IsCrafted`, Level Up (LearnNext,
RoadPlan, SkillUp, Shuffle) and the enchant tooltip (a second after a
hover) all ask for it. And it is thrown away whole (`self.merged = nil`)
by `NoteSeen` for each recipe a profession window shows, by `LearnSkill`
and by the end of a sweep, so each rebuild leaves about 3.4 MB of garbage
for the collector, and opening a profession window can do it more than
once.

Suggestions, in order of how safe they are:

- **a. Patch, don't throw away.** When one recipe is seen or one skill is
  learned, update that recipe's record (and its lookups) in place instead
  of `self.merged = nil`. Same tables, same answers, no rebuild garbage.
  Low risk; a test can compare a patched copy with a fresh build.
- **b. Share the reagent list.** Reagent tables are the biggest single
  part. Build each `{ itemID, quantity }` table once per distinct pair, or
  keep them flat (`{ id, qty, id, qty }`) with a small iterator. The first
  keeps the shape every caller reads (`reagent.itemID`); the second saves
  more but touches every reader. Saves roughly 1 MB.
- **c. Records on demand.** Keep only what differs from the static row
  (seen skill, Forever's skill, trainer cost) and give each record a
  metatable that reads the rest from the static row. Up to about 3 MB
  saved. Medium risk: `pairs()` over a record would miss fields, so every
  reader has to be checked first.

### 2. Saved auction prices: history as small tables (about 1.9 KB an item)

**Built:** `record.history` is now `{ t, m, q, t, m, q, ... }`, a missing
price or count kept as `false`. Every reader goes through
`Prices.HistoryCount`, `HistoryReading` and `EachReading`, which read both
layouts (ItemStats, VendorFlips and PriceGraph carry a fallback for the old
one). An old record is laid out flat, every number kept, when it next gets
a reading (`Prices.AddReading`) or when the background pass reaches it
(`Prices:FlattenSoon`, 20 s after login, 200 records a frame, this realm
only). No key is renamed. Sharing and the data addon never carry history,
and `PriceTransfer` starts an empty one, which reads in either layout.
Tested with an old save in `tools/test_pricehistoryflat.lua`.

Each scanned item's record (`ns.db.prices[realm][itemID]`) keeps its
last 12 readings as `{ t = , m = , q = }` tables. A record measured
**about 5.2 KB**; with the same numbers kept flat
(`{ t, m, q, t, m, q, ... }`) it measured **about 3.3 KB**. With 10,000
items scanned that is about 19 MB of the save's in-game size.

Readers: Data/Prices.lua, Logic/ItemStats.lua, Logic/VendorFlips.lua,
Logic/PriceTransfer.lua and UI/PriceGraph.lua. A change would need:

- a lossless one-time reshape at load (every number kept, just laid out
  flat), and a reader that still understands the old shape, so a save
  from an older version always reads;
- the Blackthornes Prices data addon and any price sharing checked for
  the shape they send.

Biggest saving of all for players who scan everything, but it touches
saved data, so it needs a test with an old save and a careful rollout.
Medium risk.

### 3. Prices for other realms stay loaded forever

`Prices:Prune()` drops records not seen in 21 days, but only on the realm
you are on. A realm you played once keeps its whole price table loaded on
every other realm, for good. Nothing is wrong with the data; it is just
carried around. A lossless choice: prune a realm's table the same way the
next time you log in there (it already happens), and leave other realms
alone, but show their size in `/bts db` so a player can see it. Clearing
them would have to be a typed command the player chooses. Low risk, small
to large saving depending on the player.

### 4. Static data loaded for everyone (about 2.5 MB)

| File | Memory |
|---|---|
| RecipeBook.lua | 800 KB |
| ForeverRecipes.lua | 859 KB |
| LearnSpots.lua | 319 KB |
| VendorSpots.lua | 251 KB |
| ForeverVendorSpots.lua | 146 KB |
| CraftsmansWrits.lua | 61 KB |
| Travel.lua | 39 KB |
| WaylaidCrates.lua | 30 KB |
| TravelZones.lua | 10 KB |

Options, none urgent:

- Pack rows as strings and unpack the few that are read (smaller in
  memory, slower on first read). Medium risk; the generator tools change.
- Load on demand per profession: a sub-addon per profession's data,
  loaded when a character has it or a window asks. Saves the most for a
  player with two professions, but Lua 5.1 needs separate sub-addons in
  the TOC and every reader has to cope with data that arrives later.
  High risk; a long-term idea only.
- The locale files are not a cost: each returns at once on other clients.

### 5. Smaller things checked

- Most saved logs are already capped: price history (14 days), Stats (90
  days, 40 posts), Gold log (8 days by hour, 400 days by day, 2000 a
  session), listed auctions (31 days), mail ledger (400), realm and guild
  prices (7 days, 20,000 items each), seen recipes (one a recipe).
- `Debug/ScrollTrace.lua` is in the TOC; it comes out before the next
  release anyway.
- Row scripts: no list was found making new closures on every redraw in
  a hot path; the Widgets row lists set their scripts once per row.

## Not suggested

Anything that drops readings, shortens history, clears another realm's
prices by itself or renames a saved key. Those would lose data or
features.
