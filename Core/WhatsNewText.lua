-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.68.0", lines = {
        "Rules for a whole shopping list. Each list can mail what's on it to one of your characters and keep a number of each on every character.",
        "Goblin Gold has a Transparent choice. It's on the Look page of Settings.",
        "Favors and Writs shows what's on the auction house for each item.",
        "Tradeskills learns what your sealed writs open into.",
        "With Butler, your best next skill point shows in Butler's Jobs, and Butler says when a craft you know earns more than selling.",
    } },
    { version = "0.67.0", lines = {
        "Gold pins on the world map show vendors that sell what your queue needs for less than the auction house. It's off until you turn on Vendor Map Pins on the Mail & Vendors page of Settings.",
        "Favors and Writs has a Search Both button, a Buy box, a Make tag when making is cheaper, and a column for how many you have.",
        "Each tooltip line Tradeskills adds can be Off, Shift or Always. You pick on the Look page of Settings.",
        "The Characters tab can show one realm at a time.",
    } },
    { version = "0.66.0", lines = {
        "Tradeskills speaks Simplified Chinese, French, Spanish and Russian now if your game is in one of those.",
    } },
}
