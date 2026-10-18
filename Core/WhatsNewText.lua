-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.66.0", lines = {
        "Tradeskills speaks Simplified Chinese, French, Spanish and Russian now if your game is in one of those.",
    } },
    { version = "0.65.0", lines = {
        "Right-click an item on the Sell list to keep some of it on the character you are playing. Your keeps are listed under Keep on This Character on the Queue page of Settings.",
    } },
    { version = "0.64.0", lines = {
        "A gold tracker is now available in Tradeskills. It's a small bar that adds up the gold on all your characters on this realm and side. You set a goal and watch the bar fill up. It's off until you turn it on with Gold Tracker on the Look page of Settings.",
    } },
}
