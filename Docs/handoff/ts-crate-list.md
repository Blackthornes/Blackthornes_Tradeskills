# Crate Shopping List (design handoff)

The owner asked for this on 2026-11-16 and said "build it", which also
approved the words below. Mockup: project files
`previews/ts-crate-list/index.html` and `crate-list-mockup.png`.

## What it does

When the auction house opens, the AH drawer's Buy tab (`UI/PostPanel.lua`,
view "buy") shows a **Waylaid Crates: N** group above a **Craft Queue:**
group. The new group lists the cheapest bundle for each Waylaid Crate in
your bags (sealed crates need nothing). Crates that need the same material
share one row, and what's already in your bags and bank is taken off.

- Rows: ITEM, BUY, COST, each column sortable, dark glass. The button is
  Search (the same as Buy rows today), or Vendor for a vendor item, or
  "Have" in green when you already own enough.
- Search all covers both groups. The summary line counts both.
- Hover: item name, `Fills:` (e.g. 2 Apprentice Textiles), `Needed:`,
  `You Have:`, `Each:`, then `Other Choice:` with the next cheapest
  bundle ("20 Light Leather", "7g a crate"). The made-from-a-craft price
  may show here, but the list sticks to things you can buy.
- When everything is covered: "Every crate in your bags is ready to fill."
  With no crates in your bags the group is hidden.
- It works the list out again on every AUCTION_HOUSE_SHOW, and after a buy
  or a crate fill (coalesced bag events, never on the ticker).
- Settings: "Crate Shopping List:" on the Auction House page, off by
  default. Description: "Shows what your Waylaid Crates need on the Buy
  list at the auction house."

Approved words: Waylaid Crates: N, Craft Queue:, Have, Fills:, Needed:,
You Have:, Each:, Other Choice:, a crate, Crate Shopping List:, plus the
two sentences above. All six locales, with deDE in "du".

## Code already there

- `Logic/MerchantsFavor.lua`: `Classify(itemID)` names a crate, sealed
  crate or favor. `OnBags()` keeps `self.held` (the crates in your bags).
  `GetRows()` picks each crate's cheapest bundle (`row.best`, with
  `unit`, `cost`, `vendor`). `Owned(itemID)` counts bags, bank and mail.
- `Data/WaylaidCrates.lua`: each crate's bundles `{ itemID, count }`.
- `Logic/ShoppingLists.lua` `QueueLines()` and `Line()` give the row shape
  the Buy view and Search all use.

## Cleanup (approved the same day)

The game now fills a crate from two stacks. Take out the over-a-stack
limit: the "Skip bundles over a stack" box and its setting
(`UI/Tab_Deals.lua` around line 929, `UI/DealsFavor.lua` `skipOverStack`
and the overStack marks around 566-583), and `overStack` / `skipOverStack`
in `Logic/MerchantsFavor.lua` (`GetRows`). Leave any old saved value
where it is and never rename a saved key. Drop the unused locale keys
("Skip bundles over a stack", "Leaves out bundles bigger than one stack,
like 40 Linen Cloth.") and fix any tests that leaned on them.
