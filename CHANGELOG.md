# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

## 1.36.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Prices tab.** An item with random suffixes opens to show each suffix as its own row with its own price, and the search reads suffix names too.
- **Cooldown crafts.** Crafts with a cooldown, like transmutes, are priced at what the item costs to buy, and the queue no longer plans as many as it likes. Set one to Make on the Level Up tab to plan it anyway.
- **Mailbox visits.** The list keeps 60 days of visits, up to 2,000.
- Various bug fixes for Tradeskills.

## 1.35.4

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Prices and sales.** Your prices and sales are kept when the game gives a blank realm name.

## 1.35.3

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Road to 300.** First Aid and Cooking recipes now find their trainer, so the road keeps going past the recipes you know.

## 1.35.2

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Post at Minimum Profit.** Trade goods like leather post at the market price.

## 1.35.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Trip line.** The trip line and stop dots now draw on the world map.
- **Profit by method.** Longer periods count older sales past the last 400.
- **Disenchant profit.** The age shown for a disenchant profit reads the material you mostly get.

## 1.35.0

For WoW: Forever (interface 16001). A full restart is needed after updating, because a file was added.

- **One Window switch.** Every Blackthornes window has a gold gem on its title bar. It swaps between the one window and each addon's own windows.
- **Road to 300 trainers.** When you open a profession trainer, Tradeskills notes the recipes it teaches, with their price and the skill each needs. Road to 300 and Learn Next then offer them. Some trainer recipes are known ahead of your visit.
- **Road to 300 standing.** A recipe only a vendor teaches stays off the road while you lack the standing it asks for.
- **Disenchanting.** Disenchant value is the average of every result, counting each by its chance.
- **Prices tab.** Item names fill in once the game loads them.
- **Craft queue.** The queued craft stays showing when you resize the window.
- **Snipe.** Snipe lists only show finds your Spending Cap can buy.
- **Crafted gear.** A crafted piece with a suffix is priced by that suffix.

## 1.34.5

For WoW: Forever (interface 16001). A full restart is needed after updating, because a file was added.

- **Listing from a bag item.** Fixed the "blocked" pop-up when you list a Spellstone or other bag item. List It and Skip now open in Tradeskills' own window.
- **Gear prices.** Gear lists now price to the copper, even after a listing was missed.
- **Road to 300.** Materials you already own count as free when Charge for Own Materials: is off, so hides get used first. The "Get everything before you start" row is gone.
- **Quick Scan.** If it stops partway, it keeps the rows it already read.

## 1.34.4

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Restocking.** After a sale, Tradeskills queues enough crafts to reach the amount you keep in stock.

## 1.34.3

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Cooldowns.** Fixed an error in the cooldown timer.
- **Road to 300.** Steps show in green when nothing better is known, and the game's own colours still win.
- **Recipes to Learn.** A click on the Skill column sorts by skill again.

## 1.34.2

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Road to 300.** Queue Step queues only the step you click.

## 1.34.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Bug fixes.** Various bug fixes for Tradeskills.

## 1.34.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Queue on the Crafting tab.** The craft queue and the Shopping List show on the one window's Crafting tab. They show only while something is queued.
- **Sold items.** An item that sold is no longer logged as cancelled. Restocking happens when your listed count reaches 0.
- **Road to 300.** Each rank sends you to the trainer who teaches it.
- **Profit tab.** Hovering a recipe that makes more than one item no longer shows an error.

## 1.33.0

For WoW: Forever (interface 16001). `/reload` is not enough: files were added, so close the game fully and start it again after updating.

