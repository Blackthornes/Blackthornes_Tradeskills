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
- Supersede starvation: the single check goes through `Util.WhenAuctionReady`
  with `key = "item-search"`, urgent, `expires = 6`, so a newer one replaces
  the queued one. No pile-up of dead sends.
- `ScanItem`'s `ClearSearchState()` throwing away the bulk answer: it only
  clears `searchTimeout`, `pendingItem` and `abandonedItem`.
- The 6 s stand-down after a listing: it holds back non-urgent requests
  only; price checks are urgent.

## Queue facts (Core/AHQueue.lua)

1.2 s between sends (`MIN_SPACING`), 8 sends per 15 s (`BUDGET_MAX`,
`BUDGET_WINDOW`), 10 s backoff after a dropped search (blocks everything),
a queued single check gives up after 6 s ("the auction house stayed busy").
`Posting:Request` has a 5 s fallback of its own. `CanPost` refuses on
`IsThrottled()` ("the auction house is busy") and `ConfirmingFull`
(`MAX_CONFIRMING` 6, "still confirming the last listing").

## What holds from the code

"Works for a while" is the five minutes after a scan (`wholeScanAt`):
every turn lists inside the click. After that:

- Turn 1 starts the bulk `CheckAll` and lists nothing.
- `OnCheckResults` marks an item checked only when someone else sells it
  at a credible price near the usual price. Items nobody else sells, or
  where your own listing is cheapest, stay not fresh but `BulkTried` for
  300 s: one turn to check (answer comes later, outside the click, "Click
  again to list it"), a second to list.
- Suffix copies are left out of `CheckAll`: always two turns.
- `ListNext` always stops on the first postable line, so one line whose
  check is out takes every turn; a steady wheel prints "checking the
  current price..." and lists nothing.

## Checked 2026-11-14: a listing always settles, but a steady wheel stalls

`VerifyPending` (2797) runs 3 s after a listing (`POST_VERIFY_DELAY`), may
be put off by `ShareVerify` (2858) up to 3 s more (`VERIFY_SHARE_MOST`)
while newer listings are due within 1.6 s (`VERIFY_SHARE`), gives up after
15 s (`VERIFY_GIVE_UP`) and drops anything older than 60 s. So nothing
stays pending for good. That theory is out.

What does stop the wheel, even with fresh prices: `CanPost` refuses with
"still confirming the last listing" once `MAX_CONFIRMING` (6) other items
are pending (`ConfirmingFull`, 279). Turns are 0.35 s apart and each lists
a different item, so after about 7 listings (2.8 s) the cap is hit. The
first read back is put off to as late as 6 s after the first listing, and
every listing calls `AHQueue:NoteSend()`, so the urgent read also needs
1.2 s of quiet. Net: about 3 s of listing, then about 3 to 4 s where every
turn is refused, then it works again. This fits "works for a while, then
stops".

Smaller: `CanPost`'s `IsThrottled()` can eat a turn right after a listing.

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
