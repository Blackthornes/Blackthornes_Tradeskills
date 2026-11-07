-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.16.1", lines = {
        "If you play on two accounts, they now share the newest auction prices with each other. Nothing to turn on.",
    } },
    { version = "1.16.0", lines = {
        "Two accounts now show when they last synced, in Settings on the Sharing page and on the other account's tooltip.",
    } },
    { version = "1.15.0", lines = {
        "Snipe can buy the top deal with one click or one key. It never buys on its own.",
        "After a buy, Snipe keeps the item on top while more of it is a good deal.",
        "If you play on two accounts, they can now share sales and shopping lists. It stays off until you turn it on for both.",
    } },
}
