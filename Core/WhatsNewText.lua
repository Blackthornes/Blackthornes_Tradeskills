-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.40.0", lines = {
        "A new Upgrades Only box on the profession window lists only the crafts that are upgrades for you.",
    } },
    { version = "1.39.0", lines = {
        "Windows fold into a round button with the Tradeskills badge.",
        "Minimums by Profession has a Disenchanting row.",
    } },
    { version = "1.38.0", lines = {
        "Panels and rows have a warm brown-black look.",
        "The main window has a slimmer frame.",
        "One-line rows can be Compact if you like.",
        "Item rows link in chat and try on gear.",
        "Recipes to Learn shows the Profit: choice.",
        "Tradeskills has a line in the game's Options.",
    } },
}
