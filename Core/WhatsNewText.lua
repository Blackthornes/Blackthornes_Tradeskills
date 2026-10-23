-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.69.0", lines = {
        "Set a Favor Goal on the Favors and Writs tab and Tradeskills shows the cheapest way to get there. The Favors switch at the auction house only shows up after you set a goal.",
        "Road to 300 lays out your whole way to 300 for a profession. A Welcome card shows the first time you open the window.",
        "Level Up shows your profession's skill on every view, and a Can Afford box leaves out crafts you can't pay for.",
        "My Auctions shows how many auctions at your price sell before yours.",
        "Goblin Gold shows where this week's gold came from, and it can count only the character you're on.",
    } },
    { version = "0.68.0", lines = {
        "Rules for a whole shopping list. Each list can mail what's on it to one of your characters and keep a number of each on every character.",
        "Goblin Gold has a Transparent choice. It's on the Look page of Settings.",
        "Favors and Writs shows what's on the auction house for each item.",
        "Tradeskills learns what your sealed writs open into.",
        "With Butler, your best next skill point shows in Butler's Jobs, and Butler says when a craft you know earns more than selling.",
    } },
    { version = "0.67.0", lines = {
        "Gold pins on the world map show vendors that sell what your queue needs for less than the auction house. It's off until you turn on Vendor Map Pins on the Mail & Vendors page of Settings.",
        "Favors and Writs has a Search Both button, a Buy box, a Make tag when making is cheaper, and a column for how many you have.",
        "Each tooltip line Tradeskills adds can be Off, Shift or Always. You pick on the Look page of Settings.",
        "The Characters tab can show one realm at a time.",
    } },
}
