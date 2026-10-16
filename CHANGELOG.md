# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

## 0.61.0

For WoW: Forever (interface 16001). A file was added and the TOC changed, so
restart the game fully after updating (`/reload` is not enough).

- **Find a material:** the Disenchanting tab can show what gave you an
  enchanting material before, and the ways to get more: break what you
  carry, buy and break, make and break, or farm and break with Farmer's
  record of your own kills. Each shows its odds and cost for each one.
- **Overcutting:** post just under a big stack when a few cheap listings
  sell first. Off until you tick it on the Pricing page.
- **List Next:** the button says what its next click does, and its hover
  shows the next stack.
- **Raise When Sold Out:** Keep in stock also comes back down by 1 after 3
  unsold rounds in a row, never below where it started. Settings > Queue
  lists what it changed, each with Reset.
- **Enchants for your gear:** with Blackthornes Equipment, the Level Up tab
  shows a green arrow and "For you" on an enchanting recipe that beats what
  you wear.
- **Profit:** the auction house deposit is no longer taken off, since it
  comes back when the item sells.
- **Favors and Writs:** Merchant's Favor rewards and the Artisan crates are
  corrected.
- **Auction house drawer:** the Post Crafted button is off for now.
- **Bug fixes:** various fixes to Tradeskills.

## 0.60.0

For WoW: Forever (interface 16001). Files were added and the TOC changed, so
restart the game fully after updating (`/reload` is not enough).

- **Your time view:** on the Profit tab, each craft you know shows gold an
  hour for farming the materials and crafting, and for farming them and
  selling them as they are, plus the profit for buying them and crafting.
  Farming time comes from Farmer, from your own kills and gathers. Right-click
  a row or use Queue 1 to queue a craft.
- **Random suffix prices:** each suffix seen at the auction house keeps a price
  of its own. It shows on tooltips ("This one"), Post, Your auctions,
  Disenchanting and a Random suffixes row on the Prices tab.
- **Profit tab:** the least needed columns step aside when they don't fit.
- **Shopping lists:** a search runs again after you buy.
- **Bug fixes:** various fixes to Tradeskills.

## 0.59.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- **Fast listing:** List all checks every price on your Sell list with one
  search. After that each click lists the next item straight away, with no
  Yes or No box, while its price is fresh. Items that look risky still ask.
  "Fast listing" on the auction page of Settings, on unless unticked.
- Various fixes to Tradeskills.

## 0.58.0

For WoW: Forever (interface 16001). A file was added and the TOC changed, so
restart the game fully after updating (`/reload` is not enough).

- **Enchant costs on tooltips:** an Enchanting recipe's tooltip shows its
  materials with the total cost, what you are short and which of your
  characters know it. "Enchant costs on tooltips" on the Look page.
- **Auction house drawer:** the Buy view has a Search all button that looks
  up everything on the list at once. Where the game takes one search at a
  time it steps through them with "Next 2/5". A search of a whole list
  fills in the buy quantity the way the Buy tab does.

## 0.57.0

For WoW: Forever (interface 16001). Files were added and the TOC changed, so
restart the game fully after updating (`/reload` is not enough).

- **Stats tab:** a new tab for one item at a time. The left lists what you
  craft, star and sell, sold most in 30 days first, and a search finds any
  priced item. The right shows the item you pick: worth now against a week
  ago, profit each, sold a day, sold this week, the price graph, and cards for
  the cheapest times by day and hour, where each sale goes, your listings,
  sales by week, listings at each scan, price by source, the last 90 days,
  who else sells it, how fast yours sell and money by method. `/bts stats
  [item]`.
- **Auction house drawer:** its switch has two new choices. Lists keeps named
  shopping lists, with a Search for everything still needed, per-item owned
  counts and prices, and an add box that takes names, "Peacebloom 40", item
  IDs and Shift-clicks. Auctions lists your auctions with the undercut ones
  first, a Cancel button on each and a Cancel next button.
- **Price trend:** the Prices tab has a sortable TREND column against the
  last 7 or 14 days, and item tooltips show it; "Price trend on tooltips"
  on the Look page turns that off. The price graph has a 14 Day view.
- **Tabs:** the main window's tabs read Profit, Queue, Gather, Post,
  Disenchanting, Level Up, Favors and Writs, Prices, Stats, Sales,
  Characters, Settings.
- **Craft next:** it makes the ready craft that frees the most bag slots
  first. "Craft what frees bag space first" on the Queue page turns it off.
- **Limited-stock vendor materials:** they keep their Search button on the
  Buy list and the Queue tab so they can be bought at the auction house too.
- **Ignore crafts from the pane:** Ctrl-right-click a craft in the pane
  beside the profession window to ignore it there and on the Profit tab;
  Settings > Queue > Ignored crafts restores it.
- **Butler:** it can buy the queue's materials at a vendor and search the
  auction house for the items open quests need.
- **Bug fixes:** several fixes for shopping lists, the Auctions view, the Stats
  tab and sort headings.

## 0.56.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Duration in the auction house drawer:** a box at the foot of the Sell
  view picks how long your listings stay up (2, 8 or 24 hours). It is the
  same choice as on the Post tab, so a pick in either shows in both.

