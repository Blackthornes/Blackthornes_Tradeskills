-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
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
    { version = "0.54.0", lines = {
        "At the auction house, your sell list and Scan sit in one drawer beside the window, with a List all button.",
        "Favors and Writs has a QTY column: how many others listed at that price.",
        "In travel form or another shapeshift, the Craft button reads Leave form. One click leaves the form, the next one crafts.",
    } },
}
