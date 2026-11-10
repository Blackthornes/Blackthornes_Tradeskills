-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.22.0", lines = {
        "Your Potential Sale Total now shows the whole Sell list right away and stays steady while you post.",
        "Profit now counts every item in a stack, so big stacks no longer look like huge wins.",
        "Sales with no known cost are kept out of your profit.",
        "Working Overtime and Performance Bonus now count in your skill point and Merchant's Favor numbers.",
    } },
    { version = "1.21.0", lines = {
        "Each find on the Snipe list has a Buy button that shows what you'll pay.",
    } },
    { version = "1.20.0", lines = {
        "The Recipe Book shows which vendor sells a trade camp recipe, what it costs and the standing it needs.",
        "Hover a material in the Recipe Book or Your Time to see the item's tooltip.",
    } },
}
