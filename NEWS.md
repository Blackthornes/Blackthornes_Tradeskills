# News

What each release says in the Discord server's #general channel: a few
short bullets per version, in plain words for players, saying what they'll
notice, then one line thanking, by their Discord name, everyone whose
feedback or report led to the changes (each name once; no line when nobody
asked). Each release PR writes the new version's section here next to its
CHANGELOG.md section, and after the upload `tools/post_general.py` posts it
under a line with the addon's name and version that points players to
#announcements for the full list. No link or addon card goes with it. This
is the only report that names players. A version with no section here posts
nothing in #general.
This file does not ship in the addon, but its newest sections do, without
the thanks line: `python tools/make_whatsnew.py` writes them into
Core/WhatsNewText.lua for the in-game What's New window. Run it after
writing a section; the release check refuses a tag while it is behind.

The window shows new features only. Write a section's features first, then
a "Fixes and changes:" line with the fixes and other changes under it: those
go to Discord but stay out of the window, and a section of only fixes puts
nothing in it. Say what each feature does in a few plain words, the way you'd
tell a friend: no hype, no questions to the reader, no exclamation marks
outside the thanks line, no dashes as punctuation, no "now you can". The
tool prints a note for a shipped line that reads like an advert.

## 1.49.1

- The Sell list shows your other copies of an item when one copy is soulbound.

## 1.49.0

- The Profit tab shows a 7 Days price line, a sell-speed bar and three cards. Click any profit to see how it adds up.
- Road to 300 has Stop At buttons, Fewest Materials, No Auction House and Skip on each step.
- The Queue has Sort By chips and an optional chime when it is done.
- My Auctions lists today's sales under Sold Today.
- Pick how Tradeskills opens at the auction house, a profession and the mailbox.
- New Font, Colors and Fold Gem choices on the All Addons page.

Fixes and changes:
- The game no longer stutters while a quick scan is read.
- The Prices, Disenchanting, Level Up and Profit tabs open without a stall.
- Opening Settings no longer freezes the game.
- The save is smaller.
- Road to 300 skips recipes before their skill and cooldown crafts such as transmutes.
- The Recipes to Learn pane shows every material, costliest first.
- A new copy of gear sells while the equipment set's own copy is worn.
- The minimap button stays where a button drawer puts it.
- Shift tooltip lines sit at the bottom of the tooltip.

## 1.48.0

- Vendor prices count the Bartering perk.
- The item tooltip shows what an item costs to make now, above Profit Now.
- Stock you bought is costed at what you paid and shows under Flipped.
- Lucky disenchants at an Arcane Salvager say so again, with the sound.

Fixes and changes:
- Various other bug fixes for Tradeskills.

## 1.47.2

Fixes and changes:
- Snipe and Disenchant Quick Buy buy the item when you press Buy.
- The Salvager tab shows the cut and profit from your Salvager value.
- Various other bug fixes for Tradeskills.

## 1.47.1

Fixes and changes:
- Plain Disenchant Results in Settings lets you move your old disenchants to your Salvager results, or clear them.

## 1.47.0

- Profit Now on the item tooltip uses what one costs to make today, and shows for any item a recipe makes.
- Hovering a craft's profit in the Craft queue shows the profit for one craft.

## 1.46.2

Fixes and changes:
- Lowest Posting on the item tooltip shows the cheapest listing.

## 1.46.1

Fixes and changes:
- The guide arrow is now a slim bar that takes less room.

## 1.46.0

- The Stats page lists suffixes under each item.

Fixes and changes:
- Quick scan reads big auction houses much faster.
- Road to 300 and Learn Next leave out recipes for a specialty you do not have.
- Road to 300 leaves out cooldown crafts such as Mooncloth.
- The sell drawer hover shows the suffix name, and suffix graphs show the scans they have.
- Various bug fixes.

## 1.45.0

- Buy One buys the next listing as soon as you click it again.
- The Sales tab keeps 60 days of sales, up to 2,000.

Fixes and changes:
- Various bug fixes.

## 1.44.0

- The Craft queue has an Upgrades Only box that lists only crafts that make an upgrade for you.
- Your Way There is now a small see-through box with only your current step and a dial that points the way.

Fixes and changes:
- The Salvager notice goes away when the Boosted Disenchanting buff ends.
- Scroll bars move the way you drag them.

