-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.49.0", lines = {
        "The Profit tab shows a 7 Days price line, a sell-speed bar and three cards. Click any profit to see how it adds up.",
        "Road to 300 has Stop At buttons, Fewest Materials, No Auction House and Skip on each step.",
        "The Queue has Sort By chips and an optional chime when it is done.",
        "My Auctions lists today's sales under Sold Today.",
        "Pick how Tradeskills opens at the auction house, a profession and the mailbox.",
        "New Font, Colors and Fold Gem choices on the All Addons page.",
    } },
    { version = "1.48.0", lines = {
        "Vendor prices count the Bartering perk.",
        "The item tooltip shows what an item costs to make now, above Profit Now.",
        "Stock you bought is costed at what you paid and shows under Flipped.",
        "Lucky disenchants at an Arcane Salvager say so again, with the sound.",
    } },
    { version = "1.47.0", lines = {
        "Profit Now on the item tooltip uses what one costs to make today, and shows for any item a recipe makes.",
        "Hovering a craft's profit in the Craft queue shows the profit for one craft.",
    } },
}
