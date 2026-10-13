-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.54.0", lines = {
        "At the auction house, your sell list and Scan sit in one drawer beside the window, with a List all button.",
        "Favors and Writs has a QTY column: how many others listed at that price.",
        "In travel form or another shapeshift, the Craft button reads Leave form. One click leaves the form, the next one crafts.",
    } },
    { version = "0.53.0", lines = {
        "Tradeskills tracks transmutes and other profession cooldowns on all your characters, and tells you when one is ready.",
        "The Level Up tab lists which recipe to learn next and where. Show the way puts the trainer on your map.",
        "Recipe levels and materials match Forever.",
        "Shift-click any item to search for it at the auction house.",
        "If you turn it on in Settings, chat tells you when someone in Trade asks for something you can make.",
    } },
    { version = "0.52.0", lines = {
        "Tradeskills is in Deutsch on a German client.",
        "With TradeSkillMaster or Auctionator installed, their prices fill in items you haven't scanned.",
    } },
}
