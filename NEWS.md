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

## 0.57.0

- A new Stats tab shows one item at a time in charts: price, sales, cheapest times and who else sells it.
- The auction house drawer has shopping Lists and an Auctions view that shows which of your auctions were undercut.
- The Prices tab has a trend column, and item tooltips show how the price has moved.
- Craft next can make what frees the most bag space first.

Fixes and changes:

- The tabs are in a new order.
- A 14 day price graph.
- Ctrl-right-click a craft in the profession pane to ignore it.
- Vendor materials with limited stock can still be searched on the auction house.
- Butler can buy the queue's materials at a vendor.

## 0.56.0

- The auction house panel has a box to pick how long your listings stay up.

Thanks Draffon for the idea!

## 0.55.1

Fixes and changes:

- The Profit tab shows how many of a craft Queue All plans to keep, based on what you sold this week, and you can turn that off.
- Adding one to your stock when a craft sells out is off until you turn it on.

Thanks Voldar for the report!

## 0.55.0

- This is the largest AddOn update so far across the whole suite of Blackthornes addons.
- You can set how many of an item to keep in stock for a whole profession, not just one item at a time.
- When all of a craft you listed sells out, Tradeskills adds one to how many it keeps in stock.
- Item tooltips show more about sales: how many sell a day, how many are listed, and how you did this week.
- For a part you craft, you can pick Vendor, Make or Buy on the Level Up tab.
- Settings has an About page with the Discord invite and how to report a bug.

Fixes and changes:

- Materials a vendor sells go to the vendor, not the auction house.
- Butler's job list puts the mailbox first when mail is waiting.
- Long craft names no longer cover the rows around them.

## 0.54.0

- At the auction house, your sell list and Scan sit in one drawer beside the window, with a List all button.
- Favors and Writs has a QTY column: how many others listed at that price.
- In travel form or another shapeshift, the Craft button reads Leave form. One click leaves the form, the next one crafts.

Fixes and changes:

- The Deals tab is called Favors and Writs.
- Listing different items is much faster.
- Fixes for Tailoring, the Level Up columns and the Profit graphs.

Thanks Ezmode, Voldar and Draffon for the ideas and reports!

## 0.53.1

Fixes and changes:

- Transmute cooldowns pick the one you can actually make.
- Learn next keeps its shopping list and finds your zone's trainer in Deutsch.
- Trade chat requests from someone with your first name show up.

## 0.53.0

- Tradeskills tracks transmutes and other profession cooldowns on all your characters, and tells you when one is ready.
- The Level Up tab lists which recipe to learn next and where. Show the way puts the trainer on your map.
- Recipe levels and materials match Forever.
- Shift-click any item to search for it at the auction house.
- If you turn it on in Settings, chat tells you when someone in Trade asks for something you can make.

## 0.52.0

- Tradeskills is in Deutsch on a German client.
- With TradeSkillMaster or Auctionator installed, their prices fill in items you haven't scanned.

Fixes and changes:

- The note about overpriced listings after a scan is one short line.
- Fixed your items sometimes being counted twice on a character you played before last names.

## 0.51.0

- See how much you made from crafting, flipping, vendoring and disenchanting, all split out on the Sales tab.

Thanks Ezmode for the idea!

## 0.50.0

- Sold something? You'll hear an old cash register now. You can pick another sound or turn it off.
- Crate and writ prices go blank when none are for sale.
- Works on German game clients too.

## 0.49.2

- The Disenchanting tab won't show deals that are already gone anymore. Buy the last one and the row moves to the next price or goes away.

Thanks Ezmode for the report!

## 0.49.1

- Demand now reads the same no matter how often you scan the auction house.

## 0.49.0

- Buying materials at the auction house now warns you when the price has jumped past what your shopping list expected.
- Crafting a batch with the queue open is smoother.
- Fixed finished sub-crafts staying in the queue, and some characters showing up twice.

Thanks Voldar and Sullivan for the report!

## 0.48.0

