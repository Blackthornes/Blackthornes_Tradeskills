-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.4.0", lines = {
        "Profit and Level Up switch views with tabs, and so do Sell, Buy, Lists, Auctions and Favors at the auction house.",
        "Stats now sits inside the Prices tab as Details and Stats tabs.",
        "A right-click on a Profit, Level Up, Deals or Disenchanting row opens a menu with Queue One, Show the Way and more.",
        "A new General page holds Windows, Addons and Sounds.",
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
