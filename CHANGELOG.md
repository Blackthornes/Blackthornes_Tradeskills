# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

## 0.15.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

A big bug-fixing pass across the whole addon.

- A full scan that reads the whole auction house now marks items it didn't
  see as having nothing listed, so sold-out items stop showing old prices.
  It only does this when the scan really was complete and agrees with the
  last one; cut-short scans and quick searches leave prices alone.
- The last scan time is kept per realm and faction, so another faction's
  scan no longer counts as yours.
- Posting: new listings undercut the real cheapest rival, a second List
  click waits for the price check instead of doing nothing, and a price
  under the floor is refused before the dialog.
- Post Crafted only holds back as many items as a queued craft needs.
- Enchants and other crafts that make no item now count down the queue,
  and crafts that finish after the profession window closes leave it.
- Mail: sales held by the auction house settle when their gold arrives,
  and closing the mailbox quickly no longer forgets recorded mail.
- The Profit, Prices and Enchanting tabs no longer re-read hundreds of
  items on every redraw.
- Grey items get no auction lines in tooltips, only the vendor price.
- The header button reads Cancel scan while a scan waits to start.
- Many layout fixes: labels stay inside their buttons, headings follow the
  scrollbar, settings text wraps instead of being cut off, and notes and
  totals no longer overlap.

## 0.14.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- In the Craft queue pane beside the profession window, each recipe has
  - and + buttons around a box showing how many are queued. Type in the box
  to set the number. Keep in stock limits still apply.
- Queued recipes get a Craft button (Stop while crafting).
- A Clear queue button empties the queue; click it twice to confirm.
- While anything is queued, a Queued crafts list sits beside the pane, each
  entry with Craft and remove buttons.
- The pane's list keeps its order while you queue from it, so rows no
  longer jump around or disappear.
- Settings has "Sound when a scan finishes" (on by default) to turn off the
  scan chime.

## 0.13.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- While the mailbox is open, a tally above it counts up the gold you
  collect. When you walk away, a report shows the total, where it came
  from (sales, refunded bids, other mail), your best sale, what else sold,
  the items that came back, and today's and this week's totals. Beat your
  best haul or best sale ever and it celebrates. A one-line summary goes to
  chat too.
- Every mailbox visit is kept under Sales, "Mailbox visits"; click one to
  see its report again. `/bts haul` reopens the last report.
- Settings has "Report after collecting mail" (on by default) with a
  Preview button.

## 0.12.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- New Vendor Flips tab, next to Disenchanting: items other sellers have on
  the auction house for less than a vendor pays for them. It shows the
  profit, margin, vendor price, buy price, how many are listed and how old
  the price is. Pick a row to see the flip; the button or a right-click
  searches the auction house for it. Your own listings and anything the
  last scan didn't see are left out, and your minimum profit and margin
  apply. After a scan, chat names the best flip.
- `/bts vendordeals` says why each item is on the Vendor Flips tab.

## 0.11.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- New Disenchanting tab: weapons and armor on the auction house that are
  worth buying to disenchant, with the buy price, disenchant value, profit,
  margin, the Enchanting skill needed and how old the price is. It shows
  deals over your minimum profit and margin. Items your best enchanter
  can't disenchant yet stay listed with the skill in red. Right-click a row
  to search the auction house for it. After a scan, chat names how many
  deals it found and the best one.
- The tab only lists items the last scan (or a search since) actually saw,
  so sold and expired auctions drop off. It updates as soon as you close
  the auction house.
- Ready to sell and the craft queue pane have a header strip with a button
  that folds them down. Folded, the header shows a count, and the choice is
  remembered. Ready to sell shows its total worth and how many would sell
  at a loss; the craft queue shows its profit in green or red.
- The auction house bar is narrower and no longer covers the portrait.
  While a scan runs, a progress bar shows what it's doing; when it
  finishes, it says how many prices it updated.
- `/bts readysell` watches Ready to sell for 15 seconds and says why each
  item leaves or comes back. `/bts dedeals` says why each deal is on the
  Disenchanting tab.
- Fixed: Lesser and Greater Magic Wand and Lesser and Greater Mystic Wand
  no longer get a disenchant value, since the game won't disenchant them.
- Fixed: Ready to sell no longer flips between two different lists while
  the auction house is open.

## 0.10.0

For WoW: Forever (interface 16001). This version adds a file, so fully
restart the game after updating; `/reload` is not enough.

- With Blackthornes Farmer 0.8.0 or later loaded, each material you still
  need on the Gather tab gets a Set goal button. It makes a Farmer gathering
  goal for the amount you need and opens Farmer's Goals panel.
