-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.30.0", lines = {
        "The Sales tab has a new Bought view. It shows what you spent at the auction house, what you bought most, and what you paid each.",
    } },
    { version = "1.29.0", lines = {
        "Butler can tell you why an item should wait, and Sell Anyway sells it when you disagree.",
        "A new goal window helps you pick your next gold goal.",
        "Profit shows your crafted sales by profession and by character.",
        "You can pause crafts in the Queue, move them, and skip ones that need a tool.",
        "There is a new price box for gear that binds when worn, on the Sharing page.",
        "The game's profession window can show what a craft costs and earns. It starts off.",
    } },
    { version = "1.27.0", lines = {
        "You can copy your recent auction prices to use on another computer, with new buttons on the Queue page.",
        "You can pick which TSM price to use, on the Sharing page. It starts on the recent price.",
        "You can keep disenchant lines out of chat with a new tick box on the Look page.",
        "Snipe pays in one click when you buy.",
    } },
}
