# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

## 0.28.2

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Ready to sell, beside the auction house, no longer covers buttons that
  stick out past the Professions window's right edge (some interface addons
  add a column of them). The list docks past them, and sits where it did
  before when there are none.

## 0.28.1

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- New look: the window wears a gold metal frame with corner gems, a round
  portrait holding a gold anvil, a title plate across the top and a red gem
  to close it. The tabs hang below the window like the game's own, and the
  one showing glows. Buttons are raised gold-edged metal, the main actions
  (Scan auctions, Add to queue, Post Crafted, Buy materials) are solid gold
  with dark lettering, and ticks, the search box and list rows glow gold
  under the mouse. A light runs round the portrait as the window opens and
  a glint slides along the rim; `/bts effects` Subtle drops the glint and
  Off stills everything. The sell list, craft queue, mail report and
  transfer dialog get the frame too.
- The "Send to your disenchanter" box no longer appears on the disenchanter
  itself.

## 0.27.0

For WoW: Forever (interface 16001). This version adds a file, so fully
restart the game after updating; `/reload` is not enough.

- A sale made while you're online goes on the Sales tab straight away,
  marked "gold waiting in the mail", and the real entry replaces it once
  the mail is read. This includes the sales the auction house announces
  with its own notice.
- A new **Still listed** view shows each character's listings from its last
  auction house visit, with when each one ends or that it has ended.
- Settings has **Hide sale messages in chat** (off by default).
- A **DEMAND** column on the Profit tab and a Demand line on item tooltips
  show High, Some or Low. Demand comes from your own sales once three of
  your listings of an item have sold or expired; before that it comes from
  how fast the auction house stock shrinks between scans.
- Queueing a craft with Low demand gives a one-time warning in chat.

## 0.26.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Shift-click any item row (Profit, Level up, Queue, the craft pane, Ready
  to sell and the rest) with the auction house open to search for that item.
  Right-click still queues.
- Items that don't stack, like Mana Oil, can be listed several at once: one
  click, one auction each, after the usual Yes. If the auction house only
  takes one, the addon goes back to one at a time for the rest of the
  session and says so.
- Another copy of the same item can be listed straight away, one per click,
  with no wait between copies. One check a few seconds after the last click
  counts them all and says "listed 3 x ...".
- Send gear to your disenchanter: set a **Disenchanter** name and **Mail
  gear up to** (greens by default, or blues, or purples) in Settings. At the
  mailbox a panel lists that gear with a **Send to** button that fills in
  the mail; you press Send. Soulbound and bind-on-pickup gear, and upgrades
  for your character when Blackthornes Equipment is loaded, are never listed.
- The craft queue pane beside the profession window docks clear of the
  profession tabs instead of covering them.

## 0.25.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Ready to sell, beside the auction house, can now leave items out. Each
  row has a red x at its right end ("Ignore this item"); clicking it takes
  that item off the list for good, on every character, and Post Crafted and
  Post ALL leave it alone too. It works by item, so ignoring one "Lead Band
  of the Wolf" ignores every Lead Band.
- Settings has a new Ignored items section under Ignored crafts, listing
  them A to Z in their rarity colour with a Restore button for each.
- `/bts readysell` says when an item is left out because it's ignored.

## 0.24.2

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The quick full scan waits up to 30 seconds for the auction house to
  answer instead of giving up after six and scanning page by page. If the
  answer comes even later, it's still used. `/bts scanstatus` shows how long
  the last quick scan took to answer.

## 0.24.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Vendor prices now come from the item's tooltip, everywhere the addon asks
  what a vendor pays: Vendor flips, Profit, posting floors, Disenchanting and
  the Bank view. On Forever the game's item info can still hold Classic's
  sell price, so Greater Magic Wand showed as a 15s 35c flip while a vendor
  pays 1c.
- `/bts sellprice <item>` shows both prices, so you can check any item in
  game.

## 0.24.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Click a column heading to sort the list by it. Numbers sort highest first
  and names A to Z; a second click reverses the order and a third goes back
  to the list's own order. The sorted heading is highlighted with a small
  arrow. This works on the Profit, Prices, Post, Queue materials, Gather,
  Disenchanting, Enchanting and Vendor flips tabs, and in the Bank view.
- The Buy materials button above a vendor no longer offers to buy what you
  just bought. It reads "Buying..." until the items reach your bags, then
  shows what is still needed, and it updates whenever your bags change while
  the vendor is open.