- **Small Craft Queue.** A new Small Craft Queue: box on the Windows page of Settings keeps the profession window to the small craft queue beside it. It starts off.
- **Only My Crafts.** A new Only My Crafts: box on the Queue page of Settings shows only the crafts this character makes. Crafts for your other characters stay in the queue. It starts off.
- **Empty queue stays hidden.** The folded craft pane stays out of the way until something is queued.
- **All Recipes.** The Profit tab has a new All Recipes view after My Crafts. It lists every recipe you know, with KEEP and IGNORE in the row. Alt-click a craft row, or pick Set Keep in Stock in a Profit row's menu, to open a small Keep in Stock box.
- **Keep in Stock.** Worn and soulbound copies no longer count toward Keep in Stock.
- **Soulbound crafts.** The Profit tab prices a soulbound craft by what a vendor pays or by disenchanting it.
- **Full prices.** Recipes to Learn shows gold, silver and copper, and your skill sits above the list on the Profit tab.
- **Neutral auction house.** A visit to a neutral auction house keeps its own listings. It no longer replaces your home listings.
- **Writs Done Today.** Writs can be marked done today, and the list says when new orders come in.
- **Minimums by Profession.** A new Minimums by Profession: row on the Pricing page of Settings gives each profession its own Minimum Profit and Minimum Margin.
- **Leave Out of Report.** Right-click a visit in Mailbox visits on the Sales tab and pick Leave Out of Report. The visit stays in the list, dimmed, and stops counting toward your totals. Count It Again puts it back.
- **Used In.** Material tooltips say which professions use the material and how many of your recipes need it. Hold Shift for the recipe names. The Used In Recipes: row is on the Tooltips page of Settings and starts on Always.
- **Learn Next.** Level Up's LEARN NEXT line has two new filters, Have Skill and Learn From, and recipe names are easier to read.
- **Recipe Wishlist.** A new Recipe Wishlist: box on the Mail & Vendors page of Settings, under RECIPES, puts a star on recipes to learn. A card at vendors and trainers lists the starred recipes they teach. It starts off.
- **Craft First.** A new Craft First: box on the Pricing page of Settings keeps an item off List all when a craft you know makes it worth more. It starts off.
- **Craft Messages.** A new Craft Messages: box on the Tooltips page of Settings turns the chat lines you get when you make something from your queue on or off. It starts on.
- **Butler.** Butler's Profession Leveling shows Cooking and First Aid, and Butler can ask which materials your Level Up list still needs.
- **Blackthornes button for addon bars.** If you already use an addon bar, Blackthornes now puts one button on it. Left-click opens the menu and right-click opens the All Addons page of Settings.
- **Settings pages in one order.** Every Blackthornes addon now lists its Settings pages the same way. Sounds is on its own page.
- **Butler at a vendor.** At a vendor the one window opens on Butler, then goes back to the addon you had open when you leave.
- **Thunder Bluff trainers.** Show the way points to Thunder Bluff and Mulgore trainers and vendors again.
- **Sold a Day.** Sold a Day no longer counts a look at the auction house that read only part of the listings as sales.
- Various bug fixes for Tradeskills.

## 1.32.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Post at Minimum Profit.** A new Post at Minimum Profit: box on the Pricing page of Settings, under When to Sell. When others sell a craft for less than it can earn, your listing goes at the lowest price that still makes your Minimum Profit. It starts off.
- **TSM Sold a Day.** A new TSM Sold a Day: box on the Pricing page of Settings takes the Sold a day number on item tooltips from TSM. It starts off and is greyed while TSM Prices is off.
- **Window spot.** The one window stays where you drag it.

## 1.31.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Suffix gear prices.** Tooltips for random suffix gear now show the price for that suffix.
- **Road to 300.** Artisan Enchanting now shows where the trainer is inside Uldaman, with Show the Way.
- **Import Prices.** Codes from your other account on the same realm now import.
- **Artisan crates.** Crates show their favor and silver.

## 1.31.0

For WoW: Forever (interface 16001). `/reload` is not enough: a file was added, so close the game fully and start it again after updating.