## 1.43.0

- Buy One on the Disenchanting tab buys the cheapest listing on each click, with no pop-up. You can bind a key to it.
- Each random suffix on the Prices tab has its own My Price, and item cards and Sales show the suffix name.
- The Sell list keeps its order while the auction house is open.
- Disenchants at an Arcane Salvager are kept in their own record from the start. The addon spots the Salvager by its buff.

Fixes and changes:
- Any enchanter can disenchant any item.
- Value on Tooltips set to Off hides the Disenchant Value line too.
- The Disenchanting and Deals tabs update when you search the auction house yourself.
- The Prices graph stays readable in a short window, and Side by Side no longer covers the value lines.

## 1.42.0

- The All Addons page in Settings has a Set Default button. Click Confirm and this addon's settings go back to how they started.

## 1.41.2

Fixes and changes:
- Light Leather and other gathered goods list at the auction price.
- Buy Sets and Merchant's Favor no longer stick on "auction house is busy".
- Buy For on Disenchanting moves to the next price after you buy.

## 1.41.1

- Road to 300 names the city for Undercity, Thunder Bluff and Darnassus trainers.
- Scans finish without a freeze, and the Profit and Prices searches are quicker.

Fixes and changes:
- Various bug fixes for Tradeskills.

## 1.41.0

- A new Queue From Sell List box in Settings puts crafts that Craft First holds back into your queue. It starts off.

Fixes and changes:
- After a scan, the Sell list lists an item as soon as you click, with no wait. This holds for fifteen minutes.
- Snipe buys materials again, and tells you why when a buy fails. To Disenchant says why its list is empty.
- Value on Tooltips set to Off hides only the price lines. Sales, disenchant and the other lines stay.
- A random suffix item's new price shows the next time you open the auction house.
- The recipe count no longer covers a long profit number in the profession list.
- Closing windows with a gamepad no longer gives a blocked action error.


## 1.40.0

- A new Upgrades Only box on the profession window lists only the crafts that are upgrades for you.

Fixes and changes:
- A quick full scan that you stop keeps its prices.


## 1.39.2

Fixes and changes:
- Road to 300 Fishing sends every race to the right zones.
- Shuffle no longer shows an error on a recipe with no top yield.
- The bag stack total on item tooltips stays inside the tooltip.

## 1.39.1

Fixes and changes:
- The Auction House tab always shows the sell list in the One Window.
- My Auctions rows grow to fit long item names.
- Gear with a random suffix shows its full name in My Auctions.

## 1.39.0

- Windows fold into a round button with the Tradeskills badge.
- Minimums by Profession has a Disenchanting row.

Fixes and changes:
- Folding the One Window no longer shuts it for good.
- Road to 300 sends smiths to the trainer who teaches the recipe.
- Profit Now and the Profit tab count what an item sold for when nobody else is selling.
- Demand waits for three listings to be gone before it reads a market.

## 1.38.0

- Panels and rows have a warm brown-black look.
- The main window has a slimmer frame.
- One-line rows can be Compact if you like.
- Item rows link in chat and try on gear.
- Recipes to Learn shows the Profit: choice.
- Tradeskills has a line in the game's Options.

## 1.37.0

- The Buy Materials button stays on the vendor window when Butler is loaded.
- Each suffix on the Prices tab shows its own price graph and Stats.
- Sales of stacks and other items are filed under their item, on one row.

Fixes and changes:
- Prices, Profit, Queue and Settings open with less stalling.
- A steady run of listings keeps going, and Snipe finds hold still between searches.
- Road to 300 uses the skill the trainer asks for.
- Blackthornes' own channel no longer takes the /1 spot at login.

## 1.36.0

- Random suffix items open on the Prices tab to show a price for each suffix.

Fixes and changes:
- Crafts with a cooldown, like transmutes, are priced at what the item costs to buy.
- Mailbox visits keep 60 days, up to 2,000.
- Various bug fixes for Tradeskills.

## 1.35.4

Fixes and changes:
- Your prices and sales are kept when the game gives a blank realm name.

## 1.35.3

Fixes and changes:
- Road to 300 finds trainers for First Aid and Cooking recipes, so the road keeps going.

## 1.35.2

Fixes and changes:
- Trade goods like leather post at the market price with Post at Minimum Profit.

## 1.35.1

