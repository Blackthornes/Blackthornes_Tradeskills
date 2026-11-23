-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.41.0", lines = {
        "A new Queue From Sell List box in Settings puts crafts that Craft First holds back into your queue. It starts off.",
    } },
    { version = "1.40.0", lines = {
        "A new Upgrades Only box on the profession window lists only the crafts that are upgrades for you.",
    } },
    { version = "1.39.0", lines = {
        "Windows fold into a round button with the Tradeskills badge.",
        "Minimums by Profession has a Disenchanting row.",
    } },
}
