-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.44.0", lines = {
        "The Craft queue has an Upgrades Only box that lists only crafts that make an upgrade for you.",
        "Your Way There is now a small see-through box with only your current step and a dial that points the way.",
    } },
    { version = "1.43.0", lines = {
        "Buy One on the Disenchanting tab buys the cheapest listing on each click, with no pop-up. You can bind a key to it.",
        "Each random suffix on the Prices tab has its own My Price, and item cards and Sales show the suffix name.",
        "The Sell list keeps its order while the auction house is open.",
        "Disenchants at an Arcane Salvager are kept in their own record from the start. The addon spots the Salvager by its buff.",
    } },
    { version = "1.42.0", lines = {
        "The All Addons page in Settings has a Set Default button. Click Confirm and this addon's settings go back to how they started.",
    } },
}
