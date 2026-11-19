-- Snipe offers only what the Spending Cap can buy (a player's report,
-- 2026-11-19: a 1g cap still listed snipes at 8g, 10g and 20g each).
--
-- What must hold:
--   1. A deal whose single unit costs more than the cap left is not a find.
--      Prices are each, so a stack of 5 at 8g each is out under a 1g cap.
--   2. A deal the cap can buy one of is still offered.
--   3. After a buy, finds the cap left can no longer reach are taken out.
--   4. Clicking a find the cap can't reach, while cap money is left, says so
--      and keeps the session going for cheaper finds.

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
C_Timer = { After = function() end }
GetTime = function() return 100 end

assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe:Init()

local G, S = 10000, 100
-- Worth by item: a pattern, a formula, shoulders (the screenshot) and a
-- cheap cloth the cap can reach.
local worth = { [1] = 64 * G, [2] = 107 * G, [3] = 49 * G, [4] = 2 * G }
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
local rows = {}
C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id } end,
    SearchForItemKeys = function() end,
    GetBrowseResults = function() return rows end,
    HasFullBrowseResults = function() return true end,
    GetItemCommodityStatus = function() return 1 end,
}

-- The player's setup: a 1g cap, Snipe Below 70%.
settings.snipeCap, settings.snipePct, settings.snipeWatch = 1 * G, 70, "priced"
Snipe:Start()
assert(Snipe:IsRunning(), "started")
assert(requests.snipe and requests.snipe.send() == true, "searched")
rows = {
    { itemKey = { itemID = 1 }, minPrice = 7 * G + 99 * S, totalQuantity = 5 },
    { itemKey = { itemID = 2 }, minPrice = 20 * G, totalQuantity = 11 },
    { itemKey = { itemID = 3 }, minPrice = 10 * G, totalQuantity = 7 },
    { itemKey = { itemID = 4 }, minPrice = 80 * S, totalQuantity = 3 },
}
Snipe:OnBrowseResults()

-- 1 and 2.
local finds = Snipe:Finds()
assert(#finds == 1, "only the find the cap can buy is listed, got " .. #finds)
assert(finds[1].itemID == 4, "the 80s cloth stays")

-- 3. A buy leaves 20s: the 80s cloth is out of reach now.
Snipe.pending = { itemID = 9, count = 1, total = 80 * S, phase = "buying", item = true }
Snipe:Bought()
assert(Snipe:Left() == 20 * S, "20s left")
assert(#Snipe:Finds() == 0, "nothing left the cap can reach")
assert(Snipe:IsRunning(), "cap money is left, so it keeps watching")

-- 4. A find out of reach, clicked while cap money is left.
local pricey = { itemID = 1, kind = "priced", price = 8 * G, worth = 64 * G, qty = 5 }
Snipe.finds = { pricey }
Snipe:Buy(pricey)
assert(Snipe:IsRunning(), "one costly find doesn't stop the session")
assert(said[#said] == "That costs more than your Spending Cap has left.", "says why")
assert(#Snipe:Finds() == 0, "and it leaves the list")

Snipe:Stop()
C_Timer, GetTime = oldTimer, oldGetTime
C_AuctionHouse, C_Item, ns.AHQueue, ns.Prices = nil, nil, nil, nil
print("snipe cap: all checks passed")