## 0.55.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Stock from your sales:** with Keep in stock at 0, Queue All and Restock
  what sells keep about two days of what sold for you this week. The Profit
  tab's STOCK column now shows that number, dimmed, as held and kept, and
  "Stock from your sales" on the Queue page turns it off.
- **Raise it when it sells out:** it now starts unticked. Tick it on the
  Queue page to have Keep in stock go up by itself.

## 0.55.0

For WoW: Forever (interface 16001). Files were added, so restart fully
after updating.

- **Keep in stock by profession:** Settings > Queue has a list of your
  professions, each with its own Keep in stock number. An item's own number
  still wins, then its profession's, then the usual one. The Profit tab
  greys a number that comes from the profession or the usual setting and
  says where it comes from, and an x puts an item back to that.
- **Raise it when it sells out:** when every copy of a craft you listed
  sells before its listings would have run out, its Keep in stock number
  goes up by 1, once, at your next full look at the mailbox. A gold chat
  line and a sound say so. It never lowers a number and leaves items with
  no limit alone. "Raise it when it sells out" on the Queue page turns it
  off.
- **Sales details on item tooltips:** under the Demand line: Sold a day,
  Listed now with the age of the scan, Last 7 days as small bars with a
  trend, and what you sold this week. "Sales details only with Shift" on the
  Look page shows them while Shift is held.
- **Vendor, Make or Buy:** on Level Up, a sub-craft's button picks how its
  item is got when another craft needs it. Buy prices it off the auction
  house instead of a vendor that only sells a few at a time, and Make
  always crafts it.
- **Vendor materials:** a material a vendor sells without a stock limit
  (thread, dyes) goes to the vendor on the shopping list, the Gather and
  Queue tabs and the vendor's Buy button, even when it is listed for less.
  A new Auction house setting, off by default, offers the auction house for
  them again.
- **About page:** Settings has an About page with the version, the Discord
  invite, how to report a bug and your other Blackthornes addons. What's New
  can also show one-time cards from an addon, and shows new features only.
- **Butler:** its job list puts a mailbox visit first when mail is waiting,
  names which missing materials a vendor sells, shows what the trainers'
  recipes cost to learn, holds back an item when the auction house pays well
  under what it costs to make, and marks greens worth breaking to level your
  Enchanting.
- **Rows:** a long craft name that wraps onto three lines gets a taller row
  instead of covering the names above and below it.

## 0.54.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- **Favors and Writs:** the Deals tab is now Favors and Writs (Gunst und
  Aufträge on a Deutsch client) and opens on Merchant's Favor. Its Show
  menu has Merchant's Favor and Craftsman's Writs, and a scan no longer
  prints the vendor flips line. The flips are put away for now, with their
  settings kept.
- **QTY column:** beside AGE, how many other sellers listed at the buy
  price or less in the last scan. One alone shows in amber. It sorts like
  the other headings.
- **Auction house drawer:** the sell list and the Scan bar are now one
  drawer beside the auction house, the window's full height, with Scan,
  Post Crafted and the scan status in its header and a close gem that
  hides it until your next visit. Rows are dark glass with a quiet List
  button, names are never cut short, and one **List all** button at the
  foot lists the most valuable stack each click.
- **Faster listing:** a different item can go up about a second after the
  last one instead of waiting about five seconds. Up to four listings are
  checked at once, each still confirmed on its own.
- **Leave form:** in a travel or shapeshift form (any druid form or Ghost
  Wolf), Craft next on the Queue tab and Level Up's Craft button read
  Leave form. The first click leaves the form, the next one crafts. It
  can't be done in combat, and the button says so.
- **Tailoring:** shows in the Level Up and Profit menus again, with its
  crafts, even when the game gave its skill under its other ID.
- **Level Up:** with Learn next ticked, the least needed columns step
  aside while the list is too narrow, so recipe names always have room.
  Your column choices are kept. Opening Level Up no longer throws a "C
  stack overflow" error.
- **Profit graphs:** drawn at their real size from the first look.
- **Mail:** part of a stack is split into its own bag first, so herbs in a
  herb bag can go in a mail when your other bags are full, and a chat line
  says when a mail Butler filled left something out.

## 0.53.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- **Transmute cooldowns:** any transmute of a ready cooldown can be made,
  and the one Butler names is the one you have the materials for. A
  character you removed keeps its cooldowns quietly instead of being named
  as "Player", and a fight right after login only delays the first check.
- **Learn next:** the materials Queue materials puts on the list stay
  there until you remove them, also when you already carry or bank some.
  On a Deutsch (German) client it finds the trainer in your own zone.
  Artisan recipes (Enchanting 230 and up, Engineering 260) are listed as
  taught by an Artisan trainer, and recipes with no skill data drop off
  once you're well past them. Show the way names the recipe in chat on a
  Deutsch client, even before the item has loaded.
- **Craft requests in Trade:** a player who shares your first name is
  heard; only your own lines are skipped.
