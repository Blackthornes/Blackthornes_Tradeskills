# Handoff: wheel up to list on the Sell tab stops working

The owner's report (2026-11-14): wheel up to list on the auction house Sell
tab works for a while, then stops. Branch `claude/project-thread-0xdcz2`,
PR to `main`.

Read big files in pieces: grep first, at most 120 lines at a time.

## The path a wheel turn takes

1. `UI/AuctionWheel.lua` (241 lines): two hidden buttons
   (`BlackthornesTSWheelList`, `BlackthornesTSWheelCancel`) hold
   MOUSEWHEELUP and MOUSEWHEELDOWN through override bindings while the
   drawer shows. `Update` re-checks the binding (`Holds`) every
   `CHECK_EVERY` second and on four events, so the binding layer already
   heals itself.
2. Button OnClick (drops `down == false`) -> `AuctionWheel:List()` or
   `Cancel()` -> `Turn(up)` -> `Wanted()` -> `Job()` -> `Ready()` (0.35 s
   `GAP`) -> `PostPanel:ListNext()` (`UI/PostPanel.lua:958`).
3. `PostPanel:ListNext` -> `Logic/Posting.lua` (not traced yet).

## Earlier fixes

- 2026-11-07: binding re-checked while the drawer shows.
- 2026-11-09: one job a tab.
- 2026-11-12 (#1226, cd3e96e): lists let the wheel through
  (`WheelPass`), no second price check within five minutes of a scan.

## Ideas to check (not proven)

- After the five minute window a turn starts a price check and the post
  then runs outside the wheel's click, so the game refuses it.
- A waiting flag in Posting that never clears when its event never comes.
- `Wanted()` or `Ready()` saying no in some state.

## Status

- [ ] Trace `ListNext` to the post call
- [ ] Root cause
- [ ] Fix and test
- [ ] PR
