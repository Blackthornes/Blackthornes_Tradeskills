-- Snipe Buy stuck on "asking" (a player's report).
--
-- Forever prices a stack only when StartCommoditiesPurchase runs inside the
-- player's own click. A click on Buy reads the listings first, and the
-- price is asked from the listings event, so the game never answered and
-- the row waited on "asking" for good. What must hold:
--   1. An ask outside a click that gets no price turns into a planned buy
--      (the row reads "Buy N for X"), and later stacks are planned at once.
--   2. The next click (Pay on a planned buy) asks from inside the click.
--   3. An ask from a click that still gets no price lets go and says so.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Util = { HasFunction = function() return true end }
ns.Print = function() end
local said = {}
ns.Notice = { Show = function(_, text) said[#said + 1] = text end }
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local settings = { snipeCap = 1000, snipeWatch = "lists" }
ns.Config = { Get = function(_, k) return settings[k] end }

local timers = {}
local savedTimer, savedFrame = C_Timer, AuctionHouseFrame
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
AuctionHouseFrame = nil
local function RunTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe:Init()

local requests, started, cancels = {}, {}, 0
ns.AHQueue = {
    BUDGET_MAX = 8, PRIORITY = { urgent = 10 },
    RecentSendCount = function() return 0 end,
    Request = function(_, r) requests[r.key] = r; return true end,
    Cancel = function() return true end,
}
local listings = {
    { unitPrice = 90, quantity = 3, numOwnerItems = 0 },
    { unitPrice = 150, quantity = 30, numOwnerItems = 0 },
}
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
Snipe.running, Snipe.spent, Snipe.noAutoStack = false, 0, nil

local herb = { itemID = 40, kind = "lists", price = 90, worth = 100, qty = 30 }
Snipe.finds = { herb }

-- 1. The click reads the listings; the price is asked from their event.
Snipe:Buy(herb)
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 40)
assert(Snipe.pending.phase == "asking" and #started == 1)
-- The game never answers. It must not wait on "asking" for good.
RunTimers()
assert(Snipe.pending and Snipe.pending.phase == "planned", "no price outside a click: planned")
assert(Snipe.pending.count == 3 and Snipe.pending.expected == 270)
assert(not Snipe.pending.auto, "the player's own buy keeps its words")
assert(Snipe.noAutoStack == true and cancels == 1)

-- 2. The next click asks from inside it, and the price comes.
assert(Snipe:Pay() == "checking")
assert(#started == 2 and Snipe.pending.phase == "asking" and Snipe.pending.fromClick)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 40, 270)
assert(Snipe.pending.phase == "quoted", "the click got its price")
Snipe:CancelBuy()

-- Later stacks are planned straight away, no wait on "asking".
timers = {}
Snipe:Buy(herb)
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 40)
assert(Snipe.pending.phase == "planned" and #started == 2, "planned at once")

-- 3. A click's ask with no price lets go and says why.
assert(Snipe:Pay() == "checking")
RunTimers()
assert(Snipe.pending == nil, "lets go")
assert(said[#said] and said[#said]:find("busy"), "says the auction house is busy")

C_Timer, AuctionHouseFrame = savedTimer, savedFrame
C_AuctionHouse = nil
ns.AHQueue = nil
print("test_snipestuckask: ok")