- **Prices:** a scan records what the auction house shows, never a
  TradeSkillMaster or hand-set price, and the price API for other addons
  can't raise an error.
- **What's New:** closing the window while holding its scroll bar lets go
  of it.

## 0.53.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **What's New window:** the first time the game loads after an update,
  one window shows what changed in every Blackthornes addon that was
  updated, with dark glass cards and a little motion. "Motion" in Settings
  turns the movement off, "Show after updates" turns the window off (off
  in one addon is off in all of them), and the `whatsnew` command or a
  Settings button opens it any time.
- **Profession cooldowns:** Tradeskills keeps every character's
  transmute, Mooncloth and Salt Shaker cooldowns. Chat says once when one
  is ready, the Characters tab shows how long each has left, and
  `/bts cooldowns` lists them all. Blackthornes Butler shows a ready one as
  a job.
- **Learn next:** the Level Up tab lists the trainer and vendor recipes
  that would raise the skill now, cheapest first, with where to get each
  and a Show the way button that pins the trainer or vendor on the map
  (or uses TomTom when it's installed). A "Learn next" tick box turns it
  off.
- **Forever's own recipes:** the recipe book uses Forever's skill levels
  (about 600 recipes moved) and its materials for 127 recipes, so costs
  for recipes nobody has learned yet match the game.
- **Craft requests in Trade:** ticked, chat says when someone in Trade
  asks for something one of your characters can make. Off by default.
- **Shift-click to search:** shift-clicking any item anywhere in
  Tradeskills searches the auction house while it's open, or links the
  item in chat when it's closed.
- **MOVES per day:** the Prices tab's MOVES column, its detail line and
  the profit analysis use the same per-day measure as Demand, so how often
  you scan no longer changes it.
- **Flip warning:** the Flip panel on the Deals tab says that flipping is
  risky and to spend only what you can afford to lose.

## 0.52.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **Deutsch:** on a Deutsch (German) client, every Tradeskills window,
  tab, button, tooltip and chat line is in German. English clients see
  exactly what they saw before.
- **Prices from TradeSkillMaster and Auctionator:** with either installed,
  its prices fill in items that neither you nor your guild have scanned,
  so Farmer, Equipment and Butler price them too. Your own scans and guild
  prices always come first, then TradeSkillMaster, then Auctionator (from
  your own Auctionator scans). "TSM prices" and "Auctionator prices" under
  Other price addons on Settings > Sharing turn each off; the TSM row says
  whether it is filling anything. TSM's prices may not cover Forever
  realms; when they don't, nothing changes.
- **For addon authors:** `BlackthornesTS_API.GetPrice(item)` gives the
  price the Blackthornes addons use, in copper, and
  `BlackthornesTS_API.GetPriceAge(item)` how old this account's own scan
  of it is. Both take an item ID or a link and never raise. The README's
  "For addon authors" section has the details.
- **Shorter scan line:** listings left out for being priced far too high
  are now one short line, "2 listings ignored: priced above 214,748g".
- **Fixes:** an old record of the character you're on, kept from before
  last names, is now set aside at login whatever it was saved under, so
  its items are counted once and its bags are read live. Nothing is
  deleted. A copy played from a checkout shows its real version instead
  of "dev build".

## 0.51.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **Profit by method:** a new view on the Sales tab, with a Period menu
  like Gold in and out, splits your profit into Crafted, Flipped,
  Vendored, Disenchanted and Other, each with its items beneath (best
  first) and the totals in the side panel. Flips, vendor sales and
  disenchants count from this version on. An item with no known cost
  counts as all profit, and the panel says how many.

## 0.50.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **Pick the sale sound:** Settings > Sounds > "An auction sells" now
  offers Cash register, Coins, Raid warning or Off, with a Play button.
  An old cash register is the new default.
- **Sister addons:** a few seconds after login, one chat line names the
  Blackthornes addons you don't have yet and what each one adds. It shows
  once per account, comes back only for an addon it has never named, and
  never names one you have installed but turned off. "Sister addons" in
  Settings turns it off in all of them at once.
- **Fixes:** with no Waylaid crate or writ on the auction house, the
  CRATE and WRIT columns are blank and say "none listed", so totals and
  cost per favor or reputation no longer count something you can't buy.
  Enchanters, recipe skill lines, Recipes to learn and item charges now
  work on German and other non-English clients.

## 0.49.2

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- **Fixes:** on the Disenchanting tab, buying the last item listed at a
  price now moves its row to the next known price, or drops the row when
  none is left, and a search by full name that finds nothing listed drops
  the row too, so the tab no longer offers deals that are already gone.

## 0.49.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- **Fixes:** Demand read from the auction house's stock no longer depends
  on how often you scan. It is now the share of an item's stock that sells
  a day (High at 30%, Some at 10%), so scanning every minute or once a day
  gives the same answer, and the tooltip says "N% of its stock sells a
  day". An empty scan no longer counts as the whole stock selling out.
  Your own sales still decide once three of your listings have ended.

## 0.49.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **A warning before you overpay:** when you buy a shopping list material
  at the auction house and that many now costs well over what the list
  said, a line under Buy Now shows the cost now, the list's estimate and
  how much more, in coin colours. It's a line, not a popup, and Buy Now
  still buys. "Warn when buying costs more" on the Auction house page of
  Settings sets how far over (25% to start; 0 turns it off).
- **Smoother crafting:** with the Queue tab open, a finished craft no
  longer prices the whole queue and rebuilds the shopping list several
  times over, which could freeze the game for a moment. A new speed check
  (`/bts perf`, or Settings > Data) lists the slowest work since login.
- **Fixes:** a sub-craft another character already made and sent to
  the crafter (on its way, in the mailbox or in the bags) now leaves the
  queue, along with the materials it asked for. A character that also
  had an old saved record from an earlier version is now listed once
  everywhere, instead of twice. Nothing
  is deleted; the old record is kept and its queued crafts and shopping
  list lines move to the character.

## 0.48.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- **Farmer goals follow the queue:** a goal made with Set goal (or Set all
  goals) now grows when you queue more and goes away once the queue no
  longer needs it, with one chat line saying what moved. A goal you change
  yourself in Farmer is left alone. "Goals follow the queue" on the Queue
  page of Settings turns it off.