Fixes and changes:
- The trip line and stop dots now draw on the world map.
- Longer periods count older sales past the last 400.
- The age shown for a disenchant profit reads the material you mostly get.

## 1.35.0

- Every window has a gold gem on its title bar. Click it to switch between the one window and separate windows.
- Road to 300 learns the recipes a profession trainer teaches when you open one.
Fixes and changes:
- Road to 300 leaves off vendor recipes that need a standing you don't have.
- Disenchant value is the average of every result, counting each by its chance.
- Item names on the Prices tab fill in once the game loads them.
- The queued craft stays showing when you resize the window.
- Snipe lists only show finds your Spending Cap can buy.
- Crafted pieces with a suffix are priced by that suffix.

## 1.34.5

Fixes and changes:
- Listing a Spellstone or other bag item no longer gets blocked. List It and Skip show in our own window.
- Gear lists price to the copper.
- Road to 300 counts materials you own as free when Charge for Own Materials is off, and the "Get everything before you start" row is gone.
- A Quick Scan that stops partway keeps what it read.

## 1.34.4

Fixes and changes:
- Restocking after a sale queues enough crafts to reach the amount you keep in stock.

## 1.34.3

Fixes and changes:
- The cooldown timer no longer shows an error.
- Road to 300 steps show in green.
- In Recipes to Learn, a click on Skill sorts by skill again.

## 1.34.2

Fixes and changes:
- Road to 300: Queue Step now queues only the step you click.

## 1.34.0

- The craft queue and Shopping List show on the Crafting tab of the one window, and only while something is queued.
Fixes and changes:
- An item that sold is no longer logged as cancelled, and restocking starts when your listed count hits 0.
- Road to 300 sends each rank to the trainer who teaches it.
- Hovering a recipe that makes more than one item in the Profit tab no longer shows an error.

## 1.33.0

- Star the recipes you want to learn, and vendors and trainers tell you when they teach one.
- Each profession can have its own minimum profit.
- The Profit tab has a new All Recipes view, and soulbound crafts get a price.
- Material tooltips show which professions use them.
- Butler's leveling help now covers Cooking and First Aid.
- Various bug fixes for Tradeskills.

## 1.32.0

- There's a Post at Minimum Profit box on the Pricing page. It lists your crafts at the lowest price that still makes your Minimum Profit. It starts off.
- There's a TSM Sold a Day box on the Pricing page. It takes the Sold a day number on tooltips from TSM. It starts off.
Fixes and changes:
- The window stays where you drag it.

## 1.31.1

Fixes and changes:
- Tooltips for random suffix gear show the price for that suffix.
- Road to 300 shows where the Artisan Enchanting trainer is, with Show the Way.
- Import Prices works between your own accounts on the same realm.
- Artisan crates show their favor and silver.

## 1.31.0

- There's a Crate Shopping List for Waylaid Crates on the auction house Buy tab. It starts off.
- The craft pane and mail list can be tabs in the one window.
- A slim craft strip sits inside the profession window when there's no room beside it.
- The Queue page and Settings are sorted into clearer groups, with an All Addons page.
- The window can dock in more places and you can resize it by hand.
Fixes and changes:
- Crate bundles over a stack now count.
- Fixed an error from the background worker.
- Long Your Time notes wrap.

## 1.30.3

Fixes and changes:
- Craft prices in the Profit detail now show x2 when a craft makes more than one.
- Forget Character and Clear Items work again on the Characters tab.
- Items no longer sit off the Sell list for the wrong reason when breaking them down pays more.
- Potions, food and bandages are rated against their own kind for demand.
- Gear posts keep their exact copper price when you undercut.

## 1.30.2

Fixes and changes:
- More recipes show the right materials and professions.

## 1.30.1

Fixes and changes:
- Gold you mail between your own characters no longer counts as profit.
- Writ hand-in spots show up right away.
- Snipe Buy no longer gets stuck on asking.

## 1.30.0

- The Sales tab has a new Bought view. It shows what you spent at the auction house, what you bought most, and what you paid each.

## 1.29.0

