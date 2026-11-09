-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.21.0", lines = {
        "Each find on the Snipe list has a Buy button that shows what you'll pay.",
    } },
    { version = "1.20.0", lines = {
        "The Recipe Book shows which vendor sells a trade camp recipe, what it costs and the standing it needs.",
        "Hover a material in the Recipe Book or Your Time to see the item's tooltip.",
    } },
    { version = "1.19.0", lines = {
        "Fishing now goes all the way to 300 on the Road to 300. It shows the pole, the lure and the best spot for each step. Find it in the profession drop-down on the Level Up tab.",
        "Recipes to Learn and Your Time can show the price graph now. Use the button on the heading. It also tells you when a recipe pays for itself.",
    } },
}