- **Keep in stock learns from your sales:** with no number typed, Queue All
  keeps about two days' worth of what sold for you this week, and the
  detail pane says how many it learned. When one of your auctions sells,
  another is queued straight away, unless the craft loses money or "Wait
  until it runs low" is holding back. A typed number always wins. "Restock
  what sells" in Settings turns the auto-queue off.
- **A disenchanter picked for you:** with the Disenchanter box empty, your
  character with the most Enchanting is picked, and the box shows their
  name. A typed name still wins, and "Pick one for me" turns it off.
- **Crafted gear stays with you:** the Mail page no longer sends gear a
  profession makes to the disenchanter.

## 0.47.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **Bought to disenchant:** anything you buy on the auction house after
  searching for it from the Disenchanting tab is marked "bought to DE",
  and chat says so. The mark follows the item through the mail, the bank
  and on to your enchanter. On the tab's "Items in my bags" list, marked
  items come first with a violet tag and are broken first by the
  Disenchant button. Right-click a bags row to mark or unmark it by hand.
- **Fixes:** NEW on the Deals tab now only marks real new deals, even with
  "Only deals over my minimums" unticked. The mailbox never offers a mail
  to the character you're on, and no longer skips an alt who shares your
  first name. The Queue tab and its footer price bought materials up the
  auction listings, the same as To buy. On Ready to sell's Buy view, the
  summary uses the full width.

## 0.46.0

For WoW: Forever (interface 16001). No files were added, but the emblem
art changed, so restart the game fully once after updating to see it
(`/reload` is enough for everything else).

- **Material costs go up the listings:** a craft or shopping list that
  needs 20 of a material prices them going up the auction listings from
  your last scan (3 at the cheapest, then the next price up), not all 20 at
  the cheapest. Your own price settings still win.
- **What you paid:** after an auction house buy, the shopping list shows
  what you actually paid in place of the estimate, in amber when it came to
  more than about 25% over what the list said. The tooltip gives both.
- **Deals: New only:** deals first seen in your latest scan carry a gold
  NEW tag, and a New only tick box lists just those. A deal's tooltip says
  when it was first seen.
- **Ready to sell: Hide losses:** a Hide losses box on the auction house
  Sell view leaves out the red rows, and the summary says how many are
  hidden. Off by default.
- **Alt mail sends only what's needed:** mailing materials to an alt sends
  just the amount its queue needs, split off into an empty bag slot, rather
  than the whole stack. With no free slot, the mail panel asks you to free
  one.
- **Full character names:** characters are named in full (first and last
  name) everywhere, and a mail is never planned for the character you're
  playing.
- **New emblem:** the window's emblem is redrawn as a hammer striking an
  anvil, with sparks.

## 0.45.2

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **Fixes:** in the Blizzard window style, the tab showing now wears the
  game's tab art, lit, with a white label, instead of a dark bar with gold
  corners. The Reload buttons for Text size and Window style sit under
  their setting, the same way in all four addons.

## 0.45.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- **Fixes:** gold mailed between your own characters no longer shows as
  mail income and spending on the gold chart, and the Today chart works in
  half-hour time zones. An auction buy taken from the mail with full bags
  stays off the shopping list, and a buyout lost to a quicker buyer is no
  longer confirmed by the next gold that leaves. Materials mailed to your
  own alt aren't counted twice, and materials just bought aren't still
  queued as sub-crafts. Buy materials now counts stacks. The Disenchant key
  does nothing in combat instead of casting at an old bag slot. Silly
  quantities typed into a craft box are refused. Guild price sharing keeps
  the save from growing without end, and one guildmate's stuck transfer no
  longer blocks the rest. The bank, vendor and mailbox are read once per
  burst of events instead of once per event. The Blizzard window style's
  portrait ring stays silver on every client.

## 0.45.0

For WoW: Forever (interface 16001). A file was added, so restart the game
fully after updating (`/reload` is not enough).

