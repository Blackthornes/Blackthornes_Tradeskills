-- Snipe's finds hold still while it keeps searching (the owner's report,
-- 2026-11-21: rows went away and came back while the auction house was
-- being searched).
--
-- What must hold:
--   1. A find still for sale at the same price is the same find after the
--      next search of its batch: its readied price is kept, not let go and
--      asked for again.
--   2. A search that changed nothing does not redraw the list.
--   3. A find whose listings held nothing to buy (a bid with no buyout, or
--      a row the game had not caught up on) leaves once. The same row at
--      the same price does not bring it back on the next search.
--   4. It comes back when the row's price moves, or after GONE_FOR.
--   5. A find that got cheaper keeps its place as the same find, with the
--      new price.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Util = { HasFunction = function() return true end }
ns.Print = function() end
ns.Notice = { Show = function() end }
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local settings = {}
ns.Config = { Get = function(_, k) return settings[k] end }

local oldTimer, oldGetTime = C_Timer, GetTime
local timers, clock = {}, 100
C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end }
GetTime = function() return clock end
-- Move the clock on and run what came due, oldest first.
local function Pass(seconds)
    local stop = clock + seconds
    while true do
        local pick
        for i, t in ipairs(timers) do
            if t.at <= stop and (not pick or t.at < timers[pick].at) then pick = i end
        end
        if not pick then break end
        local t = table.remove(timers, pick)
        clock = math.max(clock, t.at)
        t.fn()
    end
    clock = stop
end

assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe:Init()

local G = 10000
local worth = { [1] = 10 * G, [2] = 20 * G }
ns.Prices = {
    GetTable = function() return worth end,
    GetValue = function(_, id) return worth[id] end,
}
C_Item = { GetItemInfoInstant = function() return nil end }

local requests = {}
ns.AHQueue = {
    BUDGET_MAX = 8, PRIORITY = { urgent = 10, scan = 90 },
    RecentSendCount = function() return 0 end,
    Request = function(_, r) requests[r.key] = r; return true end,
    Cancel = function(_, key) requests[key] = nil; return true end,
}
local rows, listed = {}, {}
C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id } end,
    SearchForItemKeys = function() end,
    SendSearchQuery = function() return true end,
    GetBrowseResults = function() return rows end,
    HasFullBrowseResults = function() return true end,
    GetItemCommodityStatus = function() return 1 end,
    GetNumItemSearchResults = function() return #listed end,
    GetItemSearchResultInfo = function(_, i) return listed[i] end,
}
GetMoney = function() return 1000 * G end

-- One search and its answer.
local function Search()
    Pass(Snipe.REST * 6 + 1)
    assert(requests.snipe, "a search is asked for")
    assert(requests.snipe.send() == true, "and goes out")
    requests.snipe = nil
    Snipe:OnBrowseResults()
end

settings.snipeCap, settings.snipePct, settings.snipeWatch = 100 * G, 70, "priced"
Snipe.viewShown = true
Snipe:Start()
assert(Snipe:IsRunning(), "started")

-- A sword at 3g against 10g: a deal.
rows = { { itemKey = { itemID = 1 }, minPrice = 3 * G, totalQuantity = 1 } }
listed = { { auctionID = 21, buyoutAmount = 3 * G, quantity = 1 } }
assert(requests.snipe and requests.snipe.send() == true)
requests.snipe = nil
Snipe:OnBrowseResults()
local sword = Snipe:Finds()[1]
assert(sword and sword.itemID == 1, "the sword is a find")

-- Its price is readied in the background.
Pass(0.5)
assert(Snipe.pending and Snipe.pending.find == sword, "the top find is being readied")
assert(requests["snipe-buy"].send() == true)
requests["snipe-buy"] = nil
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 1 })
local ready = Snipe.pending
assert(ready and ready.phase == "quoted" and ready.auctionID == 21, "ready for the click")

-- 1 and 2. The next search of its batch finds it again at the same price.
local version = Snipe.version
Search()
assert(#Snipe:Finds() == 1 and Snipe:Finds()[1] == sword, "the same find, not a new one")
assert(Snipe.version == version, "nothing changed, so nothing is drawn again")
Pass(0.5)
assert(Snipe.pending == ready and ready.phase == "quoted", "the readied price is kept")

-- 5. Cheaper now: the same find with the new price.
rows = { { itemKey = { itemID = 1 }, minPrice = 2 * G, totalQuantity = 1 } }
Search()
assert(Snipe:Finds()[1] == sword and sword.price == 2 * G, "the same find at its new price")
assert(Snipe.version ~= version, "a new price is drawn")
Snipe:CancelBuy()
timers, Snipe.readyQueued, requests = {}, nil, {}
Snipe.finds = {}

-- 3. A row whose listings hold nothing to buy: a bid with no buyout.
rows = { { itemKey = { itemID = 2 }, minPrice = 1 * G, totalQuantity = 1 } }
listed = { { auctionID = 31, buyoutAmount = 0, bidAmount = 1 * G, quantity = 1 } }
Snipe:Later()
Search()
assert(#Snipe:Finds() == 1 and Snipe:Finds()[1].itemID == 2, "the row looks like a deal")
Pass(0.5)
assert(Snipe.pending and Snipe.pending.itemID == 2, "its listings are read")
assert(requests["snipe-buy"].send() == true)
requests["snipe-buy"] = nil
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 2 })
assert(#Snipe:Finds() == 0, "nothing to buy there, so it leaves")
Search()
assert(#Snipe:Finds() == 0, "the same row at the same price does not bring it back")
Search()
assert(#Snipe:Finds() == 0, "nor the search after")

-- 4. A new price is a new listing, and so is the same price much later.
rows = { { itemKey = { itemID = 2 }, minPrice = 90 * 100, totalQuantity = 1 } }
listed = { { auctionID = 32, buyoutAmount = 90 * 100, quantity = 1 } }
Search()
assert(#Snipe:Finds() == 1 and Snipe:Finds()[1].price == 90 * 100, "a new price is looked at again")
Snipe:CancelBuy()
timers, Snipe.readyQueued, requests = {}, nil, {}
Snipe.finds = {}
rows = { { itemKey = { itemID = 2 }, minPrice = 1 * G, totalQuantity = 1 } }
listed = { { auctionID = 31, buyoutAmount = 0, bidAmount = 1 * G, quantity = 1 } }
Snipe:Later()
Search()
Pass(0.5)
assert(requests["snipe-buy"].send() == true)
requests["snipe-buy"] = nil
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 2 })
assert(#Snipe:Finds() == 0, "left again")
clock = clock + Snipe.GONE_FOR + 1
Search()
assert(#Snipe:Finds() == 1, "after a good while the same price is looked at again")

Snipe:Stop()
C_Timer, GetTime = oldTimer, oldGetTime
C_AuctionHouse, C_Item, ns.AHQueue, ns.Prices, GetMoney = nil, nil, nil, nil, nil
print("snipe steady: all checks passed")
