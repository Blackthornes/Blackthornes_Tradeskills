-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.36.0", lines = {
        "Random suffix items open on the Prices tab to show a price for each suffix.",
    } },
    { version = "1.35.0", lines = {
        "Every window has a gold gem on its title bar. Click it to switch between the one window and separate windows.",
        "Road to 300 learns the recipes a profession trainer teaches when you open one.",
    } },
    { version = "1.34.0", lines = {
        "The craft queue and Shopping List show on the Crafting tab of the one window, and only while something is queued.",
    } },
}
