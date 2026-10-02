-- Quick full scan rows for commodities the addon has not been told about.
--
-- Most reagents are commodities nobody has held or searched yet, so their
-- status is unknown. A row bigger than a stack was then read as an item
-- auction, and the stack-size guard kept its whole price as the price of one:
-- Wool Cloth at 1s each was stored at 40s. No item auction holds more than a
-- stack, so such a row is a commodity's and is divided like one.
--
-- The fresh start for commodity markets built from whole-row prices is marked
-- on each price, not once for the account. Prices are kept per realm and
-- faction, and the account-wide mark let only the first realm scanned start
-- afresh: the second kept its inflated market for about ten scans.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "GetTime", "time", "C_Timer", "C_Item", "C_AuctionHouse" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local function Blank()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end

CreateFrame = function() return Blank() end
GetTime = function() return 1000 end
time = function() return 100000 end
C_Timer = {
    After = noop,
    NewTimer = function() return { Cancel = noop } end,
    NewTicker = function() return { Cancel = noop } end,
}

local LINEN, WOOL, BAR, SWORD = 2589, 2592, 2840, 9999

-- Cloth and bars stack to 20 here, a sword to 1. The stack size is the
-- eighth thing the game says about an item.
local stackSizes = { [LINEN] = 20, [WOOL] = 20, [BAR] = 20, [SWORD] = 1 }
C_Item = {
    GetItemInfo = function(itemID)
        local stack = stackSizes[itemID]
        if not stack then return nil end
        return "item", "link", 1, 1, 1, "Trade Goods", "Cloth", stack
    end,
}

-- The snapshot's rows: how many, the buyout of the whole row, the item. No
-- GetItemCommodityStatus, so only what is on record says what a commodity is.
local rows = {}
C_AuctionHouse = {
    GetReplicateItemInfo = function(index)
        local row = rows[index + 1]
        if not row then return nil end
        return "x", 0, row[1], 1, true, 1, "", 0, 0, row[2], 0, false, nil,
            "Rival", "Rival-TestRealm", 0, row[3], true
    end,
}

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop

-- Prices are kept per realm and faction.
local realm = "TestRealm-Alliance"
local priceTables = {}
ns.db = { commodity = {} }
ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return realm end,
    GetPriceTable = function()
        priceTables[realm] = priceTables[realm] or {}
        return priceTables[realm]
    end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)

local Prices, Scanner = ns.Prices, ns.Scanner

-- Run the worker straight through.
ns.Util.NewWorker = function(opts)
    return { Start = function(_, items)
        for _, item in ipairs(items) do opts.onItem(item) end
        if opts.onDone then opts.onDone() end
    end }
end

local function QuickScan(snapshot)
    rows = snapshot
    Scanner.isScanning = true
    Scanner.scanStartedWall = time()
    Scanner:ReadReplicateResults(#rows)
end

local passed, failed = 0, 0
local function check(label, condition)
    if condition then
        passed = passed + 1
        print(("  ok    %s"):format(label))
    else
        failed = failed + 1
        print(("  FAIL  %s"):format(label))
    end
end

print("")
print("a commodity nobody has said is one")

QuickScan({
    { 100, 10000, WOOL },   -- 1s each, more than a stack
    { 40, 4000, WOOL },     -- 1s each, more than a stack
    { 5, 200, LINEN },      -- 40c each, a stack's worth
    { 200, 8000, LINEN },   -- 40c each, more than a stack
    { 60, 2400, LINEN },    -- 40c each, more than a stack
})

do
    local wool, linen = Prices:Get(WOOL), Prices:Get(LINEN)
    check("nothing on record says wool is a commodity", Scanner:GetCommodityStatus(WOOL) == nil)
    check("wool at 1s each is not stored at a whole row's price",
        wool ~= nil and wool.min == 100 and wool.rivalMin == 100)
    check("and its market is 1s", wool ~= nil and wool.market == 100)
    check("linen reads 40c whatever the size of the row",
        linen ~= nil and linen.min == 40 and linen.rivalMin == 40 and linen.market == 40)
    check("so the small row is not left out as a lone low one", linen ~= nil and linen.ignoredLow == nil)
end

print("")
print("item auctions read as before")

QuickScan({
    { 5, 500, BAR },        -- a stack of 5 at 1s each
    { 1, 5000, SWORD },     -- one sword
})

check("a stack the item can hold is still divided", Prices:Get(BAR) ~= nil and Prices:Get(BAR).min == 100)
check("an item auction of one is still its buyout", Prices:Get(SWORD) ~= nil and Prices:Get(SWORD).min == 5000)

print("")
print("every realm's commodity markets start afresh once")

-- A player who had the old account-wide mark: one realm already started
-- afresh before this, and the other never did.
local function Inflated()
    return { market = 1338, min = 83, scans = 5, history = { { t = 1, m = 1338, q = 15 } }, seen = 1 }
end
ns.db.commodity[LINEN] = true
ns.db.commodityRowPriceFixed = true
priceTables = {
    ["TestRealm-Alliance"] = { [LINEN] = Inflated() },
    ["TestRealm-Horde"] = { [LINEN] = Inflated() },
}

local linenRows = { { 10, 400, LINEN }, { 5, 200, LINEN } }

realm = "TestRealm-Alliance"
QuickScan(linenRows)
check("the first realm's market starts afresh", Prices:Get(LINEN).market == 40)
check("its history is kept", #Prices:Get(LINEN).history == 2)

realm = "TestRealm-Horde"
QuickScan(linenRows)
check("so does the second realm's", Prices:Get(LINEN).market == 40)
check("each price is marked as started afresh",
    priceTables["TestRealm-Alliance"][LINEN].rowPriceFixed == true
    and priceTables["TestRealm-Horde"][LINEN].rowPriceFixed == true)
check("the old account-wide mark is left as it was", ns.db.commodityRowPriceFixed == true)

-- Only once: after that the market averages across scans as usual.
Prices:Get(LINEN).market = 60
QuickScan(linenRows)
check("a later scan averages instead of starting afresh", Prices:Get(LINEN).market == 54)

-- A commodity first priced in a scan is marked by that scan, so it is never
-- started afresh later.
QuickScan({ { 100, 10000, WOOL } })
check("a commodity new to this realm is marked too", Prices:Get(WOOL).rowPriceFixed == true)
Prices:Get(WOOL).market = 300
QuickScan({ { 100, 10000, WOOL } })
check("and averages on its next scan", Prices:Get(WOOL).market == 240)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "quick scan row checks failed")
