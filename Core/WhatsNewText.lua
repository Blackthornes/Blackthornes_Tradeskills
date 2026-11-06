-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.12.0", lines = {
        "A Buy It button on the Snipe tab buys the top find.",
        "Snipe can watch your shopping lists. Pick My Lists under Watch.",
        "You can set the most you'll pay for each item on your lists.",
        "The Sell tab shows every item in your bags unless you hid it. Items it won't list say why.",
        "A Hidden button on the Sell tab shows what you hid, so you can bring items back.",
    } },
    { version = "1.11.0", lines = {
        "A new strip sits under the recipe in your Enchanting window. Pick an item, then click Enchant. It starts off. Turn it on in Settings, on the Look page.",
    } },
    { version = "1.10.0", lines = {
        "Two new settings let Tradeskills stay shut at the auction house and beside your professions until you open it. Both start on. Find them in Settings, on the Auction House page.",
    } },
}
