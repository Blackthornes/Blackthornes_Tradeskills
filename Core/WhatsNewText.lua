-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.64.0", lines = {
        "A gold tracker is now available in Tradeskills. It's a small bar that adds up the gold on all your characters on this realm and side. You set a goal and watch the bar fill up. It's off until you turn it on.",
    } },
    { version = "0.63.0", lines = {
        "Crafts that help another of your characters only say so when you tick a new box on the Profit, Level Up and Queue tabs. It's off until you turn it on.",
    } },
    { version = "0.62.0", lines = {
        "The Characters tab splits Horde and Alliance, and shows level, rested XP, zone and time played.",
        "The mouse wheel can list and cancel at the auction house. It's off until you turn it on.",
        "The Sell list can hold back what your other Blackthornes addons need. It's off until you turn it on.",
        "With Farmer, the Gather tab shows how fast you farm a material, and Profit by method has a Farmed line.",
        "With Equipment, crafted gear that helps another of your characters says so.",
        "Profit shows gold a day in place of gold an hour.",
    } },
}