- **Crate Shopping List.** A new Crate Shopping List: box on the Auction House page of Settings adds a Waylaid Crates group to the Buy tab of the auction house drawer. It lists the cheapest bundle to buy for each crate in your bags, adds up crates that need the same material and takes off what you have. Groups fold and sort by item, amount or cost. It starts off.
- **Crafting and Mail tabs.** With One Window on, the craft pane shows as a Crafting tab beside the profession window, and the mail list shows as a Mail tab at the mailbox while it has something on it.
- **Slim craft strip.** When there is no room beside the profession window, a slim craft strip sits inside it instead.
- **Queue page.** The Queue page of Settings groups its choices into Restocking, Sub-Crafts and Alts, and The List, with Stock From Sales and Raise When Sold Out in one box.
- **Settings pages.** Settings has new Tooltips and Windows pages, with each row moved to the page where you would look for it.
- **All Addons page.** The settings every Blackthornes addon shares (Window Style, Text Size, Effects, Mute All Sounds, Combine Addon Buttons, One Window, Window Spots, Sister Addons and What's New) now sit on one All Addons page, behind the gear on the one window's rail. The two What's New boxes became one After Updates: drop-down. Nothing was renamed and your choices carry over.
- **One window docks in more places.** It sits on the free side of the game's window, shrinks only a little when there is no room, and lets you resize it by hand with the grip. Each addon keeps its own height when you switch between them.
- **Shared shelves.** Small pieces you never dragged, such as arrows, bars and cards, line up on a top or right shelf instead of starting on one spot.
- **Fixes.** Crate bundles that need more than one stack now count, because the game fills a crate from two stacks. The Skip bundles over a stack box on the Merchant's Favor view of the Deals tab is gone. Fixed the "invalid key to 'next'" error from the background worker. A long item name in the Your Time note wraps instead of running off its card.

## 1.30.3

For WoW: Forever (interface 16001). `/reload` is enough.

- **Prices match what a craft makes.** When one craft makes two or more, the Rival, Your Listing and Post prices in the Profit detail now say x2 (or x3), and hovering shows how many each craft makes.
- **Forget Character and Clear Items work again.** Both buttons on the Characters tab no longer hit an error when you arm them.
- **Vendor pays more is more careful.** An item stays off the Sell list when breaking it down is worth more. A lost deposit no longer makes a vendor look better than the auction house.
- **Demand compares like with like.** Potions, food and bandages are rated against their own kind, so they no longer all read High.
- **Gear posts keep exact copper.** A 0c undercut now matches a gear rival to the copper, and a copper undercut takes off just that copper. If a listing with copper fails to go up, the rest of the session lists gear in whole silver.

## 1.30.2

For WoW: Forever (interface 16001). `/reload` is enough.

- **Recipe materials and skills match the game.** Recipe amounts and professions now come from the game's own tables, so more recipes show the right materials.

## 1.30.1

For WoW: Forever (interface 16001). `/reload` is enough.

- **Mail between your own characters is not profit.** Gold you mail from one of your characters to another no longer counts as income in the mailbox report.
- **Writ hand-in spots show right away.** When the addon learns where a writ is handed in, the writ list redraws at once instead of waiting.
- **Snipe Buy no longer sticks on "asking".** A stack buy now finishes instead of hanging.

## 1.30.0

For WoW: Forever (interface 16001). A full restart is needed after updating, because files were added.

- **Bought list on the Sales tab.** A new Bought view lists what you bought on the auction house: what you spent, the items you bought most, what you paid each, when, and which character bought it. Pick it from the view tabs at the top of the Sales tab. It keeps a log from now on, starting at your oldest buy.

## 1.29.0

For WoW: Forever (interface 16001). A full restart is needed after updating, because files were added.

- **Butler Says Wait on the auction drawer.** When Butler says to hold an item, the Sell drawer shows why and has a Sell Anyway button. A Waiting strip with Sell All Waiting and a Show Waiting tick sits above the list.
- **Ignore Deposit.** A new Ignore Deposit box on the Pricing page leaves the deposit out of a sale's cost. It starts off.
- **Craft Cost and Profit.** A new Craft Cost and Profit: row under Show Value in Profession Window adds cost and profit to the game's profession window. It starts off.
- **Goblin Gold goals.** A new goal window sets your next gold goal. Right-click the bar for a menu, and use Change Goal to pick another.
- **Profit by profession and character.** Crafted sales are split by profession, and a Character: menu shows all characters or one of this realm's sellers.
- **TSM BoE Price Source.** A new TSM BoE Price Source: box on the Sharing page prices gear that binds when worn. Empty uses your main TSM price source.
- **Queue control.** You can pause crafts, move them and right-click for a menu. Crafts that need a tool nearby are skipped and say "Needs a NAME".
- **Cost to make on tooltips.** A recipe's cost to make also lists bind on pickup materials, such as "12g 30s, plus 4 Demonic Rune".
- **Road to 300.** Thick Leather is offered at 175, Show the Way picks a trainer on your own continent first, and two steps of one recipe add up in the queue.
- **Gear posts round up.** A gear post at 0c undercut rounds up to the next whole silver and never goes under the rival.
- **Old professions are let go.** A character that dropped every profession is no longer named for crafts.
- **Fixes.** The Sell button fits its words, such as Check Price and Sell Anyway. Scrolling and List Next skip items Butler says to wait on. The addon uses less memory. The mouse wheel works the first time you open the auction house.

## 1.28.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Road to 300 finds the right trainer.** Show the Way now sends you to the trainer who teaches your next rank, such as Artisan, instead of one that only teaches an earlier rank.

## 1.27.0

For WoW: Forever (interface 16001). A full restart is needed after updating, because a file was added.

- **Export Prices and Import Prices.** Two new buttons on the Queue page of Settings copy your recent auction prices so you can use them on another computer.
- **TSM Price Source.** A new TSM Price Source: box on the Sharing page picks which TSM price to use: DBRecent, DBMarket, DBMinBuyout or your own TSM price. It starts on DBRecent.
- **Disenchant Results.** A new Disenchant Results: row on the Look page (or `/bts dechat on|off`) lets you keep disenchant lines out of chat.
- **Snipe buys in one click.** The top find's price is ready ahead of time, so Buy pays in one click.
- **Auction house wheel fix.** The wheel on Sell and Snipe now posts and buys every time, with no second check after a scan.
- **Vendor-pays-more fix.** An old 1 silver deposit floor no longer counts when a vendor pays more.
- **One Window fix.** The One Window stays in front of the craft pane when a profession opens.

## 1.26.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Window Spots.** Windows now remember where you drag them, and the one window remembers its spot beside each game window it docks to (the auction house, mailbox, vendor and trainer). Every window stays on screen. A new Window Spots: Set Default row on the Look page (or `/bts windows reset`) puts every Blackthornes window back where it started. Sizes, settings and data stay as they are.
- **Gold an Hour.** A new Gold an Hour: row on the Pricing page of Settings (or `/bts goldhour on|off`) shows whether buying the parts or making them earns more an hour. Only crafting time counts, not buying or selling. It starts off.
- **Writs by zone.** The Group By: choice on the Writs list can put writs under zone headings, with Show the Way on each one. Hand-in spots are learned as you play. It starts on no grouping.
- **Prefer TSM Prices.** TSM's price now takes over once your own scan is an hour old, instead of four hours.
- **Craft pane steps aside.** The craft pane moves out of the way when the Character window opens.
- **Drag the auction house drawer.** The sell list drawer at the auction house can be dragged, and it remembers its spot.

## 1.25.0

For WoW: Forever (interface 16001). A full restart is needed after updating, because a file was added.

- **Buy Sets.** Each open list in the auction house drawer's Lists view has a Spend Up To: box and a Buy Sets button. It fills the list in whole sets, keeps listings above Most I'll Pay out, and buys row by row with Buy, then Confirm.
- **Mute All Sounds.** A new Mute All Sounds: row on the General page of Settings (or `/bts mute on|off`) quiets every sound from every Blackthornes addon at once. It starts off.
- **Prefer TSM Prices.** A new Prefer TSM Prices: row on the Sharing page of Settings picks TSM's price over the shared ones while TSM Prices is on.
- **Where profit comes from.** Level Up and Recipes to Learn show (AH), (Vendor) or (DE) after each profit. The recipe tooltip names the way that won. The Profit: choice on the Profit tab gains Vendor and DE, which leaves the auction house out.
- **Road to 300.** Right-click a craft step and pick Skip This Recipe. The road works itself out again with the next cheapest one. Show All brings skipped recipes back.
- **Queue time.** Each craft row on the Queue tab shows how long it takes to cast, and the footer says about how long the whole queue takes. Hover to see it by character.
- **Demand in Recipes to Learn.** A Demand column on both Recipes to Learn lists, and a Demand line on recipe tooltips, so you can tell a recipe's item sells before you buy it.
- **What you paid.** Item tooltips can say Bought For: your newest auction house buy and when, and Shift adds the average paid. Choose Off, Shift or Always under Bought For: on Tooltips.
- **Posting price floor.** Your own scans now keep posting's price floor.
- **Cured Thick Hide.** The Thunder Bluff and Darnassus trainers now teach it at skill 175.

## 1.24.0

For WoW: Forever (interface 16001). A /reload is enough after updating.

- **Reset window places.** If a window ever ends up off your screen, press Reset next to "Window Places:" on the Look page of Settings, or type `/bts resetwindows`. Every Tradeskills window goes back to where it starts.
- **Road to 300.** With Real Cost picked, the plan no longer uses long yellow steps.
- **Deutsch.** The new words are in Deutsch, and in Simplified Chinese, French, Spanish and Russian.


## 1.23.1

For WoW: Forever (interface 16001). A /reload is enough after updating.

- **Small fixes.** A few small touch-ups.

## 1.23.0

For WoW: Forever (interface 16001). Files were added, so quit the game and start it again after updating.

- **My Auctions.** A small window that lists what you have up on the auction house: the item, how long is left and the price. When something sells, its row lights gold, SOLD stamps on, coins burst out and the row slides away, and Sold Today: counts up. New posts show right away, and the list scrolls to the newest one. Turn it on with Auction Tracker: under AUCTION TRACKER on the Auction page of Settings. It starts off. Sold Effects: (Full, Subtle or Off), Transparent: and Tracker Place: (Set Default) are there too.
- **Sales by item.** The Sales tab can now show your sales by item, with last sold, each price, taken in, sales and how many sold, plus totals. Clicking an item shows how it has done. The footer counts only what the search shows.
- **Clear Items.** A Clear Items button on a character's card forgets its saved bags, bank, mail and gold, so old counts stop sending jobs there. It asks you to click again first. Logging in on that character reads it again.
- **Alts not seen in 30 days.** Butler's jobs skip an alt whose bags were last seen more than 30 days ago.
- **Smaller least deposit.** Forever's least deposit is 1 copper now, so profit guesses made away from the auction house use it.

## 1.22.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Potential Sale Total.** It now shows what everything on your Sell list should bring in, from the start. Held lines and lines with a note are left out. It stays the same while you post, and follows prices as a scan runs. The hover still splits it into Listed, Still to List and Held Back.
- **Profit by method counts whole stacks.** Each sale now remembers how many items were in it, so a stack of 20 is costed as 20 and not as one. Sales with no known cost show "Not Counted" and sit on their own "Sold, no cost known" line, outside Profit. Farmed sales still count.
- **Legacy perks.** Working Overtime now counts in the chance a yellow craft gives a skill point, and Performance Bonus counts in Merchant's Favor costs and crate numbers. Only ranks you have spent count. With none spent, nothing changes.

## 1.21.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Auction or vendor agree.** The item tooltip, Butler and the Sell list now weigh the auction house against a vendor the same way, so the tooltip no longer says Auction for an item the Sell list sends to a vendor.
- **Mail running out.** Tradeskills now saves when each character's mail runs out, so Butler can warn you.

## 1.21.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Buy from Snipe.** Each find on the Snipe list has its own Buy button. It checks the price first, then shows what you'll pay, like Buy 20 for 1g 20s. Past your Double Check price it asks you to click again.
- **Gold In and Out.** The bars follow This Character. Gold from the mailbox is sorted as auction sales, outbid refunds or gold sent from your characters.
- **Vendor or auction.** An item goes to the vendor when the auction house would pay less than one deposit more.
- **Price sharing quiets down.** Refusal lines from the price channel are hidden, and sending slows down after a refusal and stops after three. You still hear prices from others.
- **Shift tooltips.** Holding Shift over a tooltip no longer throws a Lua error.

## 1.20.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Mouse wheel follows the auction house tab.** On Sell, turning the wheel either way lists your next stack. On Auctions, either way cancels your next undercut auction. On other tabs the wheel is left alone.

## 1.20.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Where trade camp recipes come from.** Recipes sold for Merchant's Favor show the vendor, zone, cost and any standing they need in the Recipe Book, and Show the Way on the Level Up tab can lead you there. A vendor shows once you open it with this version.
- **Hover a recipe's materials.** In the Recipe Book and Your Time, hovering a material shows the item's tooltip. Recipe Book material names are white now.
- **Match the cheapest listing.** New players start with Undercut By at 0c, so posts match the cheapest price. Your saved Undercut By stays as it is. On Your Auctions, a listing tied with someone else's price shows Cheapest in amber until you run Check Places.
- **Limited stock vendors.** A material a vendor sells only a few of at a time is no longer on your shopping list as a vendor buy. It's priced from the auction house instead.
- **Craftsman's Writs in other languages.** Writs are found by your game's own item names, so they get prices on clients that aren't English.

## 1.19.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Drop-down menus open over the window.** Drop-down lists in the Rules window and other windows are no longer hidden behind the window they sit in.
- **Mouse wheel posting keeps going.** Scrolling to post moves on past a stack the game refused or that was skipped, instead of stopping there.
- **Mouse wheel posting works after the auto scan.** Scrolling to post lists right after the auto scan finishes, at the price the scan found.

## 1.19.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Fishing on the Road to 300.** The Road to 300 view on the Level Up tab now takes Fishing to 300. Each step shows the pole to wear, the lure you need, the best spot you have fished, about how many catches are left and about how long that takes at your pace, with Artisan coming from the quest chain. Fishing is in the profession drop-down. There is no queue button for it, since there is nothing to craft.
- **Price graph in Recipes to Learn and Your Time.** Both views can swap the materials list for the price graph, like My Crafts does, with a button on the heading. Under it is the average for the days shown. Recipes to Learn also says after how many crafts the recipe pays for itself at that price, and Your Time says what farming and crafting makes an hour at that price. Both start off showing the materials.
- **Linked-account prices.** Prices now go to your linked account after any new price, not only after a full scan, so a scan cut short or a search reaches the other account too. Prices it already holds are no longer dropped when the other account has been quiet for a few days.

## 1.18.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Cooking and First Aid on the Road to 300.** The Road to 300 view on the Level Up tab now takes Cooking and First Aid all the way to 300. Expert comes from a book and Artisan from a quest chain, each for your side, and Show the Way leads you to the quest giver or teacher. Both are in the profession drop-down.
- **Better Cooking and First Aid recipes.** The Road to 300 skips old recipes Forever remade under the same name, such as Basic Campfire. Ingredients nobody sells or lists are priced at what a vendor pays, so meat recipes stay on the road past 75. Recipes you see in your Cooking window now stay on the Cooking road.

## 1.17.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Crafted Only on the Sell tab.** A new Crafted Only tick box at the auction house hides everything your recipes don't make. It starts off.
- **Various bug fixes for Tradeskills.** Shuffles' Queue It no longer doubles a craft that is also made as a sub-craft.

## 1.16.2

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Fairer listing deposits in profit.** When you list several crafts together, each craft's profit now takes only its own share of the auction deposit, not the whole thing.

## 1.16.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Shared prices on linked accounts.** If you play on two accounts that name each other, each account's newest auction prices now go across too, with no tick box to find. The newer price wins, and nothing taken is passed on to anyone else.

## 1.16.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Last Synced.** If you play on two accounts, the Sharing page of Settings and the other account's tooltip now say when you last synced. It says Not yet until the first time.
- **Queue and patterns you learn later.** Once a pattern's craft is queued, the materials listed for that pattern come off your shopping list.

## 1.15.0

For WoW: Forever (interface 16001). Do a full restart after updating, since Snipe has a new key.

- **Snipe buys in one click.** Snipe gets the top deal ready while you watch, so one click buys it. The new Snipe: Buy Top key does the same. Buy It shows what you will pay, and Checking... while it gets ready. Nothing ever buys by itself. Every buy still takes a click, a key press or a wheel turn.
- **More of a good deal.** After a buy, the item stays on top while more of its listings are deals, and its row says how many are left.
- **Double Check Over:** Any buy above the price in this new box asks Click Again.
- **A list that holds still.** The Snipe list stays put while your mouse is on it. New finds wait behind a small chip.
- **Stacks.** Snipe now reads a stack's listings and buys the cheapest units first. It stops at the first unit that isn't a deal and stays under Most I'll Pay.
- **Watch and List.** Changing either one while Snipe runs starts it over with your new choice and keeps the amount you have spent.
- **Share Sales:** A new tick under Settings, Sharing, Your Other Account. It stays off until you tick it on both accounts. Then the Sales and Stats tabs show both accounts together, and a new sale reaches the other account within seconds. Buyer names never leave the account.
- **Share Shopping Lists:** A new tick in the same place, also off until you tick it on both accounts. Each account's lists and craft queue list show read only on the other account, with how many it still needs. Snipe's My Lists picks those up too.
- **Mouse wheel.** With Mouse Wheel ticked, the wheel keeps listing at the auction house even if something else takes it. A drawer list with nothing more to show now lets the turn through.
- **Sharing your data.** If you chose to share your data, it now goes to one more of our collecting characters. It is still off until you turn it on, and what gets sent is the same.

## 1.14.2

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Healing potions.** Forever moved them from Alchemy to First Aid, so Road to 300 no longer tells alchemists to make Minor and Lesser Healing Potion. Other Classic recipes Forever removed are left out of the recipe book too.

## 1.14.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Disenchanting.** A character with Enchanting on record now counts as able to disenchant, even when the game's spell check says no. Butler no longer says none of your characters can break your Always disenchant list.

## 1.14.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Auction deposit.** Ready to sell rows now show the auction house deposit. It turns orange when the deposit is more than the item sells for.

## 1.13.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Share Craft Queue.** Under Sharing, Your Other Account, tick Share Craft Queue to send what your queued crafts still need to your other account. Its mail suggestions then offer those items to the matching character on the same realm and side. Off unless you tick it.

## 1.12.2

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Profit.** Profit now counts the 1 silver minimum deposit Forever's auction house charges, so cheap items show the right profit.

## 1.12.1

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Realm prices.** If you leave the price channel, Tradeskills joins it again a few seconds later. Settings says when you aren't in it.

## 1.12.0

For WoW: Forever (interface 16001). A full restart is needed after updating, because a file was added.

- **Snipe: Buy It.** A gold Buy It button sits left of Start on the Snipe tab. It buys the top find. Big buys ask you to Click Again first.
- **Snipe: My Lists.** Watch: has a new choice, My Lists, with a List: drop-down. Snipe looks for the items on your shopping lists and stops once you have what the list wants.
- **Most I'll Pay.** In the Lists view, each item has a Most I'll Pay box, so you can set your own top price for Snipe.
- **Sell tab.** Every item in your bags now shows on the Sell tab unless you hid it. Items it won't list sit dimmed at the bottom and say why, like "No price yet."
- **Hidden items.** A Hidden button beside Overcutting opens a list of the items you hid on the Sell tab, with Restore on each.
- **Snipe.** Buying a find works again, also for items sold one at a time.
- **Snipe.** Pressing Stop keeps your finds, so you can still buy them.
- **Sell tab.** Grey items never show there. Sell those to a vendor.
- **Auction house.** The drawer builds right again, and Snipe's labels only show on the Snipe tab.

## 1.11.0

For WoW: Forever (interface 16001). A full restart is needed after updating, because files were added.

- **Enchant Window.** A strip under the recipe in your Enchanting window. Pick an item, then click Enchant. Turn it on in Settings, on the Look page, under ENCHANTING: Enchant Window:. It starts off. A one-time What's New card offers to turn it on.
- **Character window.** The craft pane now drops below the game's character window while it is open, so you can click your gear to enchant it.

## 1.10.0

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Auto open.** Two new settings on the Auction House page under AUTO OPEN: Open at AH: and Open at Professions:. Both start on, so nothing changes unless you untick them. Unticked, Tradeskills stays shut at the auction house or beside your profession window until you open it yourself.
- **Your other account.** Listings from your other account now count under this account's realm, so Keep in stock sees them.

## 1.9.7

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Realms.** Characters on your second account now count as this realm in Characters, queue mail and gold totals.
- **Your price.** Use suggested only shows once you type your own price.
- **Your price.** The labels fit in full, so Suggested and How many are no longer cut short.

## 1.9.6

For WoW: Forever (interface 16001). `/reload` is enough after updating.

- **Cooldowns.** Plain cooking recipes no longer show up as cooldowns, and Butler no longer lists them as ready.
