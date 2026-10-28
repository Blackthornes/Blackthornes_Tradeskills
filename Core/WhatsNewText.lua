-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.2.0", lines = {
        "Price limits: a Never Below price on the Prices tab can have a Highest price and a When Cheaper choice. A list's Rules window also takes Lowest Price as a percent of market or cost.",
        "Sale Total on the Sell drawer shows what your Sell list would bring in at today's prices, and counts up after each scan. Turn it off with Sale Total on the Auction House page.",
    } },
    { version = "1.1.0", lines = {
        "Road to 300 has Pick By: Lowest Cost or Real Cost. Real Cost counts what selling your crafts brings back.",
    } },
    { version = "1.0.0", lines = {
        "Shuffles on the Profit tab: pick something in your bags and see every way to turn it into gold, with the best place to stop.",
        "Guild Crafters shows guildmates online who can make a craft. It's off until you tick it on the Sharing page.",
        "Coin bags from writ turn-ins are valued, so Money Back is more exact.",
        "A part only one of your alts can make is priced at that alt's materials.",
        "Road to 300 queues a bought recipe's crafts once you learn it.",
        "Price Order on the Sharing page picks whether TSM or Auctionator is asked first. TSM comes first unless you change it.",
        "Arrow Size picks 50%, 75% or 100% for the guide arrow.",
        "A small gem beside the close button folds a window down to its title.",
    } },
}