## 0.23.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- The Profit tab has an **Ignore** button beside Max in a craft's breakdown.
  An ignored craft leaves the Profit list on every character and Queue All
  skips it. The count under the list says how many are ignored, and a new
  Ignored crafts section in Settings lists them with a Restore button.
- Every queued craft remembers which character queued it.
- A new setting, off by default, lets your alts make sub-crafts: a sub-craft
  goes to whichever of your characters makes it for less and can mail it
  (same realm and faction, never anything that binds on pickup). The Queue
  tab and the craft pane say who makes it and who it's for, and logging in on
  a helper lists what it makes for whom. With it off, the shopping list
  recommends making it on the other character, as before.
- At the mailbox, a panel beside the mail window lists what this character
  should send the others for the queue. **Send to** fills in the mail for
  you; you still press Send. Sent items aren't offered again while they're
  on the way.
- A craft you queued that only an alt can make is offered back to you once
  the alt has made it.

## 0.22.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- Vendor-sold materials (vials, thread, flux, dyes, spices) cost the vendor
  price everywhere, even before you've opened a vendor. A price you see at a
  vendor still wins.
- With "Charge market price" unticked, the materials in your bags count as
  free once across the whole queue, not once per craft.
- Key bindings under Options, Keybindings, AddOns: open or close the window,
  and Disenchant the picked item.
- A new setting, off by default, opens the window when the auction house or a
  vendor opens and closes it with them.
- A SOUNDS section in Settings has a switch for every sound the addon plays.
  Two new sounds: a warning when your last free bag slot fills, and a chime
  when a run of two or more crafts finishes.
- Random-suffix gear is priced by its own suffix: Lead Band of the Wolf is
  checked against Wolf listings, not every Lead Band.
- Right-click a Post row, or Alt-click any item with the auction house open,
  to search the auction house for it by name.
- Disenchant value is the most likely result at its usual count. Rarer
  results are shown as a bonus and no longer add to the value.
- A craft only counts as worth disenchanting when it beats its materials.
- Disenchanting has a tick box to switch between auction deals and your bags.

## 0.21.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- A new look shared with Blackthornes Farmer. Windows wear a soft gold glow
  that flares as they open, and buttons, tabs, rows, menus, search boxes and
  checkboxes ease into their hover colours. One gold line glides under the
  tab you pick, and progress bars glide up. A new "Window effects" setting
  (Full, Subtle, Off) and `/bts effects` control it.
- Text fits everywhere: tabs are as wide as their names, money drops to
  fewer coins instead of ending in "...", long menus scroll, and dropdowns
  show their choice from the start.
- Upgrade arrows judge random-suffix gear ("of the Monkey" and so on) as the
  copy in your bags. The craft pane and sell list redraw their arrows when
  Blackthornes Equipment's weights or spec change.
- Pricing: a cheap listing holding most of the auction house's stock is now
  the price to beat. A quick full scan prices reagents per unit, so Wool
  Cloth is no longer stored at a whole stack's price. A craft is valued at
  what a vendor pays when that beats the auction house.
- An alt's crafts are priced the same as the crafter's, on a bank alt
  posting them and on the Profit tab with "All characters".
- Owned materials count as free only for the units you hold, so queued
  sub-crafts stay queued.
- Add to queue stops at Keep in stock.
- Buy materials uses the vendor when a few cheap auction units sit in front
  of dearer ones, and its button no longer lingers after the vendor closes.
- The shopping list says "in mail" for materials waiting in the mailbox.
- The last craft of a run leaves the queue even with the profession window
  closed.
- The mailbox report no longer counts returned letters, and stack sales
  find their item.
- Sales history no longer records a sale twice or misses a look-alike one.
- The listed count no longer takes a returned stack off twice, and an alt's
  old auction readings expire after a day.
- The bank view's gold total is right, and grey items are valued at vendor
  price.
- The Disenchant button only follows the tab on screen, and picks only items
  worth more disenchanted than sold.
- A typed LIST price counts when List is clicked, a price under cost is
  refused before the confirmation, and closing the auction house takes the
  confirmation down.
- `/bts import` with a code too long for chat opens the paste window instead
  of importing it cut short.
- The missing saved data warning stops on every character after
  `/bts db fresh`, not just the one it was typed on.
- The minimap button starts at 170 degrees, clear of Farmer's; a button you
  already moved stays put.
- Settings: "Confirm before each listing" is gone, since it never did
  anything. Every listing is still confirmed.
- Fixed: Craft buttons ignored clicks after the Open profession button moved
  between tabs.
