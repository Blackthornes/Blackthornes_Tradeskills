-- The quick full scan that always gave way to the page-by-page one.
--
-- Trent, 2026-10-03: "it asks for a quick scan and then a few seconds later
-- it does a page by page even when it's been hours since the last scan."
--
--  * The wait for the snapshot was six seconds. As the auction house filled
--    up the server took longer than that to build it, so every quick scan
--    timed out.
--  * The answer that came after was thrown away because the page-by-page
--    scan had started, so it never counted as answered either.

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

print("\na quick full scan that is slow to answer")

--------------------------------------------------------------------------------
-- The wait is long enough for a big auction house
--------------------------------------------------------------------------------

Scanner:StartFullScan()
sendNext()
check("the quick scan was sent", replicateSent == 1)
local wait = live()[1]
check("it waits longer than six seconds before giving up", wait and wait.seconds >= 20)

-- It answers inside the wait.
replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("the answer is read", Prices:Get(SWORD) ~= nil and Prices:Get(AXE) ~= nil)
check("no page-by-page scan started", not Scanner.isBrowsing and not Scanner.browseQueued and #queue == 0)
check("the wait was stopped", wait.cancelled == true)
check("it counts as answered", ns.db.lastReplicateAnswered ~= nil)
check("and the scan is finished", not Scanner.isScanning and not Scanner.isReading)

--------------------------------------------------------------------------------
-- An answer after the wait still takes over from the page-by-page scan
--------------------------------------------------------------------------------

for k in pairs(priceTable) do priceTable[k] = nil end
timers, queue, printed, replicateCount = {}, {}, {}, 0
ns.db.lastReplicateRequest, ns.db.lastReplicateAnswered = nil, nil

Scanner:StartFullScan()
sendNext()
fire(live()[1]) -- no answer in time
check("the page-by-page scan waits its turn", Scanner.browseQueued == true)
sendNext() -- its first page goes out
check("and is running", Scanner.isBrowsing == true)

replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("the late answer is read", Prices:Get(SWORD) ~= nil)
check("chat says so", said("answered after all"))
check("the page-by-page scan is stopped", not Scanner.isBrowsing and not Scanner.browseQueued)
check("and leaves nothing waiting or timing", #queue == 0 and #live() == 0)
check("it counts as answered", ns.db.lastReplicateAnswered ~= nil)

-- The first page of the stopped sweep landing afterwards is not paged on.
browseResults = { { itemKey = { itemID = 123 }, minPrice = 10, totalQuantity = 1 } }
Scanner:OnBrowseResults()
check("a page landing after the stop asks for no more", #queue == 0 and not Scanner.isBrowsing)

--------------------------------------------------------------------------------
-- An answer after the page-by-page scan finished is still read
--------------------------------------------------------------------------------

for k in pairs(priceTable) do priceTable[k] = nil end
timers, queue, printed, replicateCount, browseResults, full = {}, {}, {}, 0, {}, false
ns.db.lastReplicateRequest, ns.db.lastReplicateAnswered = nil, nil

Scanner:StartFullScan()
sendNext()
fire(live()[1])
sendNext()
browseResults = { { itemKey = { itemID = 123 }, minPrice = 10, totalQuantity = 1 } }
full = true
Scanner:OnBrowseResults()
check("the page-by-page scan finished", not Scanner.isScanning)

replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("the snapshot arriving later is read", Prices:Get(SWORD) ~= nil)
check("and the scan is finished again", not Scanner.isScanning and not Scanner.isReading)

-- A second answer to the same request is not read twice.
for k in pairs(priceTable) do priceTable[k] = nil end
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("one request is read once", Prices:Get(SWORD) == nil)

--------------------------------------------------------------------------------
-- Somebody else's quick scan, or one after the auction house closed
--------------------------------------------------------------------------------

Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("an answer the addon did not ask for is left alone", Prices:Get(SWORD) == nil and not Scanner.isScanning)

ns.db.lastReplicateRequest = nil
Scanner:StartFullScan()
sendNext()
Scanner:CancelScan()
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("an answer after the scan was cancelled is left alone", Prices:Get(SWORD) == nil and not Scanner.isScanning)

print(("\n%d check(s) passed\n"):format(checks))
