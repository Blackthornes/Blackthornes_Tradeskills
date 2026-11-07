# Snipe tab handoff

Built 2026-11-03 from the approved mockup and spec. A full restart is needed (files added, TOC changed).

## What it is
A Snipe view tab in the auction house drawer (`UI/PostPanel.lua`). Off by default: "Snipe Tab:" on the auction page of Settings (`snipeTab`).

- Logic: `Logic/Snipe.lua`. View: `UI/SnipeView.lua`. Sound: `Media/Sounds/snipe-bell-single.ogg`.
- Hook: `Data/Scanner.lua` hands browse results to `Snipe:OnBrowseResults` inside a pcall.
- Wheel: `UI/AuctionWheel.lua`. "Wheel Buys:" (`snipeWheel`) binds wheel up to Snipe's BuyNext on the Snipe tab only.
- Money boxes: Tab moves g, s, c, then the next box (`UI/Widgets.lua`, `UI/PriceEditor.lua`).
- Saved, account wide, never rename: `snipeTab`, `snipeCap`, `snipePct`, `snipeSound`, `snipeWatch`, `snipeStripOpen`, `snipeWheel`, `snipeList`.

## Below Vendor (2026-11-03)
A player asked; Trent said build it. A third Watch: choice, "Below Vendor" (`snipeWatch` = "vendor"). Worth is `Disenchant:GetSellPrice`, the same vendor price the Deals tab's vendor flips use (a Forever sale beats the game's number). No auction house cut, greys count, no smallest worth or silly-average check, and an item whose price `Disenchant:SellPriceUnsure` calls unsure (charges) is left out. Any listing under the vendor price is a find (`Snipe.IsDealFor`), so Snipe Below greys out in this mode. Finds sort by profit a unit (`Snipe.Better`, `Snipe.Profit`); the row's badge shows that profit and the heads read "Vendor" and "Profit" (words already in the addon). Hover: "%1$s each, a vendor pays %2$s". Spending Cap, Start/Stop and the bell are unchanged. Lists are not searched (not approved). Tested in `tools/test_snipe.lua` (10, 11).

