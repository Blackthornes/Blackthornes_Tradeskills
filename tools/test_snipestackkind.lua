-- Snipe Buy It on a material: "Asking..." for a while, then nothing (a
-- player's report, 1.40.0).
--
-- Forever's GetItemCommodityStatus takes an item in the bags, never an item
-- ID: asked with an ID it raises. Snipe asked with the ID, so every find
-- read as "sold one at a time". A material's listings come back as
-- COMMODITY_SEARCH_RESULTS_UPDATED, which the one-at-a-time path never
-- reads, so the buy waited and was let go without a word. What must hold:
--   1. The event that answers says what the item is. A material the client
--      can't name still gets its units read and a buy made ready.
--   2. A click's buy is planned straight from the listings (the price can
--      only be asked inside a click), the next click asks, the next pays.
--   3. What the scanner learned is used, and what Snipe learns is kept.
--   4. An item sold one at a time still buys, also when it was guessed a
--      stack first.
--   5. No buy is ever let go without a line saying so.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Util = { HasFunction = function() return true end }
ns.Print = function() end
local said = {}
ns.Notice = { Show = function(_, text) said[#said + 1] = text end }
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local settings = { snipeCap = 300000, snipeWatch = "lists", snipeConfirmOver = 300000 }
ns.Config = { Get = function(_, k) return settings[k] end }

local timers = {}
local savedTimer, savedFrame, savedMoney = C_Timer, AuctionHouseFrame, GetMoney
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
AuctionHouseFrame = nil
GetMoney = function() return 10000000 end
local function RunTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe:Init()

local requests, started, confirmed, bids = {}, {}, {}, {}
ns.AHQueue = {
    BUDGET_MAX = 8, PRIORITY = { urgent = 10 },
    RecentSendCount = function() return 0 end,
    Request = function(_, r) requests[r.key] = r; return true end,
    Cancel = function() return true end,
}
-- What the scanner knows: only what it was taught.
local known = {}
ns.Scanner = {
    isAuctionHouseOpen = true,
    GetCommodityStatus = function(_, id) return known[id] end,
    LearnCommodity = function(_, id, stack) known[id] = stack end,
}
local listings = {
    { unitPrice = 90, quantity = 3, numOwnerItems = 0 },
    { unitPrice = 150, quantity = 30, numOwnerItems = 0 },
}
local itemRows = { { auctionID = 7, buyoutAmount = 5000, quantity = 1 } }
C_AuctionHouse = {
    -- As Forever: an item ID is refused.
    GetItemCommodityStatus = function(what)
        if type(what) ~= "table" then error("bad argument #1 to 'GetItemCommodityStatus'") end
        return 2
    end,
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = function() return true end,
    GetNumCommoditySearchResults = function() return #listings end,
    GetCommoditySearchResultInfo = function(_, i) return listings[i] end,
    GetNumItemSearchResults = function() return #itemRows end,
    GetItemSearchResultInfo = function(_, i) return itemRows[i] end,
    StartCommoditiesPurchase = function(id, n) started[#started + 1] = { id, n } end,
    CancelCommoditiesPurchase = function() end,
    ConfirmCommoditiesPurchase = function(id, n) confirmed[#confirmed + 1] = { id, n } end,
    PlaceBid = function(id, total) bids[#bids + 1] = { id, total } end,
}
Snipe.running, Snipe.spent, Snipe.noAutoStack = false, 0, nil

local herb = { itemID = 40, kind = "lists", price = 90, worth = 100, qty = 30 }
local sword = { itemID = 50, kind = "lists", price = 5000, worth = 6000, qty = 1 }
Snipe.finds = { herb, sword }

-- 1. A material the client can't name: the click reads its listings, and
-- they come back as a stack's.
Snipe:Buy(herb)
assert(Snipe.pending and Snipe.pending.find == herb, "the click asks")
requests["snipe-buy"].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 40)
assert(Snipe.pending, "the stack's listings were read, not waited past")
-- 2. Planned at once: no wait for a price that can't come outside a click.
assert(Snipe.pending.phase == "planned", "ready for the next click, got " .. tostring(Snipe.pending.phase))
assert(Snipe.pending.count == 3 and Snipe.pending.expected == 270)
assert(#started == 0, "no price asked outside a click")
assert(known[40] == true, "what the answer showed is kept")
-- Old timers must not take the planned buy away early.
assert(Snipe:Pay() == "checking" and #started == 1 and Snipe.pending.fromClick)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 90, 270)
assert(Snipe.pending.phase == "quoted" and Snipe.pending.total == 270)
assert(Snipe:Pay() == true and #confirmed == 1 and confirmed[1][2] == 3)
handlers.COMMODITY_PURCHASE_SUCCEEDED()
assert(Snipe.pending == nil and Snipe.spent == 270, "bought")
assert(#said == 0, "a buy that works says nothing")

-- 3. Known a stack now: the same path, straight away.
timers = {}
Snipe.finds = { herb, sword }
Snipe:Buy(herb)
assert(Snipe.pending.stack and Snipe.pending.phase == "listing")
Snipe:CancelBuy()

-- 4. Sold one at a time, and the scanner says so.
known[50] = false
Snipe:Buy(sword)
assert(Snipe.pending.phase == "asking" and not Snipe.pending.stack)
requests["snipe-buy"].send()
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 50 })
assert(Snipe.pending.phase == "quoted" and Snipe.pending.total == 5000)
assert(Snipe:Pay() == true and #bids == 1 and bids[1][1] == 7)
handlers.AUCTION_HOUSE_PURCHASE_COMPLETED()
assert(Snipe.pending == nil)

-- Guessed a stack (nothing known), but the answer is one-at-a-time rows.
known[50] = nil
Snipe.finds = { sword }
timers = {}
Snipe:Buy(sword)
assert(Snipe.pending.phase == "listing", "unknown reads as a stack first")
requests["snipe-buy"].send()
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 50 })
assert(Snipe.pending and Snipe.pending.phase == "quoted" and Snipe.pending.auctionID == 7,
    "the item answer is read")
assert(known[50] == false)
Snipe:CancelBuy()

-- Another item's answer (the player's own search) changes nothing.
known[40] = nil
timers = {}
Snipe.finds = { herb }
Snipe:Buy(herb)
requests["snipe-buy"].send()
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 999 })
assert(Snipe.pending.phase == "listing" and Snipe.pending.stack, "not ours: still waiting")

-- 5. No answer at all: let go, and say so.
said = {}
RunTimers()
assert(Snipe.pending == nil, "lets go")
assert(#said == 1 and said[1]:find("busy"), "says the auction house is busy")

-- The game says no to the price, or to the buy: a line each time.
for _, event in ipairs({ "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_FAILED" }) do
    said, timers = {}, {}
    known[40] = true
    Snipe.finds = { herb }
    Snipe:Buy(herb)
    requests["snipe-buy"].send()
    handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, 40)
    assert(Snipe:Pay() == "checking")
    handlers[event]()
    assert(Snipe.pending == nil and #said == 1, event .. " says why")
end

-- A buy readied in the background stays quiet.
said, timers = {}, {}
Snipe.finds = { herb }
Snipe:Buy(herb, true)
requests["snipe-buy"].send()
RunTimers()
assert(Snipe.pending == nil and #said == 0, "a quiet ready fails quietly")

C_Timer, AuctionHouseFrame, GetMoney = savedTimer, savedFrame, savedMoney
C_AuctionHouse = nil
ns.AHQueue, ns.Scanner = nil, nil
print("test_snipestackkind: ok")
