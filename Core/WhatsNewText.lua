-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.51.0", lines = {
        "The Snipe tab is faster. It shows your last scan's deals first and tells you how far along it is.",
        "Vendor Price For lets you choose which item colors count a vendor price on the Sell list.",
        "Shift-click List lists one row anyway, and Shift-click + queues all your bags can make.",
        "A Lists button opens your shopping lists away from the auction house.",
        "Crafts with a wait, like Mooncloth, count once per wait on the Profit tab.",
    } },
    { version = "1.50.0", lines = {
        "Recipe tooltips show which of your other characters can learn the recipe.",
        "Butler can mail your alts the materials for their Road to 300. It is off unless ticked.",
        "Butler can mail a recipe to the alt who can learn it. It is off unless ticked.",
        "You can leave an alt out of both.",
    } },
    { version = "1.49.1", lines = {
        "The Sell list shows your other copies of an item when one copy is soulbound.",
    } },
}