- **Window style:** Settings > Look & sound has a new Window style choice.
  Titanforged stays the default. Blizzard gives the windows the game's own
  look: grey colours, a silver rim, the game's close button, buttons, tick
  boxes, tabs and scroll knobs, plain list rows and no glows. A change takes
  effect after a reload, and a Reload now button appears when it's needed.
- **Calmer list rows:** rows in the tables look like dark glass, every other
  one a shade lighter with a fine line under each. The gold glow shows only
  on the row under the mouse.
- **Queue: wait until stock runs low** (Settings > Queue, off by default): a
  profit craft is only suggested again once what you hold drops to the
  number you pick, then it's made back up to Keep in stock.
- **Queue: fast sellers keep more** (off by default): items your own sales
  show selling well get extra room on their cap.
- **Auction house buys:** the number needed now stays in the Quantity box
  instead of jumping back to 1.
- **Bank age on the Queue tab** shows your last real bank visit. Bank events
  that fire away from a banker no longer replace your saved bank with an
  empty one.
- **Fixes:** a sub-craft queued for another craft no longer counts as stock;
  Keep in stock no longer grows each time you edit it; a broken shared
  message can no longer freeze the game; sold-out items aren't shared as
  fresh guild prices, and items with no price no longer stop the share; the
  auction house sell lists only rebuild when something in them changed; and
  six fixes to the Blizzard window style.

## 0.44.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Crafted upgrades from Blackthornes Equipment** land on the Queue tab:
  gear you or an alt can make is queued as a craft, gear you still have to
  learn has its materials put on the shopping list, and gear nobody on your
  account makes goes on the list itself, to buy from a vendor or the auction
  house. Each line has a small x to take it off and says which upgrade it's
  for, and it goes by itself once you own or wear the gear or its craft is
  queued, so nothing is bought twice.

## 0.43.0

For WoW: Forever (interface 16001). A file was added, so restart the game
fully after updating (`/reload` is not enough).

- **Auction buys waiting in the mail count toward the queue.** "Still needed"
  drops the moment a purchase goes through, the row shows "(12 in mail)" while
  more is still needed, and the tooltip says how many are waiting. Once you
  take the mail they're counted in your bags instead, never twice.
- **Merchant's Favor bundles are priced from what can really be bought.**
  Copper Modulators, Bronze Tubes and six other engineering parts use the
  auction house unless you've seen a shop sell them, a limited-stock shop no
  longer prices a bundle when there's a listing, and vendor-priced bundles
  are marked "(vendor)".
- **Gold per hour only for recipes you know:** TIME and GOLD/HR read "--" for
  recipes you can't craft, on the Profit tab and in the craft pane.
- **The version number** shows under the scan status at the top of the window
  and in the minimap button's tooltip.
- **Smoother crafting:** a run of crafts no longer re-reads every recipe and
  rebuilds the craft pane on each craft, which made the game hitch about once
  a second.
- **Less CPU** at the auction house, for prices and for addon messages, and
  cheaper tooltip reads when you hover items.
- **Buy instead works again:** it takes every row of that sub-craft off the
  queue and puts the item on the shopping list.
- **Settings:** the "Recipes to learn", "Test vendor selling" and "Sample mail
  report" buttons have their own rows instead of spilling into the next
  column, and they show up in Find a setting.

## 0.42.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **Craftsman's Writs** on the Deals tab: the Show menu's new third choice
  lists all 150 writs by what one point of trade camp reputation costs (the
  writ plus the item it asks for, bought or made, whichever is cheaper). Pick
  a **Goal** (Friendly to Exalted) and the side panel says how far you are,
  how many writs of each kind it takes, and the cheapest and quickest way.
- **Craft time and gold per hour.** The Profit tab's new **Per hour** tick box
  adds TIME and GOLD/HR columns, the craft pane shows the craft time and per
  hour rate, and the Disenchanting tab gets a GOLD/HR column.
- **Choose your columns:** right-click any list's column headings to hide the
  ones you don't use, or use Settings > Look & sound > Columns, with a
  **Show all** button.
- **Price graph:** dim bars show how many were listed each hour, and a dashed
  line marks the average price.
- **Level Up follows the Profit tab's "Profit:" choice** (Best, AH, Vendor or
  DE) when it counts what a craft gets back.
- **Turn undercut off** from Settings > Pricing: one button lists at the
  cheapest rival's own price, and clicking it again puts your old amount back.
  The default stays 1c.
- **Sub-crafts from alts:** with **Sub-crafts only** ticked, Level Up lists
  every character's sub-crafts with the alt's name beside them, and the
  Make / Buy button shows on every craft that makes an item.
- **Recipes show the skill Forever asks for**, read from the recipe's own
  tooltip, on Level Up and the recipe tooltip. Several Leatherworking patterns
  moved on Forever (Raptor Hide Harness needs 140, not 165).
- **Deals uses what Forever's vendors really pay**, learned each time you sell.
  Minor Wizard Oil now pays 1s, so it's no longer shown as a profitable flip,
  and charged items nobody has sold yet aren't offered as flips.
