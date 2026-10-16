-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.62.0", lines = {
        "The Characters tab splits Horde and Alliance, and shows level, rested XP, zone and time played.",
        "The mouse wheel can list and cancel at the auction house. It's off until you turn it on.",
        "The Sell list can hold back what your other Blackthornes addons need. It's off until you turn it on.",
        "With Farmer, the Gather tab shows how fast you farm a material, and Profit by method has a Farmed line.",
        "With Equipment, crafted gear that helps another of your characters says so.",
        "Profit shows gold a day in place of gold an hour.",
    } },
    { version = "0.61.0", lines = {
        "The Disenchanting tab has a Find a material view. Pick an enchanting material to see what gave it to you before and the best ways to get more.",
        "Overcutting posts just under a big stack when a few cheap ones sell first. It's off until you turn it on.",
        "The List Next button says what its next click does and shows the next stack when you hover it.",
        "Keep in stock also comes back down after 3 unsold rounds in a row. Settings lists what it changed, with a Reset.",
        "With Equipment, enchanting recipes get a green arrow when they beat what you wear.",
    } },
    { version = "0.60.0", lines = {
        "The Profit tab has a Your time view. It compares farming the materials, selling them as they are, and buying them, in gold an hour.",
        "Gear with a random suffix gets a price for each suffix.",
    } },
}
