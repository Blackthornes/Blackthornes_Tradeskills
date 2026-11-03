-- The Snipe tab's logic (2026-11-03).
--
-- What must hold:
--   1. A deal is a price at or under worth times Snipe Below.
--   2. Snipe Below stays between 10 and 95; the cap and watch read the setting.
--   3. Start refuses without a Spending Cap and never starts by itself.
--   4. A buy that reaches the cap stops the session and clears the finds.
--   5. The auction house closing stops a session.
--   6. The wheel (BuyNext) does nothing when not running.

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

print("test_snipe: all passed")
