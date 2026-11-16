# Tradeskills UI cleanup (2026-11-16)

What was looked at, what was fixed, and eight recommended changes. The
recommendations are not built: each needs the owner's yes on its mockup
first, and its player words approved. Mockups are in the project files under
`mockups/ts-ui-cleanup/` (drawn by `make-mockups.py` there).

## Fixed in this pass

- **Threads running out of room.** `python tools/runtests.py` printed every
  passing check: 11,707 lines, 591 KB, on every run. The sister addons print
  4 to 20 KB. It is now quiet (one line when all pass, the last 25 lines of a
  suite that fails), suites can be picked by name, and `-v` prints
  everything. `tools/syntaxcheck.py` printed 492 "OK" lines (16 KB) and now
  lists failures only. See "Running the checks" in CLAUDE.md.
- **Picked suites.** Twenty suites lean on a global an earlier suite leaves
  behind (`time`, `GetTime`, `CreateFrame`, `date`), so they failed when run
  alone. A picked suite now runs after the ones before it, unreported.
- **Your Time note cut off.** The note under each way on the Your Time view
  ("Farm some X and this fills in.") was one line that never wrapped, so a
  long item name ran off the card. It wraps and the card grows.

## Checked and found sound

- Every `OnUpdate` (35) and every repeating timer (18). The always-on ones
  are throttled or sleep when nothing shows; the rest stop themselves.
- Every handler on a burst event (`GET_ITEM_INFO_RECEIVED`, `BAG_UPDATE*`,
  `PLAYER_MONEY`, `TRADE_SKILL_LIST_UPDATE`, `MAIL_INBOX_UPDATE`). Each one
  returns early when its window is hidden or nothing is waiting, and
  coalesces to one redraw.
