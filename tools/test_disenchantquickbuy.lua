-- Buy One on the Disenchanting tab (the owner said build it, 2026-11-24).
--
-- Buying a pile of one deal took Buyout and Accept for every listing. Once
-- the Search button's search is back, the same button buys the cheapest
-- listing on each click. What must hold:
--   1. The limit is the highest price that still meets the Disenchanting
--      minimums, and listings over it are never offered.
--   2. Your own listings are skipped.
--   3. One click is one PlaceBid, cheapest first, and the buy is marked to
--      disenchant. A click while a buy waits on the game sends nothing.
--   4. A buy at or over Double Check Over takes a second click.
--   5. A refused buy moves on; when none are left the state is "done" with
--      the count and money bought.
--   6. Nothing buys outside a click: results and events never PlaceBid.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Util = {
    HasFunction = function() return true end,
    FormatMoney = function(c) return tostring(c) end,
}
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local settings = { minProfit = 0, minMarginPercent = 0 }
ns.Config = { Get = function(_, k) return settings[k] end }
ns.Profit = { DisenchantMinimums = function() return 100, 10 end }
ns.Scanner = { isAuctionHouseOpen = true }
local intents = {}
ns.DisenchantBuys = { Intend = function(_, id) intents[#intents + 1] = id end }

local timers = {}
local savedTimer = C_Timer
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

local money = 1000000
GetMoney = function() return money end

local requests = {}
ns.AHQueue = {
    PRIORITY = { urgent = 10 },
    Request = function(_, r) requests[r.key] = r; return true end,
}

local listings
local bids = {}
C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = function() return true end,
    GetNumItemSearchResults = function() return #listings end,
    GetItemSearchResultInfo = function(_, i) return listings[i] end,
    PlaceBid = function(id, total) bids[#bids + 1] = { id, total } end,
}

assert(loadfile(lfs_cwd .. "/Logic/DisenchantQuickBuy.lua"))("Blackthornes_TS", ns)
local Q = ns.DisenchantQuickBuy
Q:Init()

-- 1. The limit. Net 1000, at least 100 profit and a 10% margin:
-- 1000 - 100 = 900, 1000 / 1.1 = 909, so 900.
assert(Q.MostToPay(1000, 100, 10) == 900, "limit is " .. tostring(Q.MostToPay(1000, 100, 10)))
assert(Q.Clears(900, 1000, 100, 10) and not Q.Clears(901, 1000, 100, 10))
-- A big margin rules: 50% of 1000 is 666.
assert(Q.MostToPay(1000, 1, 50) == 666)
assert(Q.MostToPay(0, 0, 0) == nil)
print("ok: the limit meets the minimums")

-- The search, then the listings come back.
listings = {
    { auctionID = 5, buyoutAmount = 700, quantity = 1 },
    { auctionID = 1, buyoutAmount = 500, quantity = 1 },
    { auctionID = 2, buyoutAmount = 400, quantity = 1, containsOwnerItem = true },
    { auctionID = 3, buyoutAmount = 950, quantity = 1 },
    { auctionID = 4, buyoutAmount = 600, quantity = 1 },
}
assert(Q:Start({ itemID = 77, net = 1000 }))
assert(Q:StateFor(77) == "asking" and Q:StateFor(78) == nil)
-- Results before the search was sent are not ours yet.
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 77 })
assert(Q:StateFor(77) == "asking")
assert(requests["de-quickbuy"].send())
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 99 })
assert(Q:StateFor(77) == "asking", "another item's results are not ours")
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 77 })
assert(Q:StateFor(77) == "ready")
assert(#bids == 0, "reading results never buys")

-- 2. Own listing (400) skipped, 950 over the limit: 500, 600, 700.
assert(Q:Next().auctionID == 1 and Q:Next().total == 500)
assert(Q:MoreAfterNext() == 2)
print("ok: own listings and listings over the limit are left out")

-- 3. One click, one buy, cheapest first, marked to disenchant.
assert(Q:Click() == true)
assert(#bids == 1 and bids[1][1] == 1 and bids[1][2] == 500)
assert(intents[1] == 77)
assert(Q:Click() == false and #bids == 1, "a click while a buy waits sends nothing")
money = money - 500
handlers.PLAYER_MONEY()
handlers.AUCTION_HOUSE_PURCHASE_COMPLETED(nil, nil, 1)
assert(Q.current.bought == 1 and Q.current.spent == 500, "counted once")
assert(Q:Next().auctionID == 4 and Q:MoreAfterNext() == 1)
-- The game's list refresh still holds the bought one: it is not offered again.
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 77 })
assert(Q:Next().auctionID == 4)
print("ok: one click buys the cheapest, then readies the next")

-- 4. Double Check Over at 650: the 700 listing asks for Confirm.
settings.snipeConfirmOver = 650
assert(Q:Click() == true and bids[2][1] == 4)
handlers.AUCTION_HOUSE_PURCHASE_COMPLETED(nil, nil, 4)
assert(Q:Next().auctionID == 5)
assert(Q:Click() == "confirm" and #bids == 2)
assert(Q:StateFor(77) == "confirm")
RunTimers() -- the confirm runs out
assert(Q:StateFor(77) == "ready")
assert(Q:Click() == "confirm")
assert(Q:Click() == true and #bids == 3 and bids[3][1] == 5)
print("ok: a big buy takes a second click")

-- 5. The game refuses it (sold already): nothing left, so done.
handlers.AUCTION_HOUSE_SHOW_ERROR()
assert(Q:StateFor(77) == "done")
assert(Q.current.bought == 2 and Q.current.spent == 1100)
assert(Q:Click() == false and #bids == 3)
print("ok: done says how many were bought")

-- 6. Timers never buy; the auction house closing lets it go.
RunTimers()
assert(#bids == 3)
handlers.AUCTION_HOUSE_CLOSED()
assert(Q.current == nil and Q:StateFor(77) == nil)
print("ok: nothing buys outside a click")

-- Not enough money: says so, buys nothing.
listings = { { auctionID = 9, buyoutAmount = 500, quantity = 1 } }
money = 100
settings.snipeConfirmOver = nil
Q:Start({ itemID = 77, net = 1000 })
requests["de-quickbuy"].send()
handlers.ITEM_SEARCH_RESULTS_UPDATED(nil, nil, { itemID = 77 })
assert(Q:Click() == false and #bids == 3 and #printed == 1)
print("ok: short of money buys nothing")

C_Timer = savedTimer
C_AuctionHouse, GetMoney = nil, nil
print("disenchant quick buy: all passed")
