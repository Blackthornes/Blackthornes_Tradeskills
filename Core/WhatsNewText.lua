-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.19.0", lines = {
        "Fishing now goes all the way to 300 on the Road to 300. It shows the pole, the lure and the best spot for each step. Find it in the profession drop-down on the Level Up tab.",
        "Recipes to Learn and Your Time can show the price graph now. Use the button on the heading. It also tells you when a recipe pays for itself.",
    } },
    { version = "1.18.0", lines = {
        "Cooking and First Aid now go all the way to 300 on the Road to 300, with the Expert and Artisan steps. Find them in the profession drop-down on the Level Up tab.",
    } },
    { version = "1.17.0", lines = {
        "The Sell tab has a Crafted Only tick box. Tick it and you only see things your own recipes make. It starts off.",
    } },
}
