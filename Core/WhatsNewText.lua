-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.52.0", lines = {
        "Tradeskills speaks Deutsch now if your game is in German.",
        "Got TradeSkillMaster or Auctionator? Their prices now fill in anything you haven't scanned yet.",
        "The note about overpriced listings after a scan is one short line now.",
        "Fixed your items sometimes being counted twice on a character you played before last names.",
    } },
    { version = "0.51.0", lines = {
        "See how much you made from crafting, flipping, vendoring and disenchanting, all split out on the Sales tab.",
    } },
    { version = "0.50.0", lines = {
        "Sold something? You'll hear an old cash register now. You can pick another sound or turn it off.",
        "Crate and writ prices go blank when none are for sale.",
        "Works on German game clients too.",
    } },
}
