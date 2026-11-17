-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.32.0", lines = {
        "There's a Post at Minimum Profit box on the Pricing page. It lists your crafts at the lowest price that still makes your Minimum Profit. It starts off.",
        "There's a TSM Sold a Day box on the Pricing page. It takes the Sold a day number on tooltips from TSM. It starts off.",
    } },
    { version = "1.31.0", lines = {
        "There's a Crate Shopping List for Waylaid Crates on the auction house Buy tab. It starts off.",
        "The craft pane and mail list can be tabs in the one window.",
        "A slim craft strip sits inside the profession window when there's no room beside it.",
        "The Queue page and Settings are sorted into clearer groups, with an All Addons page.",
        "The window can dock in more places and you can resize it by hand.",
    } },
    { version = "1.30.0", lines = {
        "The Sales tab has a new Bought view. It shows what you spent at the auction house, what you bought most, and what you paid each.",
    } },
}
