-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.58.0", lines = {
        "Enchanting recipes show what their materials cost when you hover them.",
        "The auction house Buy view has a Search all button for everything on your list.",
    } },
    { version = "0.57.0", lines = {
        "A new Stats tab shows one item at a time in charts: price, sales, cheapest times and who else sells it.",
        "The auction house drawer has shopping Lists and an Auctions view that shows which of your auctions were undercut.",
        "The Prices tab has a trend column, and item tooltips show how the price has moved.",
        "Craft next can make what frees the most bag space first.",
    } },
    { version = "0.56.0", lines = {
        "The auction house panel has a box to pick how long your listings stay up.",
    } },
}
