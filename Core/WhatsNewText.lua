-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.8.0", lines = {
        "There's a new Snipe tab in the auction house window. It looks for items selling well under their usual price and lets you buy the best one with a click. It never starts on its own, and you set how much it can spend. It's off until you tick \"Snipe Tab:\" in the auction house settings.",
        "In the money boxes, Tab now jumps from gold to silver to copper.",
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
