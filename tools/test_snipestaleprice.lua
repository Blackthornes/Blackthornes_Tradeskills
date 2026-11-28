-- A material's price ran out behind the player's back (found 2026-11-28).
--
-- Forever prices a stack only inside the player's own click
-- (Snipe.ASK_OUTSIDE_CLICK = false). After a click got the price, the
-- keep-fresh timer asked StartCommoditiesPurchase again from a timer. The
-- game never answered it, so for QUOTE_WAIT the button read Checking... and
-- clicks did nothing, then the buy was dropped without a word. What must hold:
--   1. With ASK_OUTSIDE_CLICK false, no timer ever asks a stack's price.
--   2. When the price runs out the buy stays, marked expired; the button
--      reads "Check Price Again" and Pay asks again from inside the click.
--   3. The new price in, one more click pays it.
--   4. Double Check Over still asks for Confirm on a big buy.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Util = { HasFunction = function() return true end, FormatMoney = function(c) return tostring(c) end }
ns.Print = function() end
ns.Notice = { Show = function() end }
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local settings = { snipeCap = 100000, snipeWatch = "lists", snipeConfirmOver = 1000000 }
ns.Config = { Get = function(_, k) return settings[k] end }

local timers = {}
local savedTimer, savedFrame, savedTime = C_Timer, AuctionHouseFrame, GetTime
local clock = 100
GetTime = function() return clock end
C_Timer = { After = function(s, fn) timers[#timers + 1] = { at = clock + s, fn = fn } end }
AuctionHouseFrame = nil
local function Pass(seconds)
    local stop = clock + seconds
    while true do
        local soonest, idx
        for i, t in ipairs(timers) do
            if t.at <= stop and (not soonest or t.at < soonest) then soonest, idx = t.at, i end
        end
        if not idx then break end
        local t = table.remove(timers, idx)
        clock = math.max(clock, t.at)
        t.fn()
    end
    clock = stop
end

assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe:Init()

local requests, started, confirms = {}, {}, 0
ns.AHQueue = {
    BUDGET_MAX = 8, PRIORITY = { urgent = 10 },
    RecentSendCount = function() return 0 end,
    Request = function(_, r) requests[r.key] = r; return true end,
    Cancel = function() return true end,
}
local listings = { { unitPrice = 90, quantity = 3, numOwnerItems = 0 } }
local quoteLeft = 20
C_AuctionHouse = {
    GetItemCommodityStatus = function() return 2 end,
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = function() return true end,
    GetNumCommoditySearchResults = function() return #listings end,
    GetCommoditySearchResultInfo = function(_, i) return listings[i] end,
    StartCommoditiesPurchase = function(id, n) started[#started + 1] = { id, n } end,
    CancelCommoditiesPurchase = function() end,
    ConfirmCommoditiesPurchase = function() confirms = confirms + 1 end,
    GetQuoteDurationRemaining = function() return quoteLeft end,
}
Snipe.running, Snipe.spent, Snipe.noAutoStack = false, 0, true
Snipe.ASK_OUTSIDE_CLICK = false

local herb = { itemID = 40, kind = "lists", price = 90, worth = 100, qty = 3 }
Snipe.finds = { herb }

-- The click on Buy reads the listings, and the buy is planned.
Snipe:Buy(herb)
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 40)
assert(Snipe.pending and Snipe.pending.phase == "planned", "planned")
-- Pay (a click) asks for the price from inside the click.
assert(Snipe:Pay() == "checking")
assert(#started == 1)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 40, 270)
local buy = Snipe.pending
assert(buy and buy.phase == "quoted" and buy.total == 270, "the click got its price")

-- 1. Time passes past the price's life. No timer asks again.
quoteLeft = 0
Pass(Snipe.READY_KEEP + Snipe.QUOTE_WAIT + 5)
assert(#started == 1, "no ask from a timer: the game ignores it")
assert(not Snipe:Repricing(), "the button never waits on an answer that can't come")

-- 2. The buy stays, marked expired.
assert(Snipe.pending == buy, "the buy is not dropped quietly")
assert(buy.phase == "expired", "the price ran out")
assert(Snipe:Pay() == "checking", "a click asks again")
assert(#started == 2, "from inside the click")
assert(Snipe.pending and Snipe.pending.phase == "asking" and Snipe.pending.fromClick)

-- 3. The new price in, one more click pays.
quoteLeft = 20
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 40, 270)
assert(Snipe.pending.phase == "quoted")
assert(Snipe:QuoteLeft() == 20, "how long the price holds is known")
assert(Snipe:Pay() == true and confirms == 1, "one click pays")
handlers.COMMODITY_PURCHASE_SUCCEEDED()
assert(Snipe.pending == nil)

-- 4. Double Check Over still asks for Confirm.
settings.snipeConfirmOver = 100
herb.retryAt = nil
Snipe.finds = { herb }
Snipe:Buy(herb)
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 40)
Snipe:Pay()
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 40, 270)
assert(Snipe:Pay() == "confirm" and confirms == 1, "a big buy asks for Confirm")
assert(Snipe:Pay() == true and confirms == 2)

C_Timer, AuctionHouseFrame, GetTime = savedTimer, savedFrame, savedTime
C_AuctionHouse = nil
ns.AHQueue = nil
print("test_snipestaleprice: ok")