- Farmer goals you set from your queue now keep up with it on their own.
- Keep in stock learns what sells for you, and a sale queues another one.
- No disenchanter typed in? Your best enchanter alt gets picked for you.
- Crafted gear doesn't get mailed off to be disenchanted anymore.

## 0.47.0

- Things you buy to disenchant are marked now. They go to the top of your bags list, and the Disenchant button breaks them first.
- New deals only get the NEW tag when they're really new.
- The mailbox won't try to mail the character you're on anymore.

## 0.46.0

- Material costs are more honest now. If you need 20 and only 3 are cheap, the rest are priced at what they really cost.
- After you buy at the auction house, you'll see what you actually paid. It turns amber if you paid a lot more than expected.
- New deals get a NEW tag, and you can show only the new ones.
- You can hide the items that would sell at a loss.
- Mail to your alts sends just what they need, not the whole stack.
- Characters show their full names, and the emblem got a fresh look.

Thanks Voldar for the ideas and reports!

## 0.45.2

- The Blizzard window look got a little cleanup: the open tab looks right now.

## 0.45.1

- Gold sent between your own characters doesn't mess up the gold chart anymore.
- Auction buys and mail to your alts are counted right on the shopping list and queue.
- Lots of small fixes, and the bank, vendor and mailbox windows are a bit lighter.

## 0.45.0

- You can pick a new window look that matches the game's own windows. The gold look is still the default.
- Lists are calmer now. The gold glow only shows on the row under your mouse.
- The queue can wait until you're almost out of something before it makes more, and things that sell fast can keep a few extra.
- When you buy at the auction house, the amount you need stays put instead of going back to 1.
- The bank time on the Queue tab is right now, plus a bunch of other fixes.

## 0.44.0

Hey everyone! A small Tradeskills update just went up.

If you use Equipment too, you can send a crafted upgrade straight to your queue now. If you can make it, it's queued. If you can't, the materials or the gear itself go on your shopping list. Thanks Ezmode for the idea!

A quick /reload after you update is all you need. Have fun!

## 0.43.0

Hey everyone! Another Tradeskills update just went up.

Merchant's Favor bundles are priced right now, even right after a fresh scan. Gold per hour only shows for recipes you can actually make. The Settings buttons don't spill into the next column anymore. And you can see which version you have at the top of the window and on the minimap button. Ezmode asked for all of these. Thanks Ezmode!

Hovering over items is lighter on your game now. Thanks Lottus27 for telling us about the lag!

A few more fixes: things you bought on the auction house count toward your queue while they wait in the mail, crafting a bunch in a row doesn't make the game stutter anymore, and the Buy instead button works again.

Restart the game fully after you update. Have fun!

## 0.42.0

Hey everyone! A big Tradeskills update just went up.

Craftsman's Writs are on the Deals tab now. Pick the standing you want and it tells you how many writs it takes and the cheapest way to get there. Thanks Ezmode for asking for this one!

You can see how long a craft takes and how much gold it makes an hour, on crafting and on disenchanting. Thanks Sullivan and Ezmode for the idea!

You can hide the columns you don't use. Just right-click the headings. Thanks Ezmode!

The price graph shows how many were listed each hour and a line for the average price. Thanks Sullivan!

Level Up now counts profit the same way you picked on the Profit tab. Thanks Sullivan!

There's a button to turn undercutting off if you'd rather match the cheapest price. Thanks Voldar and Sullivan!

Your alts' sub-crafts show up on Level Up now, and you can mark any craft to always buy instead. Thanks Voldar!

Recipes show the skill level Forever really asks for. Thanks Voldar for spotting the Leatherworking ones!

Deals knows what vendors really pay now, so Minor Wizard Oil isn't a fake flip anymore. Thanks kickemhard for catching it!

Green weapons from level 21 to 30 now show the Greater Magic Essence they really give. Thanks Ezmode for noticing!

The skill colours on Level Up don't go grey after you log in anymore. Thanks Voldar!

Restart the game fully after you update. Have fun!