## Buying fixed (2026-11-06)
A player could not buy a Below Vendor find: clicks did nothing, Stop emptied the list, and chat said the auction house was busy. Three causes. Items sold one at a time (Malachite reads that way on Forever) only opened the game's own search, queued as "ui-search", which Snipe's own searches crowded out of `AHQueue`'s budget (8 sends in 15 s) until it gave up. Clicks only worked while running. Stop cleared the finds.
Now: Snipe waits while fewer than `Snipe.HEADROOM` (3) sends are left (`Snipe.CrowdsPlayer`, `AHQueue.BUDGET_MAX` exposed), and a buy cancels a queued snipe search so it waits behind the click. An item is asked about on its own (`Snipe:AskItem`, AHQueue key "snipe-buy", urgent, `SendSearchQuery` cheapest first); `Snipe:ItemResults` (ITEM_SEARCH_RESULTS_UPDATED) picks the cheapest listing not our own that is still a deal and fits the cap; Pay is `PlaceBid(auctionID, buyout)`, done on AUCTION_HOUSE_PURCHASE_COMPLETED or the purse dropping by the total (`MoneyMoved`), let go on AUCTION_HOUSE_SHOW_ERROR (`BuyError`). Stop keeps the finds; only the cap and the auction house closing clear them (`Stop(reason, clear)`, `Closed`). Buying works stopped or running. A gold **Buy It** button sits left of Start/Stop (`SnipeView:BuyTop`, `BuyState`): it asks about the top find, then reads "Pay X", "Click Again" for big ones, "Asking..." while it waits. New words: "That costs more than your Spending Cap has left." (awaits Trent's yes). Tested in `tools/test_snipe.lua` (12 to 14).

## My Lists (2026-11-06)
Trent said build it from the mockup. A fourth Watch: choice, "My Lists" (`snipeWatch` = "lists"), and a "List:" drop-down under it (All Lists or one list; `snipeList`, the list id, nil for All Lists; a deleted list reads as All Lists). The pool is the lists' items. Each item's limit: its own Most I'll Pay (new optional list item field `maxPay`, copper), else the list's maxPay rule, else worth times Snipe Below. First list that holds an item wins. An item drops out once you have what the list wants, and a buy never takes more. Heads: Item, Price, Most I'll Pay, Deal. Hover "%1$s each, you'll pay up to %2$s"; empty "Put items on a list first."; all had "Got all you need". The Lists view has a "Most I'll Pay:" money box per item (Tab g, s, c; Enter or Tab saves; Escape puts it back), "List rule, %s" when only the list's rule applies, and "Got all you need" dimmed. Labels share one measured column; Watch: and List: one measured width; the sort arrow has its own room beside each head (it sat on Price, Trent's screenshot). Tested in `tools/test_snipe.lua` (15) and `tools/test_snipelayout.lua`. Saved, never rename: `snipeList`, the list item's `maxPay`.

## One-click buying (2026-11-07)
Trent said build it from the spec (`specs/snipe-one-click.md`) and mockup. Nothing buys by itself: every `PlaceBid` and `ConfirmCommoditiesPurchase` still comes from a click, the key or a wheel turn.

- Ready before the click: while running or the Snipe list shows (`Snipe.viewShown`), `Snipe:Ready` (debounced by `ReadySoon`) asks about the top find quietly (`Buy(find, true)`, `pending.auto`). The top is the list's own order (`Snipe.topFn`, set by `SnipeView:SetShown`). An item is searched at urgent priority and its cheapest valid listing kept; a stack is quoted with `StartCommoditiesPurchase` from a timer. If the game refuses that (a pcall failure, or two quotes that never come), the stack is only "planned" and the quote is asked for on the click (`Snipe:Plan`, `noAutoStack`). `KeepFresh` asks again just before a quote runs out (`REQUOTE_BEFORE`, `READY_KEEP`); a new top lets the old ready go unless it is armed. A failed buy waits `RETRY_AFTER` before the find is tried again. Snipe's own searches rest three times longer while a ready deal waits, and a quiet ready never cancels the scan.
- Buy It reads "Buy %s x%d for %s" when ready, "Checking..." while it readies; the row says "Ready".
- Stay on the item: after a buy, a find with more deal listings stays on top (`pending.others`, `find.left`), its row showing "%d left", and is readied again.
- "Double Check Over:" money box (`snipeConfirmOver`, nil reads 10g): buys over it ask "Click Again".
- The list holds still under the mouse; new finds wait behind a "%d new" chip.
- Key binding "Snipe: Buy Top" (`BLACKTHORNESTS_SNIPEBUY`, `Snipe:BuyNext`).
- Search batches start bigger and step down when the game can't keep up.
- Saved, never rename: `snipeConfirmOver`.
- New words awaiting Trent's yes: "Buy %s x%d for %s", "Checking...", "%d left", "Double Check Over:", "%d new", "Snipe: Buy Top" ("Ready" was already in the addon). Their five translations are ours.
- Tested in `tools/test_snipe.lua` (16 to 20) and `tools/test_snipeready.lua`. Not yet seen in game.

## Rules kept
Never starts by itself. Ends on Stop, the auction house closing, or the cap; Stop keeps the list. Small searches, one at a time, cheapest page, held while the player sells or buys. Big buys ask "Click Again". Nothing touches a Blizzard frame. Tested in `tools/test_snipe.lua`.

## Words awaiting Trent's yes (not in the approved spec)
"Set a Spending Cap first.", "Nothing to snipe yet. Scan the auction house first.", "that item", "%1$s each, worth %2$s", "%1$d for sale. %2$s", "Click Again", "Pay %s", "Asking...", "%d%% under", "% of worth", "Looking for deals...", "Spent: %1$s of %2$s", "%d finds", "Snipe", "Item", "Price", "Deal", "Start Sniping", "Stop", "SNIPE SETTINGS", "Spending Cap:", "Snipe Below:", "Watch:", "Priced Items", "To Disenchant", "Snipe Sound", "You need %s for that.", the cap message, "Snipe Tab:", "Wheel Buys:" and "On the Snipe tab, wheel up buys the best find."

My Lists' words (My Lists, List:, All Lists, the hover, empty and Got all you need lines, List rule, Deal) were seen by Trent before build it; their translations are ours. The five translations were written by us from the English keys and need his okay too.

## Not yet seen in game
Everything. Unchecked: the To Disenchant and Below Vendor modes against real results, and drawer sizing with the strip open at One Window.
