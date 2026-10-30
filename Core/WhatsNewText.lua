-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.5.0", lines = {
        "All your Blackthornes addons now share one window. A strip down the left has a button for each addon you have, and the tabs of the one you pick sit beside it. At the auction house, mailbox, vendor and trainer it sits next to the game's window, and it goes back when you close that one. Turn it off with One Window on the General page.",
        "At the auction house the window has an Auction House tab for selling, buying, lists, your auctions and favors, next to Prices, Profit, Queue, Disenchanting and Favors and Writs.",
    } },
    { version = "1.4.0", lines = {
        "Profit, Level Up and the auction house views are tabs now, so they are easier to find.",
        "Stats moved into the Prices tab.",
        "Right-click a row in Profit, Level Up, Deals or Disenchanting for a quick menu.",
        "Settings has a new General page.",
    } },
    { version = "1.3.0", lines = {
        "One minimap button now covers every Blackthornes addon you have. Click it to pick one. Turn it off with Combine Addon Buttons on the Look page.",
        "Tooltips list what an item can disenchant into, with the count and chance. Disenchant Results on Tooltips on the Look page picks Off, Shift or Always.",
    } },
}