- Set all goals does the same for every material still needed, in list
  order. Farmer holds six goals at most, so any it turns down are named in
  chat with the reason.

## 0.9.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- When a material on the Queue tab's shopping list is cheaper for another of
  your characters to make, it shows in green, with that character, the cost
  and the saving on hover, a note under the list and a one-time chat line.
  It only suggests: the queue and shopping list don't change on their own.
  Bind-on-pickup materials are never suggested, since they can't be mailed.
  Turn it off in Settings under Suggest other characters.
- The queue now works out in-between crafts again a moment after you log in,
  so the character who can make a material gets it queued with its own
  materials on the shopping list, and one who can't goes back to buying it.
  Each newly queued in-between craft is named in chat.

## 0.8.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Fixed: characters that share a first name were treated as one character
  on the Characters tab, sharing recipes, bags and gold. Each character is
  now kept separately. Your existing records carry over to the first
  character that logs in under that name; nothing is deleted or merged.
- Characters that still look alike on the Characters tab show their level
  and class.

## 0.8.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- Disenchanting comes to the addon. The Profit tab gains a Disenchant column,
  green when breaking one beats selling it, and item tooltips show a
  "Disenchant value" line. Disenchant materials are priced at their lowest
  posting.
- A new Enchanting tab lists your crafts, the items in your bags, or the
  enchanting materials, with what each breaks into and whether that beats
  selling.
- A Disenchant button on the Enchanting tab breaks the best item in your
  bags with each click.
- The addon learns from your own disenchants. After ten of a kind, the
  chances and counts come from your own results instead of the built-in
  table. Chat says what each disenchant gave and what it was worth, and a
  new material or an unusually good result gets a message and a sound.
  `/bts delog` shows what was recorded.
- For a character that knows Disenchant, the Ready to sell list shows each
  item's disenchant value beside the listing price.
- `/bts de <item>` prints what an item breaks into.

## 0.7.0

For WoW: Forever (interface 16001).

- Hovering an item or craft anywhere in the addon now shows the game's own
  item tooltip, with the addon's lines under it.
- Item tooltips show the lowest posting from your last scan under the
  auction value, marked "(yours)" when the cheapest listing is yours, or
  "none listed" when nobody was selling.
- A new look to match Blackthornes Farmer: item icons beside every item and
  craft, a lit gold edge on the selected row, gold section headings and
  trim, and a margin bar on the Profit tab.
- Fixed: the Profit tab's Max button showed with nothing selected.

## 0.6.0

For WoW: Forever (interface 16001).

- When you are the only seller of a craft, it is now priced at the higher of
  market value and material cost plus your markup, instead of holding at
  market value forever. A rival listing still beats both. The Profit tab
  says "No competition" for these, and `/bts why`, `/bts price`, the Sell
  tab tooltip and the posting confirmation all name the rule.
- The posting confirmation is now four plain lines: Average Market Value,
  Lowest Market Posting, Posting at, and Do you wish to continue?, with one
  extra line only when the price is below what the item cost to make. When a
  lone low listing was skipped, it says so.
- Fixed: prices in the profession window's recipe list printed over recipe
  names and counts. A name that would run into its price is now cut short
  to fit.

## 0.5.1

For WoW: Forever (interface 16001).

- Fixed: a page-by-page scan stalled at page 8, threw away the pages it had
  read and left the progress bar stuck at 40%. A page that really never
  answers now keeps what was read and ends the scan properly.
- Fixed: a quick full scan that was cancelled, or gave up while waiting
  behind posting, still started the fifteen minute cooldown and blocked the
  next scan. The cooldown now starts only when the scan is actually sent.

## 0.5.0

For WoW: Forever (interface 16001).

- Queue All on the Profit tab: queues every craft in the list, after your
  filters and search, up to its Max on hand less what you already hold, have
  listed, have in the mail or have queued. Crafts with no Max on hand are
  skipped.
- A single low listing from one seller, under a third of the next listing
  up, is no longer the price to beat. Undercuts match the next real seller
  and it is left out of market value. Two or more low listings still count
  as a real price drop.

## 0.4.0

For WoW: Forever (interface 16001).

- Level Up: the recipe panel has a number box with Craft, Queue and Max.
  Craft makes that many right away, up to what your bags hold, and opens the
  profession window first if it is closed. While it runs the button reads
  Stop and the craft progress bar shows under it. Queue adds that many to
  the craft queue.
- Fixed: Lua errors inside dungeons from the cast bar, the sale alarm, item
  tooltips and the craft progress bar. A tooltip the game will not let the
  addon read now just skips its price line.
- The number typed in the recipe panel no longer resets when your bags
  change.

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
