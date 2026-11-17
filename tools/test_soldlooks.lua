-- Sold a day and single item looks.
--
-- A full scan reads every listing of an item. A look at one item (yours from
-- the sell tab, or the player's own search) may read only the first page of
-- the book, so its count can be far under what is listed. Each fall from a
-- full count to a look's count was added up as sales: Mithril Tube read
-- 147, 171, 187, 170, 191, 14, 18, 201, 201, 244, 128, 19 and showed about
-- 500 a day, when the full scans alone moved far less.
--
--   1. A look the client does not call complete keeps its count out of the
--      readings Sold a day measures, and out of the seven day counts.
--   2. Full scans around it still count their own falls.
--   3. A look the client calls complete counts like a full scan.
--   4. The price and the book from a look are still learned.
--   5. An old save that already holds a look's small count still reads.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local hasFull = {}
ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    Comma = tostring,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    FormatAgeAgo = function() return "" end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    GetMaxStackSize = function() return 20 end,
    UnitPriceFromStack = function(_, buyout, quantity) return math.floor(buyout / (quantity or 1)) end,
    HasFunction = function(path) return hasFull[path] ~= nil end,
    ItemAuctionPrice = function(p) return p end,
}

local priceTable = {}
ns.Config = {
    Get = function() return nil end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "TestRealm" end,
}
ns.db = {}
ns.AHQueue = { PRIORITY = { urgent = 10, normal = 50, scan = 90 } }
ns.Inventory = { GetCarriedBags = function() return { 0 } end }

-- A clock the test moves by hand. Day 20000 at 01:00, so 0.84 days stays
-- inside one day and the seven day counts land on a single day.
local clock = 20000 * 86400 + 3600
time = function() return clock end
GetTime = function() return clock end
C_Timer = { NewTimer = function() return { Cancel = function() end } end, After = function() end }
Enum = { ItemCommodityStatus = { Commodity = 2 }, BagIndex = { ReagentBag = 5 } }
UnitName = function() return "Tester" end
GetRealmName = function() return "TestRealm" end
C_Container = { GetContainerNumSlots = function() return 0 end }

local commodityRows, itemRows = {}, {}
C_AuctionHouse = {
    GetNumCommoditySearchResults = function() return #commodityRows end,
    GetCommoditySearchResultInfo = function(_, i) return commodityRows[i] end,
    GetNumItemSearchResults = function() return #itemRows end,
    GetItemSearchResultInfo = function(_, i) return itemRows[i] end,
    HasFullCommoditySearchResults = function() return hasFull["C_AuctionHouse.HasFullCommoditySearchResults"] end,
    HasFullItemSearchResults = function() return hasFull["C_AuctionHouse.HasFullItemSearchResults"] end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)
local Prices, Scanner = ns.Prices, ns.Scanner
Scanner.isAuctionHouseOpen = true

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.5 end

-- 12 readings over 0.84 days, as in the save.
local STEP = math.floor(0.84 * 86400 / 11)

-- A full scan's reading, as the browse scan records it (no book).
local function FullScan(itemID, q)
    Prices:Record(itemID, 5000, 5000, q, clock, 5000, nil)
end

-- A look whose book shows only two price steps: 12, then the rest.
local function Look(itemID, q, mine)
    commodityRows = { { unitPrice = 5000, quantity = 12 }, { unitPrice = 5100, quantity = q - 12 } }
    if mine then
        Scanner.pendingItem = { itemID = itemID }
    else
        Scanner.pendingItem = nil
    end
    Scanner.passiveSeen = nil
    Scanner:COMMODITY_SEARCH_RESULTS_UPDATED(nil, itemID)
end

local function Play(itemID, readings)
    for i, r in ipairs(readings) do
        if i > 1 then clock = clock + STEP end
        if r.look then Look(itemID, r.q, r.mine) else FullScan(itemID, r.q) end
    end
end

local function Sold(itemID)
    local week = Prices:GetDailySales(itemID, clock)
    return week and week[#week]
end

local TUBE = {
    { q = 147 }, { q = 171 }, { q = 187 }, { q = 170 }, { q = 191 },
    { q = 14, look = true, mine = true }, { q = 18, look = true },
    { q = 201 }, { q = 201 }, { q = 244 }, { q = 128 },
    { q = 19, look = true, mine = true },
}

print("\nlooks the client does not call complete")
Play(10559, TUBE)
local full = (187 - 170) + (244 - 128)                -- 133 gone between full scans
local days = (10 * STEP) / 86400                      -- the 128 is the last full one
local perDay = Prices:GetUnitsSoldPerDay(10559)
check("Sold a day counts only the full scans' falls (" .. tostring(perDay) .. ")",
    near(perDay, full / days))
check("far under the 499 the looks made it", perDay < 200)
check("the seven day count holds only the full scans' falls", Sold(10559) == full)
check("the look's price is still learned", Prices:GetTable()[10559].scans == 12)
check("and its book", Prices:GetTable()[10559].ladder ~= nil)

print("\nlooks the client calls complete")
hasFull["C_AuctionHouse.HasFullCommoditySearchResults"] = true
clock = 20010 * 86400 + 3600
Play(2000, {
    { q = 200 }, { q = 180, look = true, mine = true }, { q = 170, look = true }, { q = 160 },
})
check("a complete look counts like a full scan", near(Prices:GetUnitsSoldPerDay(2000), 40 / (3 * STEP / 86400)))
check("and in the seven day count", Sold(2000) == 40)
hasFull["C_AuctionHouse.HasFullCommoditySearchResults"] = nil

print("\nan item look (not by the unit)")
clock = 20020 * 86400 + 3600
FullScan(3000, 100)
clock = clock + STEP
itemRows = { { buyoutAmount = 900, quantity = 5 } }
Scanner.pendingItem = nil
Scanner.passiveSeen = nil
Scanner:ITEM_SEARCH_RESULTS_UPDATED(nil, { itemID = 3000 })
clock = clock + STEP
FullScan(3000, 95)
check("an incomplete item look is left out too", near(Prices:GetUnitsSoldPerDay(3000), 5 / (2 * STEP / 86400)))
check("and from the seven day count", Sold(3000) == 5)

print("\nan old save")
priceTable[4000] = { scans = 3, history = { 0, 10, 150, false, false, false, 7200, 10, 20 } }
check("a save with a look's count already in it still reads", near(Prices:GetUnitsSoldPerDay(4000), 130 / (7200 / 86400)))
priceTable[4001] = { scans = 2, history = { { t = 0, q = 150 }, { t = 7200, m = 10 }, { t = 14400, q = 140 } } }
check("a reading with no count is passed over", near(Prices:GetUnitsSoldPerDay(4001), 10 / (14400 / 86400)))

print("\nthe older sales hint")
priceTable[4002] = { scans = 3, history = { 0, 10, 100, 3600, 10, false, 7200, 10, 90 } }
check("a reading with no count is not read as a sell-out", near(Prices:GetLiquidity(4002) * 100, 10))

print(("\n%d check(s) passed\n"):format(checks))
