-- Another addon's quick full scan.
--
-- The quick full scan can be asked for about once every fifteen minutes,
-- and another addon asking first uses that up. Tradeskills asked anyway,
-- heard nothing, and only gave way to the page-by-page scan half a minute
-- later (2026-10-20). Now it notices the other request and goes straight
-- to pages, saying so.

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

-- hooksecurefunc on a table: run the hook after the original. Put back
-- after OnEnable, since the suites share one Lua.
local savedHook = hooksecurefunc
hooksecurefunc = function(t, method, hook)
    local original = t[method]
    t[method] = function(...)
        local a, b, c = original(...)
        hook(...)
        return a, b, c
    end
end

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)

local Prices, Scanner = ns.Prices, ns.Scanner
Scanner.isAuctionHouseOpen = true

ns.Util.NewWorker = function(opts)
    return { Start = function(_, items)
        for _, item in ipairs(items) do opts.onItem(item) end
        if opts.onDone then opts.onDone() end
    end, IsRunning = function() return false end }
end
ns.Util.UnitPriceFromStack = function(_, total) return total end
ns.Util.GetMaxStackSize = function() return 20 end
Scanner.IsCommodity = function() return false end
Scanner.GetCommodityStatus = function() return false end

local SWORD, AXE = 9999, 9998
local rows = { { 1, 5000, SWORD }, { 1, 7000, AXE } }
local replicateCount = 0
C_AuctionHouse.GetNumReplicateItems = function() return replicateCount end
C_AuctionHouse.GetReplicateItemInfo = function(index)
    local row = rows[index + 1]
    if not row then return nil end
    return "x", 0, row[1], 1, true, 1, "", 0, 0, row[2], 0, false, nil,
        "Rival", "Rival-TestRealm", 0, row[3], true
end

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end
local function said(text)
    for _, line in ipairs(printed) do if line:find(text, 1, true) then return true end end
    return false
end

Scanner:OnEnable()
hooksecurefunc = savedHook

print("\nanother addon's quick full scan")

-- Our own quick scan is not taken for another addon's.
Scanner:StartFullScan()
sendNext()
check("our own quick scan was sent", replicateSent == 1)
check("and is not counted as another addon's", not ns.db.lastReplicateByOther)
replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("and is read", Prices:Get(SWORD) ~= nil and not Scanner.isScanning)

-- Another addon asks.
for k in pairs(priceTable) do priceTable[k] = nil end
timers, queue, printed, replicateCount = {}, {}, {}, 0
ns.db.lastReplicateRequest, ns.db.lastReplicateAnswered = nil, nil
C_AuctionHouse.ReplicateItems()
check("another addon's request is noticed", ns.db.lastReplicateByOther == true)
check("and starts the cooldown", Scanner:GetSnapshotCooldown() ~= nil)

local before = replicateSent
Scanner:StartFullScan()
check("chat says what happened",
    said("Another addon just did a full scan, so doing a page by page scan instead."))
check("no quick scan of our own is asked for", replicateSent == before and #queue == 1)
check("the page-by-page scan waits its turn", Scanner.browseQueued == true)
sendNext()
check("and runs", Scanner.isBrowsing == true)
local quickWait = false
for _, t in ipairs(live()) do if t.seconds >= 20 then quickWait = true end end
check("with no half-minute wait for an answer", not quickWait)

-- With Auctionator loaded, chat says how to get the quick scan back.
Scanner:StopBrowse()
Scanner.isScanning = false
timers, queue, printed = {}, {}, {}
Auctionator = {}
Scanner:StartFullScan()
Auctionator = nil
check("with Auctionator loaded, chat says to turn off its scan",
    said("Turn off Auctionator's scan when the auction house opens to get the quick scan back."))
check("and still scans page by page", Scanner.browseQueued == true)
sendNext()

-- Its answer is still left alone.
replicateCount = #rows
Scanner:StopBrowse()
Scanner.isScanning = false
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("another addon's answer is left alone", Prices:Get(SWORD) == nil)

-- Once the cooldown is ours again, the old line comes back.
timers, queue, printed = {}, {}, {}
ns.db.lastReplicateRequest = time() - 20 * 60
Scanner:StartFullScan()
sendNext()
check("after the cooldown our quick scan goes again", replicateSent == before + 1)
check("and the flag is cleared", not ns.db.lastReplicateByOther)

print(("\n%d check(s) passed\n"):format(checks))
