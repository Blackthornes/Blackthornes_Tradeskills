-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.42.0", lines = {
        "The All Addons page in Settings has a Set Default button. Click Confirm and this addon's settings go back to how they started.",
    } },
    { version = "1.41.1", lines = {
        "Road to 300 names the city for Undercity, Thunder Bluff and Darnassus trainers.",
        "Scans finish without a freeze, and the Profit and Prices searches are quicker.",
    } },
    { version = "1.41.0", lines = {
        "A new Queue From Sell List box in Settings puts crafts that Craft First holds back into your queue. It starts off.",
    } },
}
