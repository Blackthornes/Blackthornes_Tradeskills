-- The Snipe tab's logic (2026-11-03).
--
-- What must hold:
--   1. A deal is a price at or under worth times Snipe Below.
--   2. Snipe Below stays between 10 and 95; the cap and watch read the setting.
--   3. Start refuses without a Spending Cap and never starts by itself.
--   4. A buy that reaches the cap stops the session and clears the finds.
--   5. The auction house closing stops a session.
--   6. The wheel (BuyNext) does nothing with nothing to buy.
--  12. Stop keeps the finds, so they can still be bought.
--  13. Snipe waits while its searches would crowd out the player's click.
--  14. An item sold one at a time is asked about, then bought with a bid.
--  15. My Lists: the pool is the lists' items; each limit is the item's own
--      Most I'll Pay, else the list's rule, else worth times Snipe Below; a
--      gone list reads as All Lists; an item drops out once you have enough.
--  16. Searches start big, halve when the game can't keep up, grow back.
--  17. The top find is readied in the background, quietly; one click buys
--      it, and the item stays while more of its listings are deals.
--  18. A new top lets the old readied deal go, unless it is being confirmed.
--  19. Stacks are readied too; a client that won't price them in the
--      background gets them planned, and the click asks, the next one pays.
--  20. Snipe's own searches slow down while a ready deal waits.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Util = {}
ns.Print = function() end
local said = {}
ns.Notice = { Show = function(_, text) said[#said + 1] = text end }
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local settings = {}
ns.Config = { Get = function(_, k) return settings[k] end }
-- Timers wait until Flush; the clock moves only when told.
local oldTimer, oldGetTime = C_Timer, GetTime
local timers, clock, lastWait = {}, 1000, nil
C_Timer = { After = function(seconds, fn) lastWait = seconds; timers[#timers + 1] = fn end }
GetTime = function() return clock end
-- Runs the timers waiting now, once each; ones they set wait for the next.
local function Flush()
    local list = timers
    timers = {}
    for _, fn in ipairs(list) do fn() end
end

assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe:Init()

-- 1. Deals.
assert(Snipe.IsDeal(70, 100, 70) == true, "at the line is a deal")
assert(Snipe.IsDeal(71, 100, 70) == false, "over the line is not")
assert(Snipe.IsDeal(10, 0, 70) == false, "no worth, no deal")
assert(Snipe.Deal(50, 100) == 50, "half price is 50 under")

-- 2. Settings.
assert(Snipe:Percent() == 70, "default 70")
settings.snipePct = 3
assert(Snipe:Percent() == 10, "floor 10")
settings.snipePct = 200
assert(Snipe:Percent() == 95, "ceiling 95")
settings.snipeCap = 5000
assert(Snipe:Cap() == 5000)
assert(Snipe:Watch() == "priced")
settings.snipeWatch = "disenchant"
assert(Snipe:Watch() == "disenchant")
assert(Snipe:Enabled() == false)
settings.snipeTab = true
assert(Snipe:Enabled() == true)

-- 3. No cap, no start.
settings.snipeCap = 0
Snipe:Start()
assert(not Snipe:IsRunning(), "refuses without a cap")
assert(said[#said] == "Set a Spending Cap first.", "says why")

-- 6. Wheel does nothing when stopped.
Snipe:BuyNext()
assert(not Snipe:IsRunning())

-- 4. Cap reached.
settings.snipeCap = 1000
Snipe.running, Snipe.spent = true, 0
Snipe.finds = { { itemID = 1 }, { itemID = 2 } }
Snipe.pending = { itemID = 1, count = 1, total = 1000, phase = "buying" }
Snipe:Bought()
assert(Snipe:Spent() == 1000, "spent counts")
assert(not Snipe:IsRunning(), "cap stops the session")
assert(#Snipe:Finds() == 0, "finds cleared")
assert(said[#said] == "You've reached your Spending Cap. Snipe stopped.")

-- 5. Auction house closing.
Snipe.running = true
handlers.AUCTION_HOUSE_CLOSED()
assert(not Snipe:IsRunning(), "closing the auction house stops")

-- 7. Only our own search's rows are read.
assert(Snipe.OwnResults({ { itemKey = { itemID = 5 } } }, { [5] = 100 }) == true, "our rows")
assert(Snipe.OwnResults({ { itemKey = { itemID = 5 } }, { itemKey = { itemID = 9 } } }, { [5] = 100 }) == false,
    "a row outside the batch is someone else's search")

-- 8. Last scan's items first, most valuable first.
local order = Snipe.OrderPool({
    { id = 1, worth = 900 }, { id = 2, worth = 100, listed = true },
    { id = 3, worth = 500, listed = true }, { id = 4, worth = 2000 },
})
assert(order[1].id == 3 and order[2].id == 2 and order[3].id == 4 and order[4].id == 1, "listed first, then by worth")

-- 9. Greys and silly averages are left out of Priced Items.
settings.snipeWatch = "priced"
local quality, records = {}, {}
C_Item = { GetItemQualityByID = function(id) return quality[id] end }
ns.Prices = {
    GetValue = function(_, id) return records[id] and records[id].value end,
    Get = function(_, id) return records[id] end,
    LowestListed = function(r) return r.min end,
}
records[10] = { value = 80000, min = 60000, quantity = 2 }
records[11] = { value = 80000, min = 60000, quantity = 2 }
records[12] = { value = 6800000000, min = 1000, quantity = 1 }
quality[10], quality[11], quality[12] = 2, 0, 2
assert(Snipe:WorthOf(10) == 80000, "a green is watched")
assert(Snipe:WorthOf(11) == nil, "a grey is not")
assert(Snipe:WorthOf(12) == nil, "an average over ten times the cheapest is not")
assert(Snipe.InLastScan(10, 0) == true)
C_Item, ns.Prices = nil, nil

-- 10. Below Vendor: worth is what a vendor pays, greys count, any listing
--     under it is a find, unsure charged items and unpriced ones are out.
settings.snipeWatch = "vendor"
assert(Snipe:Watch() == "vendor", "vendor is a watch")
settings.snipeWatch = "nonsense"
assert(Snipe:Watch() == "priced", "an unknown watch reads as priced")
settings.snipeWatch = "vendor"
local sell, unsure = { [20] = 500, [21] = 300, [22] = 0, [24] = 2 }, { [21] = true }
ns.Disenchant = {
    GetSellPrice = function(_, id) return sell[id] end,
    SellPriceUnsure = function(_, id) return unsure[id] == true end,
}
C_Item = { GetItemQualityByID = function() return 0 end }
assert(Snipe:WorthOf(20) == 500, "a grey's vendor price, no cut")
assert(Snipe:WorthOf(24) == 2, "no smallest worth in Below Vendor")
assert(Snipe:WorthOf(21) == nil, "a charged item with an unsure price is out")
assert(Snipe:WorthOf(22) == nil, "no vendor price, no find")
assert(Snipe:WorthOf(23) == nil, "unknown, no find")
assert(Snipe.IsDealFor(499, 500, "vendor", 10) == true, "under vendor is a find whatever Snipe Below says")
assert(Snipe.IsDealFor(500, 500, "vendor", 95) == false, "at vendor is no profit")
assert(Snipe.IsDealFor(70, 100, "priced", 70) == true, "other watches keep Snipe Below")
assert(Snipe.IsDealFor(71, 100, "priced", 70) == false)
assert(Snipe.Profit({ price = 300, worth = 500 }) == 200)
local finds = {
    { itemID = 1, kind = "vendor", price = 90, worth = 100, deal = 10 },
    { itemID = 2, kind = "vendor", price = 1000, worth = 5000, deal = 80 },
    { itemID = 3, kind = "vendor", price = 1, worth = 50, deal = 98 },
}
table.sort(finds, Snipe.Better)
assert(finds[1].itemID == 2 and finds[2].itemID == 3 and finds[3].itemID == 1, "biggest profit first")
local deals = { { itemID = 1, deal = 10 }, { itemID = 2, deal = 50 } }
table.sort(deals, Snipe.Better)
assert(deals[1].itemID == 2, "other watches still sort by how far under")

-- 11. A quote that is no longer under a vendor's price is let go.
Snipe.running, Snipe.spent = true, 0
settings.snipeCap, settings.snipePct = 100000, 10
local find = { itemID = 20, kind = "vendor", price = 400, worth = 500, qty = 5 }
Snipe.finds = { find }
Snipe.pending = { itemID = 20, count = 2, phase = "asking", find = find }
Snipe:PriceUpdated(800)
assert(Snipe.pending and Snipe.pending.phase == "quoted", "400 each is still under 500, Snipe Below ignored")
Snipe.pending = { itemID = 20, count = 2, phase = "asking", find = find }
ns.Util.HasFunction = function() return false end
Snipe:PriceUpdated(1000)
assert(Snipe.pending == nil and #Snipe.finds == 0, "500 each is no find")
Snipe:Stop()
ns.Disenchant, C_Item = nil, nil

-- 12. Stop keeps the finds; the auction house closing clears them.
ns.Util.HasFunction = function() return false end
Snipe.running = true
Snipe.finds = { { itemID = 1 } }
Snipe:Stop()
assert(not Snipe:IsRunning() and #Snipe:Finds() == 1, "Stop keeps the finds")
handlers.AUCTION_HOUSE_CLOSED()
assert(#Snipe:Finds() == 0, "closing clears them")

-- 13. Room left for the player's click.
local sends = 0
ns.AHQueue = { BUDGET_MAX = 8, RecentSendCount = function() return sends end }
assert(Snipe.CrowdsPlayer() == false, "nothing sent, no crowding")
sends = 5
assert(Snipe.CrowdsPlayer() == true, "five of eight leaves too little room")
sends = 4
assert(Snipe.CrowdsPlayer() == false, "four of eight is fine")

-- 14. Buying an item sold one at a time, while stopped.
local requests, cancelled, bids = {}, {}, {}
ns.AHQueue = {
    BUDGET_MAX = 8, PRIORITY = { urgent = 10, scan = 90 },
    RecentSendCount = function() return 0 end,
    Request = function(_, r) requests[r.key] = r; return true end,
    Cancel = function(_, key) cancelled[#cancelled + 1] = key; return true end,
}
ns.Util.HasFunction = function() return true end
local results = {
    { auctionID = 7, buyoutAmount = 900, quantity = 1, containsOwnerItem = true },
    { auctionID = 8, buyoutAmount = 300, quantity = 1 },
    { auctionID = 9, buyoutAmount = 350, quantity = 1 },
}
C_AuctionHouse = {
    GetItemCommodityStatus = function() return 1 end,
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = function() return true end,
    GetNumItemSearchResults = function() return #results end,
    GetItemSearchResultInfo = function(_, i) return results[i] end,
    PlaceBid = function(id, amount) bids[#bids + 1] = { id, amount } end,
}
local purse = 10000
GetMoney = function() return purse end
settings.snipeCap, settings.snipeWatch = 5000, "vendor"
Snipe.running, Snipe.spent = false, 0
local item = { itemID = 30, kind = "vendor", price = 300, worth = 500, qty = 1 }
Snipe.finds = { item }
Snipe:BuyNext()
assert(Snipe.pending and Snipe.pending.item and Snipe.pending.phase == "asking", "asks while stopped")
assert(requests["snipe-buy"] and requests["snipe-buy"].priority == 10, "an urgent search of its own")
assert(cancelled[1] == "snipe", "a waiting snipe search steps aside")
assert(requests["snipe-buy"].send() == true)
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 30 })
assert(Snipe.pending.phase == "quoted" and Snipe.pending.auctionID == 8, "cheapest not our own")
assert(Snipe.pending.total == 300)
assert(Snipe:Pay() == true and bids[1][1] == 8 and bids[1][2] == 300, "bids the buyout")
purse = 9700
handlers.PLAYER_MONEY()
assert(Snipe.pending == nil and Snipe:Spent() == 300, "bought")
assert(#Snipe:Finds() == 1 and item.left == 1, "350 is still a deal: stays on it, 1 left")

-- 14b. Gone: no listing is a deal any more.
item.left = nil
Snipe.finds = { item }
Snipe:Buy(item)
requests["snipe-buy"].send()
results = { { auctionID = 10, buyoutAmount = 600, quantity = 1 } }
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 30 })
assert(Snipe.pending == nil and #Snipe:Finds() == 0, "gone, dropped")
assert(said[#said] == "That auction is gone already.")

-- 14c. The game refuses the bid.
results = { { auctionID = 11, buyoutAmount = 200, quantity = 1 } }
Snipe.finds = { item }
Snipe:Buy(item)
requests["snipe-buy"].send()
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 30 })
Snipe:Pay()
handlers.AUCTION_HOUSE_SHOW_ERROR()
assert(Snipe.pending == nil and #Snipe:Finds() == 1 and item.retryAt, "refused: kept, looked at again in a moment")
C_AuctionHouse, GetMoney, ns.AHQueue = nil, nil, nil
timers, Snipe.readyQueued = {}, nil

-- 15. My Lists.
local held = {
    { list = { id = 1, name = "Herbs", items = {
        { id = 100, want = 10, maxPay = 5000 },
        { id = 101, want = 5 },
        { id = 102, want = 2 },
    } } },
    { list = { id = 2, name = "Ore", items = {
        { id = 100, want = 99, maxPay = 1 },
        { id = 103, want = 4 },
    } } },
}
ns.ShoppingLists = {
    version = 1,
    Readable = function() return held end,
    MaxPayOf = function(item) return tonumber(item.maxPay) end,
}
ns.ListRules = { Of = function(list) return list.id == 1 and { maxPay = 3000 } or {} end }
local owned = {}
ns.Inventory = { GetOwnedCount = function(_, id) return owned[id] or 0 end }
ns.Prices = { GetValue = function(_, id) return id == 103 and 10000 or nil end }
settings.snipeWatch, settings.snipePct = "lists", 70
assert(Snipe:Watch() == "lists", "My Lists is a watch")
assert(Snipe:ListChoice() == nil, "no pick reads as All Lists")
settings.snipeList = 9
assert(Snipe:ListChoice() == nil, "a gone list reads as All Lists")
settings.snipeList = 2
assert(Snipe:ListChoice() == 2, "a list that is there is picked")

settings.snipeList = nil
local items, order = Snipe.ListItems(Snipe:ListChoice())
assert(#order == 4 and order[1] == 100 and order[4] == 103, "every item once, in list order")
assert(items[100].want == 10 and items[100].own == 5000, "the first list that holds it wins")
assert(Snipe:LimitFor(items[100]) == 5000, "the item's own Most I'll Pay first")
local limit, from = Snipe:LimitFor(items[101])
assert(limit == 3000 and from == "list", "then the list's rule")
limit, from = Snipe:LimitFor(items[103])
assert(limit == 7000 and from == "worth", "then worth times Snipe Below")

local only = Snipe.ListItems(2)
assert(only[100].own == 1 and only[101] == nil, "one list only watches that list")

owned[101] = 5
local pool = Snipe:BuildListPool()
local inPool = {}
for _, entry in ipairs(pool) do inPool[entry.id] = entry end
assert(inPool[101] == nil, "an item you have enough of drops out")
assert(inPool[100] and inPool[100].worth == 5000 and inPool[100].want == 10, "the limit stands in for worth")
assert(inPool[102] and inPool[102].worth == 3000, "the list's rule covers an item with no price")
assert(Snipe.IsDealFor(5000, 5000, "lists", 10) == true, "at the limit is a buy, whatever Snipe Below says")
assert(Snipe.IsDealFor(5001, 5000, "lists", 95) == false, "over the limit is not")

settings.snipeCap = 1000000
Snipe.spent = 0
owned[100] = 7
assert(Snipe:UnitsFor({ kind = "lists", want = 10, itemID = 100, qty = 20, price = 10 }) == 3,
    "buys only what the list still needs")

held = {}
Snipe.running = true
Snipe:BuildPool(function() end)
assert(Snipe.emptyWhy == "Put items on a list first.", "no lists says so")
held = { { list = { id = 1, name = "Herbs", items = { { id = 101, want = 5 } } } } }
Snipe:BuildPool(function() end)
assert(Snipe.emptyWhy == "Got all you need", "everything had says so")
Snipe.running = false
ns.ShoppingLists, ns.ListRules, ns.Inventory, ns.Prices = nil, nil, nil, nil
settings.snipeWatch, settings.snipeList, settings.snipeCap = nil, nil, nil


-- 16. Batch size.
Snipe.batch = nil
assert(Snipe:BatchSize() == Snipe.BATCH_MOST, "starts at the most")
Snipe:Shrink()
assert(Snipe:BatchSize() == math.floor(Snipe.BATCH_MOST / 2), "halves")
for _ = 1, 10 do Snipe:Shrink() end
assert(Snipe:BatchSize() == Snipe.BATCH, "never under the floor")
Snipe:Grow()
assert(Snipe:BatchSize() == Snipe.BATCH + Snipe.BATCH_STEP, "grows by a step")
for _ = 1, 50 do Snipe:Grow() end
assert(Snipe:BatchSize() == Snipe.BATCH_MOST, "never over the most")
Snipe.batch = nil

-- 17. Readied before the click.
local requests, cancelled, bids, starts, confirms = {}, {}, {}, {}, {}
ns.AHQueue = {
    BUDGET_MAX = 8, PRIORITY = { urgent = 10, scan = 90 },
    RecentSendCount = function() return 0 end,
    Request = function(_, r) requests[r.key] = r; return true end,
    Cancel = function(_, key) cancelled[#cancelled + 1] = key; return true end,
}
ns.Util.HasFunction = function(name) return name ~= "C_AuctionHouse.GetQuoteDurationRemaining" end
local listed, status = {}, 1
local stack = {}
C_AuctionHouse = {
    GetItemCommodityStatus = function() return status end,
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = function() return true end,
    GetNumItemSearchResults = function() return #listed end,
    GetItemSearchResultInfo = function(_, i) return listed[i] end,
    PlaceBid = function(id, amount) bids[#bids + 1] = { id, amount } end,
    GetNumCommoditySearchResults = function() return #stack end,
    GetCommoditySearchResultInfo = function(_, i) return stack[i] end,
    StartCommoditiesPurchase = function(id, units) starts[#starts + 1] = { id, units } end,
    ConfirmCommoditiesPurchase = function(id, units) confirms[#confirms + 1] = { id, units } end,
    CancelCommoditiesPurchase = function() end,
}
local wallet = 100000
GetMoney = function() return wallet end
settings.snipeCap, settings.snipeWatch, settings.snipePct = 50000, "vendor", 70
Snipe.running, Snipe.spent, Snipe.pending, Snipe.armed = false, 0, nil, nil
Snipe.viewShown, timers, Snipe.readyQueued = true, {}, nil
listed = { { auctionID = 21, buyoutAmount = 300, quantity = 1 }, { auctionID = 22, buyoutAmount = 320, quantity = 1 } }
local a = { itemID = 40, kind = "vendor", price = 300, worth = 500, qty = 1 }
Snipe.finds = { a }
local saidBefore = #said
Snipe:Ready()
assert(Snipe.pending and Snipe.pending.auto and Snipe.pending.phase == "asking", "readies on its own")
assert(#cancelled == 0, "a background ready leaves the scan alone")
assert(requests["snipe-buy"].send() == true)
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 40 })
assert(Snipe.pending.phase == "quoted" and Snipe.pending.auctionID == 21, "the cheapest listing is ready")
assert(#bids == 0, "nothing is bought without a click")
assert(Snipe:WaitingReady())
Snipe:BuyNext()
assert(bids[1] and bids[1][1] == 21 and bids[1][2] == 300, "one click buys it")
wallet = wallet - 300
handlers.PLAYER_MONEY()
assert(Snipe.pending == nil and a.left == 1 and #Snipe.finds == 1, "stays on it, 1 left")
Flush()
assert(Snipe.pending and Snipe.pending.auto and Snipe.pending.find == a, "readies the same item again")
requests["snipe-buy"].send()
listed = { { auctionID = 23, buyoutAmount = 900, quantity = 1 } }
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 40 })
assert(Snipe.pending == nil and #Snipe.finds == 0, "no deal left: off the list")
assert(#said == saidBefore, "a background ready says nothing")
timers, Snipe.readyQueued = {}, nil

-- 18. A new top.
local b = { itemID = 41, kind = "vendor", price = 200, worth = 500, qty = 1 }
a.left = nil
Snipe.finds = { a, b }
Snipe:Ready()
assert(Snipe.pending and Snipe.pending.find == a)
Snipe.topFn = function() return b end
Snipe.armed = Snipe.pending
Snipe:Ready()
assert(Snipe.pending and Snipe.pending.find == a, "a deal being confirmed is kept")
Snipe.armed = nil
Snipe:Ready()
assert(Snipe.pending == nil, "the old ready goes")
Snipe:Ready()
assert(Snipe.pending and Snipe.pending.find == b, "the new top is readied")
Snipe:CancelBuy()
Snipe.topFn, timers, Snipe.readyQueued = nil, {}, nil

-- 19. Stacks.
status = 2
stack = { { unitPrice = 100, quantity = 3 }, { unitPrice = 120, quantity = 50 } }
local c = { itemID = 42, kind = "vendor", price = 100, worth = 500, qty = 53 }
Snipe.finds, Snipe.spent = { c }, 0
Snipe:Ready()
assert(Snipe.pending and Snipe.pending.phase == "listing" and Snipe.pending.auto, "reads the listings first")
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 42)
assert(starts[1] and starts[1][1] == 42 and starts[1][2] == Snipe.MOST_UNITS, "asks the price for the most at once")
assert(Snipe.pending.phase == "asking" and Snipe.pending.auto and Snipe.pending.others == 53 - Snipe.MOST_UNITS)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, nil, 2340)
assert(Snipe.pending.phase == "quoted" and #confirms == 0, "priced, nothing bought")
Snipe:BuyNext()
assert(confirms[1] and confirms[1][2] == Snipe.MOST_UNITS, "one click buys the stack")
handlers.COMMODITY_PURCHASE_SUCCEEDED()
assert(#Snipe.finds == 1 and c.left == 33 and c.qty == 33, "33 more still deals")
timers, Snipe.readyQueued = {}, nil
Snipe.noAutoStack = true
Snipe:Ready()
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 42)
assert(Snipe.pending.phase == "planned" and #starts == 1, "planned, no price asked in the background")
assert(Snipe:BuyNext() == "checking" and #starts == 2, "the click asks")
assert(Snipe.pending.phase == "asking" and not Snipe.pending.auto)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, nil, 2340)
assert(Snipe:BuyNext() == true and #confirms == 2, "the next click pays")
handlers.COMMODITY_PURCHASE_SUCCEEDED()

-- 20. Slower searches while a ready deal waits.
Snipe.pending = { auto = true, phase = "quoted", find = c }
Snipe:Later()
assert(lastWait == Snipe.REST * 3, "rests longer")
Snipe.pending = nil
Snipe:Later()
assert(lastWait == Snipe.REST, "back to the usual rest")

Snipe.viewShown, Snipe.noAutoStack, Snipe.finds, Snipe.running = nil, nil, {}, false
C_AuctionHouse, GetMoney, ns.AHQueue = nil, nil, nil
C_Timer, GetTime = oldTimer, oldGetTime

print("test_snipe: all passed")
