# Snipe tab handoff

Built 2026-11-03 from the approved mockup and spec. A full restart is needed (files added, TOC changed).

## What it is
A Snipe view tab in the auction house drawer (`UI/PostPanel.lua`). Off by default: "Snipe Tab:" on the auction page of Settings (`snipeTab`).

- Logic: `Logic/Snipe.lua`. View: `UI/SnipeView.lua`. Sound: `Media/Sounds/snipe-bell-single.ogg`.
- Hook: `Data/Scanner.lua` hands browse results to `Snipe:OnBrowseResults` inside a pcall.
- Wheel: `UI/AuctionWheel.lua`. "Wheel Buys:" (`snipeWheel`) binds wheel up to Snipe's BuyNext on the Snipe tab only.
- Money boxes: Tab moves g, s, c, then the next box (`UI/Widgets.lua`, `UI/PriceEditor.lua`).
- Saved, account wide, never rename: `snipeTab`, `snipeCap`, `snipePct`, `snipeSound`, `snipeWatch`, `snipeStripOpen`, `snipeWheel`.

## Below Vendor (2026-11-03)
A player asked; Trent said build it. A third Watch: choice, "Below Vendor" (`snipeWatch` = "vendor"). Worth is `Disenchant:GetSellPrice`, the same vendor price the Deals tab's vendor flips use (a Forever sale beats the game's number). No auction house cut, greys count, no smallest worth or silly-average check, and an item whose price `Disenchant:SellPriceUnsure` calls unsure (charges) is left out. Any listing under the vendor price is a find (`Snipe.IsDealFor`), so Snipe Below greys out in this mode. Finds sort by profit a unit (`Snipe.Better`, `Snipe.Profit`); the row's badge shows that profit and the heads read "Vendor" and "Profit" (words already in the addon). Hover: "%1$s each, a vendor pays %2$s". Spending Cap, Start/Stop and the bell are unchanged. Lists are not searched (not approved). Tested in `tools/test_snipe.lua` (10, 11).

## Rules kept
Never starts by itself. Ends on Stop, the auction house closing, or the cap. Small searches, one at a time, cheapest page, held while the player sells or buys. Big buys ask "Click Again". Nothing touches a Blizzard frame. Tested in `tools/test_snipe.lua`.

## Words awaiting Trent's yes (not in the approved spec)
"Set a Spending Cap first.", "Nothing to snipe yet. Scan the auction house first.", "that item", "%1$s each, worth %2$s", "%1$d for sale. %2$s", "Click Again", "Pay %s", "Asking...", "%d%% under", "% of worth", "Looking for deals...", "Spent: %1$s of %2$s", "%d finds", "Snipe", "Item", "Price", "Deal", "Start Sniping", "Stop", "SNIPE SETTINGS", "Spending Cap:", "Snipe Below:", "Watch:", "Priced Items", "To Disenchant", "Snipe Sound", "You need %s for that.", the cap message, "Snipe Tab:", "Wheel Buys:" and "On the Snipe tab, wheel up buys the best find."

The five translations were written by us from the English keys and need his okay too.

## Not yet seen in game
Everything. Unchecked: the To Disenchant and Below Vendor modes against real results, and drawer sizing with the strip open at One Window.
