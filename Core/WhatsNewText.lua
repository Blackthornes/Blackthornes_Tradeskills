-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.8.0", lines = {
        "Added a Snipe tab to the Auction House. Snipe actively scans the AH for items posted under their usual price and alerts you. This is an early build of this feature, and it is off by default. You can turn it on in Settings > Auction House > Snipe Tab:.",
    } },
    { version = "1.7.0", lines = {
        "When you hover an item you can disenchant, the tooltip now shows what each material is worth.",
    } },
    { version = "1.6.0", lines = {
        "The window stays next to the auction house now.",
        "Item icons get a soft ring in the color of their quality.",
        "Road to 300 counts what your other characters hold.",
        "You get asked before a listing goes up far under the usual price.",
        "A new box lets you list items even when they would normally wait.",
    } },
}
