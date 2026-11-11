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

