-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.60.0", lines = {
        "The Profit tab has a Your time view. It compares farming the materials, selling them as they are, and buying them, in gold an hour.",
        "Gear with a random suffix gets a price for each suffix.",
    } },
    { version = "0.59.0", lines = {
        "Listing on the auction house is faster.",
    } },
    { version = "0.58.0", lines = {
        "Enchanting recipes show what their materials cost when you hover them.",
        "The auction house Buy view has a Search all button for everything on your list.",
    } },
}
