# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

## 0.3.0

For WoW: Forever (interface 16001).

- Level Up tab: the recipes you know for a profession in levelling order,
  orange first, then yellow, then green, cheapest materials first within
  each colour. Grey is hidden unless "Show grey" is ticked. Rows add to the
  craft queue.
- Queue: when the next craft's profession window is closed, the craft button
  reads "Open <profession>" and opens it. The next click crafts.
- Craft progress bar in the Queue tab and the craft pane: the item, time
  left and how many more in the run. The game's cast bar is also kept on top
  of the addon's windows while a craft casts.
- Craft pane: a star on every recipe that still gives skill, a Level Up sort
  beside Profit and A-Z, an "Ignore max on hand" box that lets you queue past
  your Keep in stock limit, and a detail line that fits the row.
- Fixed: two List clicks a second apart during a scan could post at an
  unchecked price.
- Fixed: making an in-between craft you had also queued by hand removed the
  one you queued.
- Fixed: mailbox counting missed stacks from a partly taken mail, recorded
  some mails twice, and forgot recorded mail when the inbox was slow to load.
- Fixed: withdrawing from a bank bag counted that stock twice until your
  next bank visit.
- Fixed: the Post button counted its wait down twice between listings.
- Fixed: lists drew a half row past their bottom edge, the Scan button could
  stay disabled during a scan, a craft queued with the profession window
  open missed its first craft, and the shopping list skipped an alt's
  recipe.
- Chat lines, tooltips and labels read more plainly.

## 0.2.0

For WoW: Forever (interface 16001).

- Works out which crafts are worth making from auction house prices, with the
  full cost behind each one (`/bts why`).
- Scans the auction house, and learns prices from your own searches too.
- Craft queue with a shopping list and a posting list built around it.
- Posting panel beside the auction house and a craft pane beside your
  profession window.
- Tracks what is in your bags, bank and mailbox, what has sold, and what it
  really earned next to the estimate.
- Optional alarm when an auction sells.
- Your saved data now stays between sessions on the game's own saved
  variables, and the old macro storage is cleaned up on login.
- The version now shows when you log in.

## 0.1.0

The first upload to CurseForge.