- Butler can tell you why an item should wait, and Sell Anyway sells it when you disagree.
- A new goal window helps you pick your next gold goal.
- Profit shows your crafted sales by profession and by character.
- You can pause crafts in the Queue, move them, and skip ones that need a tool.
- There is a new price box for gear that binds when worn, on the Sharing page.
- The game's profession window can show what a craft costs and earns. It starts off.
Fixes and changes:
- Gear posts at no undercut round up to a whole silver.
- Road to 300 picks a closer trainer and adds up repeated steps.
- Tooltips show the cost to make with bind on pickup parts.
- The addon uses less memory.
- The mouse wheel works the first time you open the auction house.

## 1.28.0

Fixes and changes:
- Road to 300 now points you to the trainer who teaches your next rank.

## 1.27.0

- You can copy your recent auction prices to use on another computer, with new buttons on the Queue page.
- You can pick which TSM price to use, on the Sharing page. It starts on the recent price.
- You can keep disenchant lines out of chat with a new tick box on the Look page.
- Snipe pays in one click when you buy.
Fixes and changes:
- The auction house wheel works every time on Sell and Snipe.
- Items a vendor pays more for are no longer held back by an old deposit rule.
- The One Window stays in front when a profession opens.

## 1.26.0

- Windows now remember where you drag them, so they come back in the same spot.
- A new button on the Look page puts every window back where it started.
- Gold an Hour shows whether buying the parts or making them earns more each hour. It starts off.
- You can group writs by the zone where you hand them in.
- TSM prices take over sooner, after your own scan is an hour old.
Fixes and changes:
- The craft pane moves out of the way when the Character window opens.
- The auction house drawer can be dragged and remembers where you put it.
## 1.25.0

- Buy Sets fills a shopping list in whole sets and stops at the gold you pick.
- A new box mutes every sound from all the Blackthornes addons at once. It starts off.
- Recipes show whether the profit comes from the auction house, a vendor or disenchanting.
- You can skip a recipe on Road to 300, and the road picks the next one.
- The Queue shows how long your crafts will take.
- Tooltips can show what you paid at the auction house, and Recipes to Learn shows demand.

## 1.24.0

- New Reset button in Settings to bring every window back if one gets lost.
- Road to 300 plans smarter steps when you pick Real Cost.


## 1.23.0

- There is a new little window called My Auctions. It shows everything you have up, and when something sells, the row lights up and slides away.
- It starts off. You turn it on in Settings, on the Auction page.
- The Sales tab can show your sales by item, with totals for what you took in.
- You can clear what an old character was carrying, so you do not get sent to log in on it.

Fixes and changes:

- Profit guesses use Forever's new 1 copper least deposit.
- Alts not seen in 30 days are skipped when jobs are planned.

## 1.22.0

- Your Potential Sale Total now shows the whole Sell list right away and stays steady while you post.
- Profit now counts every item in a stack, so big stacks no longer look like huge wins.
- Sales with no known cost are kept out of your profit.
- Working Overtime and Performance Bonus now count in your skill point and Merchant's Favor numbers.

## 1.21.1

Fixes and changes:

- The tooltip and the Sell list agree on auction or vendor.
- Butler can see when a character's mail is about to run out.

## 1.21.0

- Each find on the Snipe list has a Buy button that shows what you'll pay.

Fixes and changes:

- Gold In and Out follows This Character and sorts mailbox gold by where it came from.
- Items go to the vendor when the auction house pays less than one deposit more.
- Price channel refusal lines are hidden, and sending slows down after a refusal.
- Holding Shift over a tooltip no longer causes an error.

## 1.20.1

Fixes and changes:

- The mouse wheel now follows the auction house tab: on Sell it lists your next stack, on Auctions it cancels your next undercut auction.

## 1.20.0

- The Recipe Book shows which vendor sells a trade camp recipe, what it costs and the standing it needs.
- Hover a material in the Recipe Book or Your Time to see the item's tooltip.

Fixes and changes:

- New players match the cheapest listing by default. Your own Undercut By setting stays the same.
- A tie with someone else's price shows Cheapest in amber until you check places.
- Vendors that only sell a few at a time are left off your shopping list.
- Craftsman's Writs get prices on clients that aren't English.

## 1.19.1

Fixes and changes:

- Drop-down lists now open on top of their window, so none get hidden.
- Scrolling to post no longer stops on a stack that was skipped or refused.
- Scrolling to post now works right after the auto scan.

## 1.19.0

New:

