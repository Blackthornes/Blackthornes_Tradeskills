-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.25.0", lines = {
        "Buy Sets fills a shopping list in whole sets and stops at the gold you pick.",
        "A new box mutes every sound from all the Blackthornes addons at once. It starts off.",
        "Recipes show whether the profit comes from the auction house, a vendor or disenchanting.",
        "You can skip a recipe on Road to 300, and the road picks the next one.",
        "The Queue shows how long your crafts will take.",
        "Tooltips can show what you paid at the auction house, and Recipes to Learn shows demand.",
    } },
    { version = "1.24.0", lines = {
        "New Reset button in Settings to bring every window back if one gets lost.",
        "Road to 300 plans smarter steps when you pick Real Cost.",
    } },
    { version = "1.23.0", lines = {
        "There is a new little window called My Auctions. It shows everything you have up, and when something sells, the row lights up and slides away.",
        "It starts off. You turn it on in Settings, on the Auction page.",
        "The Sales tab can show your sales by item, with totals for what you took in.",
        "You can clear what an old character was carrying, so you do not get sent to log in on it.",
    } },
}