- **Disenchanting:** green weapons of item level 21 to 30 now show Greater
  Magic Essence, which is what Forever gives, instead of astral essence.
- Fixed: Level Up's skill colours no longer turn grey for a while after
  logging in or a loading screen.
- Saved data is never written into the game's own settings any more, so it
  can't harm them if the game ever fails to load the addon's data.

## 0.41.0

For WoW: Forever (interface 16001). A file was added, so restart the game
fully after updating (`/reload` is not enough).

- Any craft can now be marked **never made as a sub-craft**: crafts that
  need its item buy it instead, in every cost, the queue, the shopping
  list and the alt suggestions, on every character. The craft can still be
  queued and sold on its own. Mark one with the new SUB-CRAFT Make / Buy
  button on the Level Up tab (with a **Sub-crafts only** tick box to list
  just those), or with the x on a queued sub-craft. Settings > Queue >
  **Never made as sub-crafts** lists them with what each costs to buy and
  an **Allow** button to undo it.
- Set your own price on **Ready to sell**: click a row's price to open a
  small "Your price" window with the price each, how many and the total,
  all editable and kept in step. It shows the suggested price with a
  **Use suggested** button, how far under market you are and roughly what
  comes back after the cut. **List** lists it at that price; **Keep as my
  price** saves it on the Prices tab, otherwise it lasts the session. The
  window grows to fit its notes at any text size.

## 0.40.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- New **Merchant's Favor** view on the Deals tab (**Show: Merchant's
  Favor**). It lists every Waylaid Crate, cheapest favor first, with the
  crate's auction house price, its cheapest bundle, the total after the
  silver the turn-in pays back, and what one favor costs. Click a crate to
  see every bundle it takes, the cheapest in green, with buttons to search
  for the crate or the bundle. **Skip bundles over a stack** (on by
  default, also in Settings) leaves out bundles bigger than one stack.
- Crate rewards are learned from the game at each turn-in, account wide.
  Until a turn-in has been seen, the values players reported are used and
  labelled as reported. Artisan crates show "?" and sort last.

## 0.39.0

For WoW: Forever (interface 16001). A file was added and the TOC changed,
so restart the game fully after updating (`/reload` is not enough).

- The **Disenchanting** tab is back as its own tab, just as it was before
  0.37.0: auction house items worth buying to disenchant, "Items in my
  bags" with the one-click Disenchant button, and its tick boxes.
  **Deals** keeps the vendor flips: its Sell to menu offers AH and Vendor,
  with the VIA column and the other way's profit in the side pane. The
  Profit tab's Disenchant button and the queue's AH/DE/Vendor marks are
  unchanged.
- Item names on the Disenchanting and Deals tabs now show in their rarity
  colour (green, blue, purple and so on), as on the Queue and Profit tabs.
  Many were plain white because the game no longer had the item in its
  cache.

## 0.38.2

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The Profit tab's AGE column now shows how old the price is on rows best
  disenchanted or sold to a vendor, instead of repeating "DE" or "vendor".
  A disenchant row shows the age of the scan for its most likely result,
  in the warning colour when that scan is stale. A vendor row shows a
  dash, since vendor prices never go out of date.

## 0.38.1

For WoW: Forever (interface 16001). Files were removed, so restart the game
fully after updating (`/reload` is not enough).

- The mailbox **Take** buttons and the movable **Tradeskills mailbox** from
  0.38.0 are off for now. The Take strip covered the game's Send Mail tab,
  so both are coming back after more testing. The game's mailbox works as
  it did before 0.38.0, and so do the queue's mail panel and "Take next
  batch". Your settings for them are kept for when they return.

## 0.38.0

For WoW: Forever (interface 16001). Files were added, removed and renamed,
so restart the game fully after updating (`/reload` is not enough).

- New **Sharing** settings. Name a character on your other account (and
  name this one from that side), and while both are logged in on the same
  realm they swap characters: recipes, bags, bank and mail, gold and
  auctions, each with its own Send box. They show up wherever your alts
  do, marked "other account" on the Characters tab. Use first and last
  names, as Forever needs.
- **Guild prices**, on by default: Tradeskills shares a fresh scan with
  guildmates at most once an hour, and uses theirs only for items you
  haven't priced or whose price has gone stale. Turn it off in Settings or
  with `/bts share guild off`; a choice you already made is kept.
- Each queued craft now has an **AH / DE / Vendor** button, starting on
  whichever pays most. Click it to change, right-click to go back to the
  best. Items the queue makes for DE or Vendor are marked as they're made.
- **Disenchant next** on the Queue tab (off by default, in Settings) aims
  the Disenchant button at the next item marked DE, one cast per click.
  **Sell marked** on the vendor window sells Vendor-marked items, one click
  per stack and at most 12 per visit, so the buyback can undo any sale.
  Neither ever touches anything blue or better, anything worn, or anything
  the queue didn't make.
- New **Deals** tab replaces Disenchanting and Vendor Flips: every auction
  house buy worth making, with a "Sell to" menu (AH, DE, Vendor) and a VIA
  column saying which way pays most. The Enchanting tab is gone, but its
  parts moved: the Profit tab has the Disenchant button and a "breaks
  into" tooltip, and the Prices tab has an "Enchanting materials" tick box
  and an "In your bags" line. A saved tab or key binding for an old tab
  opens its new home.
