-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.53.1", lines = {
        "Transmute cooldowns pick the one you can actually make.",
        "Learn next keeps its shopping list and finds your zone's trainer in Deutsch.",
        "Trade chat requests from someone with your first name show up now.",
    } },
    { version = "0.53.0", lines = {
        "A new What's New window shows what changed after each update.",
        "Tradeskills now tracks your transmute and other cooldowns on every character.",
        "The Level Up tab tells you which recipe to learn next and shows you the way to the trainer.",
        "Recipe levels and materials now match Forever.",
        "Want to know when someone in Trade needs something you can make? Turn it on in Settings.",
        "Shift-click any item to search for it on the auction house.",
    } },
    { version = "0.52.0", lines = {
        "Tradeskills speaks Deutsch now if your game is in German.",
        "Got TradeSkillMaster or Auctionator? Their prices now fill in anything you haven't scanned yet.",
        "The note about overpriced listings after a scan is one short line now.",
        "Fixed your items sometimes being counted twice on a character you played before last names.",
    } },
}
