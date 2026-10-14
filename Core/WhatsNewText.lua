-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.57.0", lines = {
        "A new Stats tab shows one item at a time in charts: price, sales, cheapest times and who else sells it.",
        "The auction house drawer has shopping Lists and an Auctions view that shows which of your auctions were undercut.",
        "The Prices tab has a trend column, and item tooltips show how the price has moved.",
        "Craft next can make what frees the most bag space first.",
    } },
    { version = "0.56.0", lines = {
        "The auction house panel has a box to pick how long your listings stay up.",
    } },
    { version = "0.55.0", lines = {
        "This is the largest AddOn update so far across the whole suite of Blackthornes addons.",
        "You can set how many of an item to keep in stock for a whole profession, not just one item at a time.",
        "When all of a craft you listed sells out, Tradeskills adds one to how many it keeps in stock.",
        "Item tooltips show more about sales: how many sell a day, how many are listed, and how you did this week.",
        "For a part you craft, you can pick Vendor, Make or Buy on the Level Up tab.",
        "Settings has an About page with the Discord invite and how to report a bug.",
    } },
}
