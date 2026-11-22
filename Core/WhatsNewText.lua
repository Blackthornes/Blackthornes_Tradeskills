-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.38.0", lines = {
        "Panels and rows have a warm brown-black look.",
        "The main window has a slimmer frame.",
        "One-line rows can be Compact if you like.",
        "Item rows link in chat and try on gear.",
        "Recipes to Learn shows the Profit: choice.",
        "Tradeskills has a line in the game's Options.",
    } },
    { version = "1.37.0", lines = {
        "The Buy Materials button stays on the vendor window when Butler is loaded.",
        "Each suffix on the Prices tab shows its own price graph and Stats.",
        "Sales of stacks and other items are filed under their item, on one row.",
    } },
    { version = "1.36.0", lines = {
        "Random suffix items open on the Prices tab to show a price for each suffix.",
    } },
}