- Mailbox **Take sales**, **Take expired**, **Take cancelled** and **Take
  all** buttons under the inbox, each with a count. Payment-due (COD) mail
  is never touched and nothing is deleted.
- **Tradeskills mailbox** (off by default, in Settings) shows a movable
  window instead of the game's mailbox, with sales listed first, the Take
  buttons along the top, letters you can read, reply to or return, and the
  game's own Send Mail page. "Use the game's mailbox" switches back for
  that visit.
- Settings now sit on seven pages (Pricing, Queue, Mail & vendors, Auction
  house, Look & sound, Sharing, Data), one line per setting, with what each
  does in its tooltip. **Show descriptions** puts the text back under every
  row, and **Find a setting** searches every page. Nothing was removed or
  renamed, so your choices stay as they were.
- New **Text size** setting (Normal, Large, Larger) makes the text bigger
  without growing the window. It works with Window size and takes effect
  after `/reload`, with a **Reload now** button beside it.
- Column headings are never cut off, and columns other than money are
  centred. Money always reads like 1g 05s 00c, so the coins line up.
  Item names that don't fit wrap onto a second line instead of ending in
  "...".

## 0.37.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The main window can now be resized from 50% to 150% of its normal size.
  Drag the gold grip below its bottom right corner (right-click it for
  Normal), pick Small, Normal or Large under **Window size** in Settings,
  or type `/bts size small|normal|large|<percent>`. Everything scales
  together, so no tab loses its layout, and the size is kept between
  sessions. The window never grows past the screen.
- Queue tab costs now follow **Queue sub-crafts**. With it off, in-between
  materials are priced at what they cost to buy; with it on, at what they
  cost to make. Each queued craft and the footer's materials and profit
  now match the Materials Needed list.
- Fixed sales on the Sales tab that kept saying "gold waiting in the mail"
  long after the gold was collected, stack sales especially. Sales already
  stuck clear on your next mailbox visit. Only the display was wrong; the
  totals, profit figures and gold chart were never affected.
- With more than 50 mails waiting, a sale whose mail wasn't shown yet no
  longer stops saying its gold is waiting.
- A few lucky disenchants no longer make an item override the disenchant
  table. An item now takes over after three casts only when the table's
  likeliest result never came out of it; otherwise it waits for ten.
- Gold mailed to an alt addressed by full name, as Queue Mail fills it in,
  now counts as Your characters on the gold chart instead of Mail spending.

## 0.36.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Tradeskills now learns how each item disenchants for you, not just each
  row of the disenchant table. Once you've disenchanted an item three times
  and it mostly gives something other than the table says, its own results
  are used everywhere: the tooltip value, the Disenchanting and Enchanting
  tabs and Profit. Chat says "Learned!" when that happens, and `/bts delog`
  lists those items. Items that break the way the table says keep using
  the table's bigger pool. Disenchants you recorded before this update are
  filled in once from your recent list.

## 0.35.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Crafts on the Queue tab, sub-crafts included, are now drawn in the colour
  of the item they make (green, blue, purple and so on), as on the Profit
  tab. An item the game hasn't loaded yet picks up its colour as soon as it
  arrives. A craft whose profit has fallen since it was queued now says
  "worth less than when queued" in amber beside its name.

## 0.34.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- New price graph. Tradeskills keeps the cheapest listing once an hour for
  7 days for what your characters craft, their materials and starred items,
  and draws it as a line with **24 Hours** and **7 Day** toggles on the
  Prices tab and the Profit tab's craft pane (a **Price graph** button there
  swaps it in for the materials). Under the graph a line says when an item
  is usually cheapest and dearest, once there are enough scans to tell.
- Picking an item that the Buy list, the Queue tab or the Gather tab
  searched for now fills the auction house's quantity box with how many the
  queue still needs. A number you typed is never written over, and Buy Now
  is still your click. A Settings row, **Fill in how many to buy**, turns it
  off.
- At the mailbox, finished crafts another character's queue needs get their
  own green row with a **Send crafts to** button, ahead of any materials.
  Both rows show whether or not "Let alts make sub-crafts" is ticked, and
  the To box gets the full name, since Forever characters share first names.
- The Prices tab's detail pane has a **My price** section. Type a price in
  gold, silver and copper, then pick **Use this price** (it replaces the
  auction price everywhere) or **Never below** (it only lifts a lower
  auction price). Material costs, Profit, Level Up, the queue, tooltips and
  posting all follow it, and items with a price of your own say "my price"
  in gold. A new **My prices only** tick box lists just those. Clear removes
  the price.
- Buy materials at a vendor buys the whole amount again; buying a bagful at
  a time is taken out for now, along with its "Fit vendor buys to your bags"
  setting. Take next batch at the mailbox stays.
- The minimap button now sits on the minimap's ring beside other addons'
  buttons, instead of floating just outside it.

