-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.67.0", lines = {
        "Gold pins on the world map show vendors that sell what your queue needs for less than the auction house. It's off until you turn on Vendor Map Pins on the Mail & Vendors page of Settings.",
        "Favors and Writs has a Search Both button, a Buy box, a Make tag when making is cheaper, and a column for how many you have.",
        "Each tooltip line Tradeskills adds can be Off, Shift or Always. You pick on the Look page of Settings.",
        "The Characters tab can show one realm at a time.",
    } },
    { version = "0.66.0", lines = {
        "Tradeskills speaks Simplified Chinese, French, Spanish and Russian now if your game is in one of those.",
    } },
    { version = "0.65.0", lines = {
        "Right-click an item on the Sell list to keep some of it on the character you are playing. Your keeps are listed under Keep on This Character on the Queue page of Settings.",
    } },
}
