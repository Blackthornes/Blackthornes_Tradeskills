-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.48.0", lines = {
        "Vendor prices count the Bartering perk.",
        "The item tooltip shows what an item costs to make now, above Profit Now.",
        "Stock you bought is costed at what you paid and shows under Flipped.",
        "Lucky disenchants at an Arcane Salvager say so again, with the sound.",
    } },
    { version = "1.47.0", lines = {
        "Profit Now on the item tooltip uses what one costs to make today, and shows for any item a recipe makes.",
        "Hovering a craft's profit in the Craft queue shows the profit for one craft.",
    } },
    { version = "1.46.0", lines = {
        "The Stats page lists suffixes under each item.",
    } },
}
