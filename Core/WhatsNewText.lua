-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
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
    { version = "1.22.0", lines = {
        "Your Potential Sale Total now shows the whole Sell list right away and stays steady while you post.",
        "Profit now counts every item in a stack, so big stacks no longer look like huge wins.",
        "Sales with no known cost are kept out of your profit.",
        "Working Overtime and Performance Bonus now count in your skill point and Merchant's Favor numbers.",
    } },
}