- Fixed: the Settings page grew taller each time it drew.
- Fixed: a loot link the game hides inside instances could raise an error in
  the disenchanting log.

## 0.20.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Shopping list beside the profession window: under Queued crafts you now
  see every material the whole queue needs, with have and need, a progress
  bar, its price or where to get it, and a To buy total. The Hide list /
  Shopping button at its foot hides and shows it.
- Shopping list at the auction house: Ready to sell has a Sell / Buy switch.
  Buy shows the same list in the panel already beside the auction house.
  Each material you're still short of that no vendor sells gets a Search
  button that looks it up on the auction house.
- Ready to sell no longer covers the craft queue when a profession and the
  auction house are open together. It docks past the queue, or steps aside
  when the screen has no room, and the queued crafts move out of its way
  too.

## 0.19.0

For WoW: Forever (interface 16001). This version adds a file, so fully
restart the game after updating; `/reload` is not enough.

- With Blackthornes Equipment installed, gear that's an upgrade for the
  character you're playing gets the green upgrade arrow on its icon in every
  Tradeskills window, the same arrow Equipment puts in your bags. Without
  Equipment nothing changes. "Upgrade arrows on gear" in the settings turns
  it off.
- Returned mail is valued the same way as everything else: grey items at
  vendor price, the rest at the higher of auction and vendor.
- Ticking "Queue sub-crafts" updates the queue straight away.
- The minimap button follows the cursor on a scaled minimap.
- Fixed: the Disenchant button could stop working after a fight that began
  right at login.
- Fixed: a tiny loss showed as a red "-0c" instead of 0c.
- Fixed: `/bts top 0` showed an empty heading instead of one craft.
- Profit, Characters and Prices lists keep the same order for ties.

## 0.18.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- The Characters tab has a new Bank view (switch at the top, or
  `/bts bank`). It lists every item in all your characters' banks, with a
  search box, a character filter, and sorting by worth, count or name.
  Tick "Bags too" to add bags. Point at an item to see who holds it.
- The side pane shows each bank's worth and when it was last read, or,
  once you pick an item, who has it and how many.
- A character's bank shows up once they've opened it with the addon
  installed. Characters who haven't show "Bank not opened yet".

## 0.17.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating. This release also carries everything in 0.17.0.

- Fixed: at the auction house, opening your character window (C) put it
  under the Ready to sell list, which covered it completely. The list now
  moves over beside the character window while it's open and slides back
  when it closes. On a screen too narrow for all three, the list steps
  aside until the character window closes. The spellbook and other game
  windows that open in the same place work the same way.

## 0.17.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The Disenchanting tab can now show the items in your bags. Pick
  "Show: Items in your bags" at the top left. Each item lists how much more
  disenchanting pays than selling, what it disenchants into, what it
  sells for and how many you have.
- The best item is picked for you. The Disenchant button breaks one per
  click, and the next item takes over when that one is gone. A running
  total shows what you've disenchanted this session, and "All done!" shows
  when your bags are clear.

## 0.16.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Fixed: a quick full scan read commodity prices (cloth, herbs, ore and
  the like) as if each whole row cost the price of one, so they came out
  far too high. For example, Linen Cloth showed about 16 times its real
  price. Each commodity's market value starts fresh on your next quick
  scan; its price history is kept.
- A single cheap listing no longer sets the material cost, the only-seller
  price or the tooltip's lowest posting.
- Enchanting profit takes the auction house cut off.
- Buy materials skips anything rivals sell cheaper on the auction house.
- With All characters ticked, the Profit tab's profession list includes
  your other characters.
- A craft counts down the queue once per cast, even when it makes extra
  items. The queue says "made 1 of X, 4 left".
- Crafts from a profession you dropped are hidden (not deleted).
- WHO shows first names, adding the last name's initial when two
  characters share one.
- The listing confirmation shows the item's icon and the price in gold.
- A scan stopped at the 40-page limit no longer counts as a full scan.
- Two sales that look alike at the mailbox now count as two.
- A fresh install gets a welcome message instead of a saved data warning.
- `/bts help` lists the everyday commands; `/bts help all` lists them all.
- The Prices tab search finds items the game hasn't loaded yet.
- The cast bar only moves for crafts, not for things like Hearthstone.
- Buttons that need a second click get a red border while armed.

## 0.15.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The + and - buttons in the Craft queue window now change the queue the
  moment you click, and the Queued crafts list keeps up with quick clicks.
  They used to lag about a second behind.
- Quick clicks on + no longer queue past your Keep in stock limit.

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