- Fishing now goes all the way to 300 on the Road to 300. It shows the pole, the lure and the best spot for each step. Find it in the profession drop-down on the Level Up tab.
- Recipes to Learn and Your Time can show the price graph now. Use the button on the heading. It also tells you when a recipe pays for itself.

Fixes and changes:

- Prices reach your linked account after any new price, not only after a full scan.

## 1.18.0

New:

- Cooking and First Aid now go all the way to 300 on the Road to 300, with the Expert and Artisan steps. Find them in the profession drop-down on the Level Up tab.

Fixes and changes:

- Cooking and First Aid recipes on the road are more accurate, and old campfire recipes are left out.

## 1.17.0

New:

- The Sell tab has a Crafted Only tick box. Tick it and you only see things your own recipes make. It starts off.

Fixes and changes:

- Queue It in Shuffles no longer doubles a craft that is also made along the way.

## 1.16.2

Fixes and changes:

- Each craft's profit now counts only its own share of the auction house deposit.

## 1.16.1

- If you play on two accounts, they now share the newest auction prices with each other. Nothing to turn on.

## 1.16.0

New:

- Two accounts now show when they last synced, in Settings on the Sharing page and on the other account's tooltip.

Fixes and changes:

- After you queue a craft, the materials listed for learning its pattern come off your list.

## 1.15.0

New:

- Snipe can buy the top deal with one click or one key. It never buys on its own.
- After a buy, Snipe keeps the item on top while more of it is a good deal.
- If you play on two accounts, they can now share sales and shopping lists. It stays off until you turn it on for both.

Fixes and changes:

- Snipe buys stacks cheapest first and stays under your price.
- The mouse wheel keeps working at the auction house.

## 1.14.2

Fixes and changes:

- Road to 300 no longer tells alchemists to make healing potions. Forever moved them to First Aid.

## 1.14.1

Fixes and changes:

- Butler now knows your enchanter can disenchant, so it stops saying nobody can.

## 1.14.0

- Ready to sell rows now show the auction house deposit. It turns orange when it costs more than the item sells for.

## 1.12.2

Fixes and changes:

- Profit counts the 1 silver minimum deposit the auction house charges, so cheap items show the right profit.

## 1.12.1

Fixes and changes:

- If you leave the price channel, Tradeskills joins it again a few seconds later. Settings says when you aren't in it.

## 1.12.0

- A Buy It button on the Snipe tab buys the top find.
- Snipe can watch your shopping lists. Pick My Lists under Watch.
- You can set the most you'll pay for each item on your lists.
- The Sell tab shows every item in your bags unless you hid it. Items it won't list say why.
- A Hidden button on the Sell tab shows what you hid, so you can bring items back.

Fixes and changes:

- Buying a find on the Snipe tab works again.
- Pressing Stop on the Snipe tab keeps your finds.
- Grey items no longer show on the Sell tab.
- The auction house drawer builds right again.

## 1.11.0

- A new strip sits under the recipe in your Enchanting window. Pick an item, then click Enchant. It starts off. Turn it on in Settings, on the Look page.

Fixes and changes:

- The craft pane steps aside for your character window, so you can click your gear to enchant it.

## 1.10.0

- Two new settings let Tradeskills stay shut at the auction house and beside your professions until you open it. Both start on. Find them in Settings, on the Auction House page.

Fixes and changes:

- Listings from your other account now count under this account's realm.

## 1.9.7

Fixes and changes:

- Characters on your second account now count as this realm.
- Use suggested only shows once you type your own price.
- The labels in the price box fit in full.

## 1.9.6

Fixes and changes:

- Plain cooking recipes no longer show up as cooldowns.

## 1.9.5

Fixes and changes:

- No more frame drops with the profession window open over a long session.

## 1.9.4

Fixes and changes:

- Vendor map pins show the material icon round and clear.

## 1.9.3

Fixes and changes:

- One Window keeps its size when it docks while folded.

## 1.9.2

Fixes and changes:

- Vendor map pins show the icon of the material to buy.

## 1.9.1

Fixes and changes:

- Various bug fixes for Tradeskills.

## 1.8.0

Fixes and changes:

- Added a Snipe tab to the Auction House. Snipe actively scans the AH for items posted under their usual price and alerts you. This is an early build of this feature, and it is off by default. You can turn it on in Settings > Auction House > Snipe Tab:.
- Various bug fixes for Tradeskills.

