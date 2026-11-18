-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.34.0", lines = {
        "The craft queue and Shopping List show on the Crafting tab of the one window, and only while something is queued.",
    } },
    { version = "1.33.0", lines = {
        "Star the recipes you want to learn, and vendors and trainers tell you when they teach one.",
        "Each profession can have its own minimum profit.",
        "The Profit tab has a new All Recipes view, and soulbound crafts get a price.",
        "Material tooltips show which professions use them.",
        "Butler's leveling help now covers Cooking and First Aid.",
        "Various bug fixes for Tradeskills.",
    } },
    { version = "1.32.0", lines = {
        "There's a Post at Minimum Profit box on the Pricing page. It lists your crafts at the lowest price that still makes your Minimum Profit. It starts off.",
        "There's a TSM Sold a Day box on the Pricing page. It takes the Sold a day number on tooltips from TSM. It starts off.",
    } },
}
