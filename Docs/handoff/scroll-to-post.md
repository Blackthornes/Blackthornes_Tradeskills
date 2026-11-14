# Handoff: wheel up to list on the Sell tab stops working

The owner's report (2026-11-14): wheel up to list on the auction house Sell
tab works for a while, then stops. Branch `claude/project-thread-0xdcz2`,
PR to `main`.

Read big files in pieces: grep first, at most 120 lines at a time.

## The path a wheel turn takes (traced)

1. `UI/AuctionWheel.lua` (241 lines): two hidden buttons hold
   MOUSEWHEELUP and MOUSEWHEELDOWN through override bindings while the
   drawer shows. `Update` re-checks the binding every second and on four
   events, so the binding layer already heals itself.
2. Button OnClick -> `AuctionWheel:Turn(up)` -> `Wanted()` -> `Job()` ->
   `Ready()` (0.35 s `GAP`) -> `PostPanel:ListNext()` (`UI/PostPanel.lua:958`).
3. `ListNext`: `Posting:GetNextPostable({ skipSettling = true }, lines)`;
   when the line is not `IsFresh` and not `BulkTried`, `Posting:CheckAll`
   (one bulk search, prints "checking the prices of N items...") and
   returns; else `CanPost`, then `Posting:Request(itemID, qty, price)`.
4. `Posting:Request` (`Logic/Posting.lua:2638`): `CanListOnClick` (fresh
   price) -> `Post` inside the click. Else a single `Scanner:ScanItem`
   whose answer comes later, outside the click, so it can only mark the
   price checked and print "checked the price of X. Click again to list
   it." (`Proceed`, with Ask Before Listing off).

Fresh means: a whole scan in the last `FRESH_FOR` (300 s, `wholeScanAt`),
or `checkedAt[itemID]` (plain items) or `checkedSuffix[id:suffix]`
(suffix copies) that recent. `bulkTried[itemID]` also lasts 300 s.

## Ruled out

- Binding lost: `Update` re-checks it (2026-11-07).
- Freshness key mismatch: `GetSearchKey` is nil for plain items, so
  `IsFreshCopy` falls back to `checkedAt`, which `NoteChecked` writes.
- Supersede starvation in `ScanItem`: a repeat within 20 s answers
  "recent"; an unsent one is replaced by the newest.

## Leading cause (being verified)

"Works for a while" is the five minutes after a scan (`wholeScanAt`):
every turn lists. After that:

- Turn 1 starts the bulk `CheckAll`. A turn 0.35 s later sees
  `BulkTried` true (through `CheckPending`) and falls through to
  `Request`, which starts a single `ScanItem`. `ScanItem` calls
  `Scanner:ClearSearchState()` and sends an item search, so the bulk
  browse answer may be thrown away. `bulkTried` then holds for 300 s, so
  every item left takes the slow path: one turn to check, a second to
  list, and a steady wheel only prints "checking the current price...".
- `OnCheckResults` marks an item checked only when someone else sells it,
  the price is credible and near the usual price. Items nobody else
  sells, or where your own listing is cheapest, stay not fresh but
  `BulkTried`, so they always take the two-turn path.
- Suffix copies are left out of `CheckAll` and are never `IsFresh` after
  the window, so they always take the two-turn path.

Still to rule out: a pending listing that never settles (`VerifyPending`,
`Logic/Posting.lua:2797`), `MAX_CONFIRMING` (6), `Util.WhenAuctionReady`
(`Core/Util.lua:766`) under throttle.

## Fix direction

- While a bulk check that covers the item is out (`CheckPending`), a turn
  starts no single search (it would pre-empt the bulk one).
- No second single search for an item already being checked.
- The wheel lists the next fresh line instead of waiting on one whose
  check is out.
- Test: wheel turns every 0.4 s past the five minute mark keep listing.

## Status

- [x] Trace `ListNext` to the post call
- [ ] Root cause confirmed
- [ ] Fix and test
- [ ] PR