- Widgets made in redraw code. All are pooled and reused.
- Window Spots: Set Default reaches every saved spot.
- Memory: nothing new since `Docs/handoff/memory-review.md`. Its items 3
  (other realms' prices stay loaded) and 4 (static data, about 2.5 MB) are
  still open and still the largest savings left.

## Worth a look in game (not verified here)

One-line labels that never wrap and have no shorter wording to fall back
on. Each could end in "..." with a long name or in a longer language:

- `UI/ShuffleView.lua` `row.chain` (the chain of items under a shuffle).
- `UI/YourTimeView.lua` `line.how` (how a material is farmed).
- `UI/BankView.lua` `line.sub` (where an item is held).
- `UI/Tab_Settings.lua` the ignored-list rows and the Keep in Stock by
  Profession rows (`row.label`).
- `UI/Tab_Sales.lua` the summary tiles' `value` and `sub`.

## Where our windows overlap today

What sits where, from the code:

| At | Pieces |
|---|---|
| Auction house | The one window docks beside it, with the drawer inside as the Auction House tab. With One Window off, the drawer sits beside the auction house. My Auctions and the gold bar float. |
| Profession window | The craft pane hangs on its right edge, moves past or under the character sheet. The profit card and the enchant strip sit inside the profession window. The one window is **not** docked here. |
| Mailbox | The one window docks beside it. The mail panel goes beside that, a third panel wide. The mail report opens mid-screen. |
| Anywhere | Gold bar, way arrow, notices, gold goal windows, Sell Marked button, mail tally, My Auctions, Guide Me card. |

First spots on a fresh install (before anything is dragged):

| Piece | First spot |
|---|---|
| Gold bar | top centre, 120 down |
| Way arrow | top centre, 140 down |
| Mail tally (no mail window found) | top centre, 140 down |
| Notices | top centre, 150 down |
| Gold goal windows | top centre, 150 down |
| Sell Marked button | top centre, 180 down |
| My Auctions | right edge, 40 in, 60 up |
| Guide Me card | right edge, 60 in, 60 up |
| Craft pane (no profession window found) | right edge, 40 in |

## Recommendations: overlap

### 1. One docked window at the profession window

Mockup: `overlap-1-profession-window.png`

Make the profession window a dock place like the auction house, mailbox,
vendor and trainer (`SharedWindow.PLACES`), and lay the craft pane in as
the first tab, the way the drawer became the Auction House tab
(`PostPanel:IntoOne`). With One Window off, or in a fight, the pane stays
on the profession window as today. `UI/SharedWindow.lua` is shared by all
five addons, so this is one change made in five repos.

### 2. The mail to-do list moves inside the docked window

Mockup: `overlap-2-mailbox.png`

At the mailbox the mail panel becomes a tab in the docked one window
instead of a third panel past it. With One Window off it stays beside the
mail window.

### 3. Small pieces take the next free spot

Mockup: `overlap-3-small-pieces.png`

Two shelves, one down from the top centre and one down the right edge. A
piece that has never been dragged asks the shelf for the next free place
instead of using its own fixed number. A dragged piece keeps its spot. The
shelf belongs in a shared file so Farmer's, Equipment's and Butler's small
pieces can use the same two shelves; today each addon picks its own numbers
without knowing the others'.

### 4. No room beside it: a slim strip inside the profession window

Mockup: `overlap-4-strip-inside.png`

When there is no room for the pane beside the profession window, show a
slim strip inside the window's foot (Craft Next and Open Queue), the way
the profit card and enchant strip already sit inside it. This is the
"overlay on Blizzard's UI" case. It replaces the pane being pushed over
the profession window by the screen edge. Nothing of the game's is hidden
or moved; the strip lifts clear of the game's own buttons the way
`EnchantWindowUI.Lift` does.

## Recommendations: Settings

About 130 rows on nine pages. No setting is removed or renamed by any of
these, and no saved choice changes.

### 5. Tooltips get their own page

Mockup: `settings-1-tooltips-page.png`

Eight Off, Shift or Always rows sit in a 16 row section on Look. Give them
a page, with one choice on top that sets them all and each line still able
to have its own. The two buttons that only open a tab (Recipes to Learn,
Stats) go; Road to 300 (it opens the Welcome card again) moves to About.

### 6. Rows sit on the page a player would look on

Mockup: `settings-2-where-rows-move.png`

- Fast Listing, Ask Before Listing, Bypass Disallowed Postings, Mouse
  Wheel, Snipe Tab and Wheel Buys are under When to Sell on Pricing. They
  belong on Auction House.
- TSM Prices, Prefer TSM Prices, the two TSM source boxes, Auctionator
  Prices and Price Order are on Sharing. They pick a price; nothing is
  shared. They belong on Pricing.
- Tracker Place, Gold Tracker Place and Window Spots are three reset
  buttons on two pages. One row.
- Open at AH and Open With AH and Vendors overlap. One row with a tick for
  each place.
- Look and General fold into Tooltips and a new Windows page.

### 7. Restocking is one group

Mockup: `settings-3-restocking.png`

Keep in Stock, Restock What Sells, Raise When Sold Out, Stock From Sales,
Restock When Down To and Extra for Fast Sellers all answer "how many do I
keep". Group them under Restock What Sells, greyed when it is off, and
fold Stock From Sales and Raise When Sold Out into one box.

### 8. Six lists on the Queue page become one box

Mockup: `settings-4-queue-lists.png`

Keep in Stock by Profession, Changed When Sold Out, Never Made as
Sub-Crafts, Ignored Crafts, Ignored Items and Keep on This Character are
six stacked lists, mostly empty. One list with a box to pick which, each
name showing its count.

## Suggested order

3 first (small, fixes real first-run overlap, helps every addon), then 6
and 5 (rows only move), then 1 and 2 (the shared window, five repos), then
7, 8 and 4.

## For the other addons' threads

- Check whether the test runner prints every check. Tradeskills' was the
  only one over 20 KB, but the quiet runner here can be copied as is.
- All six CLAUDE.md files load into every thread, about 103 KB together.
  One key per character, Mute All Sounds, Writing for players, the standing
  rules, Window spots and the fold-in rule are repeated word for word in
  each. Keeping the full text in one repo and a two-line pointer in the
  others would cut that by more than half. This is the owner's call: the
  files say to keep them the same.
