-- Snipe buying from a stack, and changing what it watches while it runs.
--
-- What must hold:
--   1. Units are read off the listings cheapest first: every unit is a deal
--      on its own (My Lists' Most I'll Pay holds per unit, not on average),
--      and a listing is cut short to fit the cap left, so a real deal is
--      bought rather than dropped.
--   2. A find with nothing that fits the cap stays on the list and says so;
--      one with no deal left is dropped and says so.
--   3. The game's total is checked against what the listings said; a higher
--      one keeps the find.
--   4. Changing Watch or List while running starts over with the new choice
--      and keeps the amount spent.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Util = { HasFunction = function() return true end }
ns.Print = function() end
local said = {}
ns.Notice = { Show = function(_, text) said[#said + 1] = text end }
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local settings = {}
ns.Config = { Get = function(_, k) return settings[k] end }

assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe:Init()

-- 1. The pure count.
local lists = { kind = "lists", worth = 100 }
local book = {
    { unitPrice = 90, quantity = 3 },
    { unitPrice = 100, quantity = 2, own = 1 },
    { unitPrice = 140, quantity = 50 },
}
local units, cost, any = Snipe.UnitsFromListings(book, lists, 70, 100000, 20)
assert(units == 4 and cost == 370 and any, "stops at the first unit over Most I'll Pay")

units, cost = Snipe.UnitsFromListings({ { unitPrice = 100, quantity = 10 } }, lists, 70, 350, 20)
assert(units == 3 and cost == 300, "a listing is cut to what the cap holds")

units, cost = Snipe.UnitsFromListings({
    { unitPrice = 100, quantity = 2 }, { unitPrice = 120, quantity = 5 },
}, { kind = "priced", worth = 200 }, 70, 100000, 20)
assert(units == 7 and cost == 800, "priced: every unit at or under the line")

units, cost = Snipe.UnitsFromListings({
    { unitPrice = 100, quantity = 2 }, { unitPrice = 141, quantity = 5 },
}, { kind = "priced", worth = 200 }, 70, 100000, 20)
assert(units == 2 and cost == 200, "priced: a unit over the line is left")

units = Snipe.UnitsFromListings({ { unitPrice = 10, quantity = 99 } }, lists, 70, 100000, 20)
assert(units == 20, "never more than the most at once")

units, cost, any = Snipe.UnitsFromListings({ { unitPrice = 100, quantity = 5 } }, lists, 70, 50, 20)
assert(units == 0 and any == true, "a deal the cap can't reach")
units, cost, any = Snipe.UnitsFromListings({ { unitPrice = 101, quantity = 5 } }, lists, 70, 50, 20)
assert(units == 0 and any == false, "no deal at all")

-- 2 and 3. The whole buy, through the events.
local requests, started, cancels = {}, {}, 0
ns.AHQueue = {
    BUDGET_MAX = 8, PRIORITY = { urgent = 10 },
    RecentSendCount = function() return 0 end,
    Request = function(_, r) requests[r.key] = r; return true end,
    Cancel = function() return true end,
}
local listings = {}
C_AuctionHouse = {
    GetItemCommodityStatus = function() return 2 end,
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = function() return true end,
    GetNumCommoditySearchResults = function() return #listings end,
    GetCommoditySearchResultInfo = function(_, i) return listings[i] end,
    StartCommoditiesPurchase = function(id, n) started[#started + 1] = { id, n } end,
    CancelCommoditiesPurchase = function() cancels = cancels + 1 end,
    ConfirmCommoditiesPurchase = function() end,
}
settings.snipeCap, settings.snipeWatch = 1000, "lists"
Snipe.running, Snipe.spent = false, 0

local herb = { itemID = 40, kind = "lists", price = 90, worth = 100, qty = 30 }
Snipe.finds = { herb }
listings = {
    { unitPrice = 90, quantity = 3, numOwnerItems = 0 },
    { unitPrice = 150, quantity = 30, numOwnerItems = 0 },
}
Snipe:Buy(herb)
assert(Snipe.pending and Snipe.pending.phase == "listing", "reads the listings first")
assert(#started == 0, "nothing priced yet")
assert(requests["snipe-buy"].send() == true)
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 40)
assert(started[1][1] == 40 and started[1][2] == 3, "only the units under Most I'll Pay")
assert(Snipe.pending.phase == "asking" and Snipe.pending.expected == 270)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 40, 270)
assert(Snipe.pending.phase == "quoted" and Snipe.pending.total == 270, "the quote matches")

-- A quote over what the listings said: some sold first, the find stays.
Snipe:CancelBuy()
Snipe:Buy(herb)
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 40)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 40, 360)
assert(Snipe.pending == nil and #Snipe:Finds() == 1, "a higher total keeps the find")
assert(said[#said] == "That auction is gone already.")

-- A deal the old math dropped: 950 left, 3 at 190 then more at 210 (worth
-- 300 at 70% is a 210 line). Cap left / cheapest asked for 5, which cost
-- 990, over the cap, so the find was dropped. Now 4 are bought.
settings.snipeWatch = "priced"
settings.snipeCap = 950
local ore = { itemID = 41, kind = "priced", price = 190, worth = 300, qty = 40 }
Snipe.finds = { ore }
listings = {
    { unitPrice = 190, quantity = 3, numOwnerItems = 0 },
    { unitPrice = 210, quantity = 40, numOwnerItems = 0 },
}
started = {}
Snipe:Buy(ore)
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 41)
assert(started[1][2] == 4, "three at 190 and one at 210 fit 950")
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 41, 780)
assert(Snipe.pending.phase == "quoted", "bought, not dropped")
Snipe:CancelBuy()

-- Nothing fits the cap: the find stays and says why.
Snipe.spent = 900
started = {}
Snipe:Buy(ore)
assert(Snipe.pending == nil and #started == 0 and #Snipe:Finds() == 1, "the cap check before asking")
Snipe.spent = 0

-- No deal left: dropped.
listings = { { unitPrice = 400, quantity = 9, numOwnerItems = 0 } }
Snipe:Buy(ore)
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 41)
assert(Snipe.pending == nil and #Snipe:Finds() == 0, "gone, dropped")
assert(said[#said] == "That auction is gone already.")

-- Our own units are skipped, as the auction house does.
Snipe.finds = { ore }
listings = {
    { unitPrice = 150, quantity = 2, numOwnerItems = 2 },
    { unitPrice = 200, quantity = 1, numOwnerItems = 0 },
}
started = {}
Snipe:Buy(ore)
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 41)
assert(started[1][2] == 1 and Snipe.pending.expected == 200, "own units left out")
Snipe:CancelBuy()

-- Another item's listings are not ours.
Snipe:Buy(ore)
requests["snipe-buy"].send()
started = {}
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 99)
assert(Snipe.pending.phase == "listing" and #started == 0, "waits for its own item")
Snipe:CancelBuy()

-- 4. Watch or List changed while running.
local built = 0
Snipe.BuildPool = function(_, done) built = built + 1 end
settings.snipeCap = 1000
Snipe:Start()
assert(Snipe:IsRunning() and built == 1)
Snipe.spent = 300
Snipe.finds = { ore }
settings.snipeWatch = "vendor"
Snipe:Restart()
assert(Snipe:IsRunning() and built == 2, "a new pool for the new choice")
assert(Snipe:Spent() == 300, "the amount spent carries on")
assert(#Snipe:Finds() == 0, "finds judged the old way are gone")
Snipe:Stop()
Snipe:Restart()
assert(not Snipe:IsRunning() and built == 2, "nothing to restart when stopped")

C_AuctionHouse, ns.AHQueue = nil, nil
print("snipe stack: all checks passed")
