-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
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
    { version = "1.2.0", lines = {
        "Price limits: a Never Below price on the Prices tab can have a Highest price and a When Cheaper choice. A list's Rules window also takes Lowest Price as a percent of market or cost.",
        "Sale Total on the Sell drawer shows what your Sell list would bring in at today's prices, and counts up after each scan. Turn it off with Sale Total on the Auction House page.",
    } },
}
