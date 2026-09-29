-- Quick full scan rows quote their whole quantity, commodities included.
--
-- The addon read a commodity row's buyout as the price of one. /bts verify on
-- Linen Cloth in game (2026-09-29) settled it: a fresh search said 40c each
-- and 84c market, while the quick scan had stored 83c as the cheapest and a
-- market of 13s 38c. Every reagent cost built on those numbers was inflated.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
local warnings = {}
local printed = {}
ns.Print = function(msg) printed[#printed + 1] = msg end
ns.PrintRaw, ns.Debug = function() end, function() end
ns.Warn = function(msg) warnings[#warnings + 1] = msg end

ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    Comma = function(n) return tostring(n) end,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    FormatAgeAgo = function() return "just now" end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    HasFunction = function(path)
        return path == "C_AuctionHouse.SendBrowseQuery"
            or path == "C_AuctionHouse.HasFullBrowseResults"
    end,
    WhenAuctionReady = function(action) action() end,
}

local settings = {}
local priceTable = {}
ns.Config = {
    Get = function(_, k) return settings[k] end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "TestRealm" end,
}
ns.Compat = { Get = function() return { auction = { hasReplicate = true, hasBrowseQuery = true } } end }
ns.db = {}
ns.Auctions = { GetOwnMinPrice = function() return nil end }

-- A queue that holds requests until the test says the budget lets one go,
-- which is what the real one does eight times in any fifteen seconds.
local queue = {}
ns.AHQueue = {
    PRIORITY = { urgent = 10, normal = 50, scan = 90 },
    Request = function(_, req) queue[#queue + 1] = req return true end,
    Cancel = function(_, key)
        for i = #queue, 1, -1 do if queue[i].key == key then table.remove(queue, i) end end
    end,
}
local function sendNext()
    local req = table.remove(queue, 1)
    assert(req, "nothing was waiting to be sent")
    return req.send()
end
local function giveUpNext()
    local req = table.remove(queue, 1)
    assert(req, "nothing was waiting to give up")
    if req.onGiveUp then req.onGiveUp() end
end

local ui = { completes = 0, progress = nil }
ns.UI = {
    SetScanProgress = function(_, f) ui.progress = f end,
    OnScanComplete = function() ui.completes = ui.completes + 1 ui.progress = nil end,
}

time = os.time
GetTime = function() return 1000 end

-- Timers are kept so the test can run one out. A cancelled one never fires.
local timers = {}
C_Timer = {
    NewTimer = function(seconds, fn)
        local t = { seconds = seconds, fn = fn }
        t.Cancel = function() t.cancelled = true end
        timers[#timers + 1] = t
        return t
    end,
    After = function() end,
}
local function live()
    local out = {}
    for _, t in ipairs(timers) do if not t.cancelled and not t.fired then out[#out + 1] = t end end
    return out
end
local function fire(t) t.fired = true t.fn() end

Enum = { ItemCommodityStatus = { Commodity = 2 }, BagIndex = {} }
UnitName = function() return "Tester" end
GetRealmName = function() return "TestRealm" end

local browseResults, full = {}, false
local replicateSent = 0
C_AuctionHouse = {
    GetBrowseResults = function() return browseResults end,
    HasFullBrowseResults = function() return full end,
    RequestMoreBrowseResults = function() return true end,
    SendBrowseQuery = function() return true end,
    ReplicateItems = function() replicateSent = replicateSent + 1 end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)

local Prices, Scanner = ns.Prices, ns.Scanner
Scanner.isAuctionHouseOpen = true

-- Run the worker straight through.
ns.Util.NewWorker = function(opts)
    return { Start = function(_, items)
        for _, item in ipairs(items) do opts.onItem(item) end
        if opts.onDone then opts.onDone() end
    end, Run = function(self, items) self:Start(items) end }
end
ns.Util.UnitPriceFromStack = function(_, total, quantity)
    if not quantity or quantity <= 1 or total < quantity then return total end
    return math.floor(total / quantity)
end
ns.Util.GetMaxStackSize = function() return 20 end

local LINEN, SWORD = 2589, 9999
local rows = {
    -- count, buyout (the whole row), itemID
    { 2, 83, LINEN },     -- 41.5c each
    { 250, 10000, LINEN },-- 40c each, a row bigger than a stack
    { 1, 45, LINEN },
    { 1, 5000, SWORD },   -- an item auction
}
C_AuctionHouse.GetReplicateItemInfo = function(index)
    local row = rows[index + 1]
    if not row then return nil end
    return "x", 0, row[1], 1, true, 1, "", 0, 0, row[2], 0, false, nil,
        "Rival", "Rival-TestRealm", 0, row[3], true
end
Scanner.IsCommodity = function(_, itemID) return itemID == LINEN end
Scanner.GetCommodityStatus = function(_, itemID) return itemID == LINEN end

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

-- What the old reading left behind: a market 16 times too high.
priceTable[LINEN] = { market = 1338, min = 83, scans = 5, history = {}, seen = 1 }

print("\nreading a quick full scan")
local ok, err = pcall(Scanner.ReadReplicateResults, Scanner, #rows)
if not ok then error(err, 0) end

local linen = Prices:Get(LINEN)
check("linen was recorded", linen ~= nil)
check("its cheapest is 40c each, not a whole row", linen and linen.min == 40)
check("its market is near 40c, not in silver", linen and linen.market and linen.market < 50)
check("the old history is kept", linen and linen.history ~= nil)

-- Only once: after that, market value averages across scans as usual.
check("the reset is remembered", ns.db.commodityRowPriceFixed == true)
linen.market = 60
Scanner:ReadReplicateResults(#rows)
check("a later scan averages instead of starting afresh", Prices:Get(LINEN).market > 45)
local sword = Prices:Get(SWORD)
check("an item auction of one is still its buyout", sword and sword.min == 5000)

print(("\n%d check(s) passed\n"):format(checks))
