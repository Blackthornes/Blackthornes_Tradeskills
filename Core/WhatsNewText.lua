-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.27.0", lines = {
        "You can copy your recent auction prices to use on another computer, with new buttons on the Queue page.",
        "You can pick which TSM price to use, on the Sharing page. It starts on the recent price.",
        "You can keep disenchant lines out of chat with a new tick box on the Look page.",
        "Snipe pays in one click when you buy.",
    } },
    { version = "1.26.0", lines = {
        "Windows now remember where you drag them, so they come back in the same spot.",
        "A new button on the Look page puts every window back where it started.",
        "Gold an Hour shows whether buying the parts or making them earns more each hour. It starts off.",
        "You can group writs by the zone where you hand them in.",
        "TSM prices take over sooner, after your own scan is an hour old.",
    } },
    { version = "1.25.0", lines = {
        "Buy Sets fills a shopping list in whole sets and stops at the gold you pick.",
        "A new box mutes every sound from all the Blackthornes addons at once. It starts off.",
        "Recipes show whether the profit comes from the auction house, a vendor or disenchanting.",
        "You can skip a recipe on Road to 300, and the road picks the next one.",
        "The Queue shows how long your crafts will take.",
        "Tooltips can show what you paid at the auction house, and Recipes to Learn shows demand.",
    } },
}
