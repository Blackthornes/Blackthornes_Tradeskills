-- Snipe buys are instant: the top find's price is kept ready.
--
-- What must hold:
--   1. Searching holds while the top find's price is not ready yet, and a
--      background check that got nowhere steps aside so searching goes on.
--   2. The ready check may use the requests searching leaves alone: it goes
--      out at 6 of 8 and waits only at 7.
--   3. A ready price that got old is asked for again in place. The deal is
--      never let go just for its age, and one click still buys it.
--   4. A stack priced again can't be paid until the answer is in, and goes
--      when it costs more now.
--   5. Nothing is ever bought without the player's click.

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

local requests, sends, started, bids, confirms, searches = {}, 0, {}, {}, 0, 0
ns.AHQueue = {
    BUDGET_MAX = 8, PRIORITY = { urgent = 10, scan = 90 },
    RecentSendCount = function() return sends end,
    Request = function(_, r) requests[r.key] = r; return true end,
    Cancel = function(_, key) requests[key] = nil; return true end,
}
local stackIDs, listed, listings = {}, {}, {}
C_AuctionHouse = {
    GetItemCommodityStatus = function(id) return stackIDs[id] and 2 or 1 end,
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = function() return true end,
    SearchForItemKeys = function() searches = searches + 1 end,
    GetNumItemSearchResults = function() return #listed end,
    GetItemSearchResultInfo = function(_, i) return listed[i] end,
    GetNumCommoditySearchResults = function() return #listings end,
    GetCommoditySearchResultInfo = function(_, i) return listings[i] end,
    StartCommoditiesPurchase = function(id, n) started[#started + 1] = { id, n } end,
    CancelCommoditiesPurchase = function() end,
    ConfirmCommoditiesPurchase = function() confirms = confirms + 1 end,
    PlaceBid = function(id, money) bids[#bids + 1] = { id, money } end,
}
GetMoney = function() return 1000000 end
settings.snipeCap, settings.snipeWatch, settings.snipePct = 50000, "vendor", 70
Snipe.spent, Snipe.viewShown = 0, true

-- 2. The ready check's own room.
local sword = { itemID = 40, kind = "vendor", price = 300, worth = 500, qty = 1 }
Snipe.finds = { sword }
listed = { { auctionID = 21, buyoutAmount = 300, quantity = 1 } }
assert(Snipe:WantsReady(), "a top find with no price wants one")
sends = 7
Snipe:Ready()
assert(Snipe.pending == nil, "waits when only one request is left")
sends = 6
Snipe:Ready()
assert(Snipe.pending and Snipe.pending.auto and Snipe.pending.phase == "asking", "goes out past where searching holds")
assert(not Snipe:WantsReady(), "one check at a time")
assert(requests["snipe-buy"].send() == true)
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 40 })
local ready = Snipe.pending
assert(ready.phase == "quoted" and ready.auctionID == 21 and Snipe:WaitingReady(), "ready for the click")

-- 3. An old price is asked for again in place.
requests["snipe-buy"] = nil
Pass(Snipe.READY_KEEP + 0.5)
assert(Snipe.pending == ready and ready.phase == "quoted", "the deal is kept past its age")
assert(ready.refreshing and requests["snipe-buy"], "and asked for again")
assert(not Snipe:Repricing(), "one listing can still be paid for meanwhile")
listed = { { auctionID = 22, buyoutAmount = 280, quantity = 1 } }
assert(requests["snipe-buy"].send() == true)
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 40 })
assert(Snipe.pending == ready and ready.auctionID == 22 and ready.total == 280, "the newest listing takes its place")
assert(ready.refreshing == nil and #bids == 0, "nothing is bought without a click")
Snipe:BuyNext()
assert(bids[1] and bids[1][1] == 22 and bids[1][2] == 280, "one click buys it")
Snipe:CancelBuy()
timers, Snipe.readyQueued, requests = {}, nil, {}

-- 1. A background check that got nowhere steps aside.
sword.retryAt, sword.left = nil, nil
Snipe.finds = { sword }
sends = 0
Snipe:Ready()
assert(Snipe.pending and Snipe.pending.phase == "asking")
requests["snipe-buy"].onGiveUp()
assert(Snipe.pending == nil, "the check is let go")
assert(sword.retryAt and sword.retryAt > clock, "and waits a moment")
assert(not Snipe:WantsReady(), "so searching goes on meanwhile")
clock = clock + Snipe.RETRY_AFTER + 1
assert(Snipe:WantsReady(), "then it is tried again")
timers, Snipe.readyQueued, requests = {}, nil, {}

-- 4. A stack priced again.
stackIDs[50] = true
settings.snipeWatch = "lists"
local herb = { itemID = 50, kind = "lists", price = 90, worth = 100, qty = 30 }
Snipe.finds = { herb }
listings = { { unitPrice = 90, quantity = 3, numOwnerItems = 0 } }
Snipe:Ready()
assert(Snipe.pending and Snipe.pending.phase == "listing")
assert(requests["snipe-buy"].send() == true)
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 50)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 50, 270)
local stack = Snipe.pending
assert(stack and stack.phase == "quoted" and stack.total == 270)
local asked = #started
Pass(Snipe.READY_KEEP + 0.5)
assert(Snipe.pending == stack and #started == asked + 1, "the same units are priced again")
assert(Snipe:Repricing(), "the old price can't be paid meanwhile")
assert(Snipe:Pay() == "checking" and confirms == 0, "a click waits for the answer")
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 50, 270)
assert(Snipe.pending == stack and not Snipe:Repricing(), "ready again")
Snipe:BuyNext()
assert(confirms == 1, "one click buys it")
Snipe:CancelBuy()
timers, Snipe.readyQueued, requests = {}, nil, {}

herb.retryAt = nil
Snipe.finds = { herb }
Snipe:Ready()
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 50)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 50, 270)
stack = Snipe.pending
assert(stack and stack.phase == "quoted")
Snipe.noReady = true
Pass(Snipe.READY_KEEP + 0.5)
assert(Snipe:Repricing())
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 50, 300)
assert(Snipe.pending == nil, "costs more now: let go")
assert(confirms == 1 and #bids == 1, "nothing bought without a click")
Snipe.noReady = nil

C_Timer, GetTime = oldTimer, oldGetTime
print("  all instant snipe checks passed")
