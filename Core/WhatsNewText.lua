-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.0.0", lines = {
        "Shuffles on the Profit tab: pick something in your bags and see every way to turn it into gold, with the best place to stop.",
        "Guild Crafters shows guildmates online who can make a craft. It's off until you tick it on the Sharing page.",
        "Coin bags from writ turn-ins are valued, so Money Back is more exact.",
        "A part only one of your alts can make is priced at that alt's materials.",
        "Road to 300 queues a bought recipe's crafts once you learn it.",
        "Price Order on the Sharing page picks whether TSM or Auctionator is asked first. TSM comes first unless you change it.",
        "Arrow Size picks 50%, 75% or 100% for the guide arrow.",
        "A small gem beside the close button folds a window down to its title.",
    } },
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
}
