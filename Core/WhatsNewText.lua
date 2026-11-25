-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.47.0", lines = {
        "Profit Now on the item tooltip uses what one costs to make today, and shows for any item a recipe makes.",
        "Hovering a craft's profit in the Craft queue shows the profit for one craft.",
    } },
    { version = "1.46.0", lines = {
        "The Stats page lists suffixes under each item.",
    } },
    { version = "1.45.0", lines = {
        "Buy One buys the next listing as soon as you click it again.",
        "The Sales tab keeps 60 days of sales, up to 2,000.",
    } },
}