## 0.33.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- New **Gold in and out** view on the Sales tab: a chart of where your gold
  came from and went, by source (auction sales and buys, deposits, vendor,
  repairs, loot, quests, training, flights, mail, trades), for this session,
  today, the last 7 or 30 days, or dates you pick. Hover a bar for what made
  it up. Gold mailed between your own characters is kept apart.
- The Sales tab shows the profit on each sale over what the item cost to
  make, in green or red, with totals per item and for the whole list.
- Vendor Flips has a new **Sell to: Auction house** choice: items other
  sellers have listed well under their usual price, with what to list them
  again at and the profit after the cut.
- The Profit tab's PROFIT is now the best of the auction house, a vendor
  and disenchanting, with a VIA column saying which. A **Profit:** switch
  ranks by Best, AH, Vendor or DE alone. Disenchanting only counts when one
  of your characters has the Enchanting skill for the item.
- The Prices tab has a star on every row. Star the items you watch and tick
  **Favourites only** to see just those.
- While batch crafting, the progress bar also shows the time left on the
  whole batch, e.g. "3 more · 3.0s · 15s left".
- Every tab's option bar is laid out the same way: menus, then search, then
  tick boxes. The "Sort:" menus are gone, since clicking a heading sorts,
  and the right-hand panel no longer moves when you switch tabs.
- The Enchanting tab no longer has its own "Items in your bags" view; the
  Disenchanting tab's **Items in my bags** tick box shows the same list.

## 0.32.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The Level Up tab now has the **MY RECIPES | RECIPES TO LEARN** switch
  too. There the list is ordered by the skill each recipe needs, lowest
  first, so the next recipe to pick up on the way up sits near the top.
- On both tabs, the SKILL column in Recipes to learn is green when your
  skill is already high enough to learn the recipe and amber when it isn't
  yet.

## 0.31.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- Recipe items (Pattern, Plans, Formula, Recipe, Schematic, Manual) now
  show what they're worth on their tooltip: what the recipe teaches and at
  what skill, who on your account knows it, the cost to make, what one craft
  sells for after the cut, what it disenchants for, the profit per craft,
  and how many crafts pay the recipe back. A Settings switch turns these
  lines off.
- The Profit tab has a new **MY CRAFTS | RECIPES TO LEARN** switch.
  Recipes to learn lists every recipe of a profession you don't know yet,
  with skill, cost, sells, disenchant, profit, the recipe's cheapest price
  (trainer, vendor or auction) and where it's learned. Sort by any heading;
  the pane on the right shows the materials and where to learn it (vendors
  on your side, drops, trainer). Open it with `/bts recipes [profession]`
  or the button in Settings.

## 0.30.0

For WoW: Forever (interface 16001). A file was added, so restart the game
fully after updating (`/reload` is not enough).

- Tradeskills now remembers what each craft cost you to make. The item
  tooltip, Ready to sell and the Post tab show **Made for** (what one cost
  the last time you crafted it, and when), **Last posted** (the price it
  last went up at) and **Profit now** (what listing at today's price makes
  over that cost after the auction house's cut, in green or red).
- New setting under Posting, **Never below what I paid** (off by default):
  a listing that would bring in less than the last craft cost after the cut
  is refused and shown in red on Ready to sell. It works alongside the
  existing material cost guard.

## 0.29.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Buy materials now buys only what fits in your bags, keeping 5 slots
  free, and keeps the materials in step so what you buy makes whole crafts.
  The button reads "Buy what fits", and its tooltip says roughly how many
  batches the queue will take. Craft, then click again for the next batch.
- New setting, **Take queue mail in batches** (off by default): the
  mailbox panel gets a **Take next batch** button that takes the queue's
  materials out of the mail the same way, one stack at a time. It never
  touches COD mail.
- The Level Up tab has three new columns: GETS BACK (the most one craft
  returns), VIA (Vendor, AH or DE) and REAL COST (the materials less what
  you get back, in green with a plus when the craft pays for itself). Each
  skill-up colour now ranks on the real cost.
- On the Queue tab you can type the queued amount (Enter to set it, 0 takes
  the craft off), with room for four digits. The window is a little wider,
  so Materials Needed has more space and long names are no longer cut
  short.

## 0.28.5

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The craft queue no longer drops a planned sub-craft when buying it turns
  cheaper partway through a chain (say scraps to light leather to medium
  leather). The sub-craft stays, its row says "buying is cheaper now" in
  amber, and chat tells you once. Hover it to see both prices.
- A **Buy instead** button on the Queue tab, or **Buy** on the craft queue
  beside the profession window, takes that sub-craft off and puts the item
  on the shopping list.

## 0.28.4

For WoW: Forever (interface 16001). Nothing in the addon itself changed, so
`/reload` is enough after updating.

- New versions are now announced in the Blackthornes Discord, in the
  #announcements channel.

## 0.28.3

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Listing every copy of an unstackable crafted item in one click no longer
  switches itself off. A sale between auction house visits could make a full
  batch look short and turn it off for every item until the next login. Now
  only a clear reading can turn it off, and only for that one item. Items
  whose info has not loaded yet no longer go up one at a time.

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
