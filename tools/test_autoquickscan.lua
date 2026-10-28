-- The auto scan's quick scan (the owner, 2026-10-28).
--
-- Auto Scan used to scan only when prices were two days old. Now, once a
-- visit, it asks for one quiet quick scan when the last scan is over fifteen
-- minutes old: never in a fight, never while the quick scan is cooling down,
-- and never page by page when it does not answer.

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

local lastScan, count = nil, 0
Prices.GetLastScan = function() return lastScan end
Prices.Count = function() return count end
ns.AHQueue.PlayerIsSelling = function() return false end
local fighting = false
local savedCombat = InCombatLockdown
InCombatLockdown = function() return fighting end
settings.autoScan = true

local function reset()
    timers, queue, printed = {}, {}, {}
    Scanner.isScanning, Scanner.scanQueued, Scanner.browseQueued = false, false, false
    Scanner.isBrowsing, Scanner.awaitingReplicate, Scanner.quickOnly = false, false, false
    ns.db.lastReplicateRequest, ns.db.lastReplicateByOther = nil, nil
    replicateCount = 0
    Scanner:AUCTION_HOUSE_SHOW()
end

print("\nthe auto scan's quick scan")

reset()
count, lastScan = 50, time() - 5 * 60
Scanner:ConsiderAutoScan()
check("a scan five minutes ago: nothing starts", #queue == 0 and not Scanner.scanQueued)

reset()
count, lastScan = 50, time() - 20 * 60
local before = replicateSent
Scanner:ConsiderAutoScan()
check("twenty minutes ago: a quick scan waits its turn", #queue == 1 and Scanner.quickOnly == true)
check("and nothing is said in chat", #printed == 0)
sendNext()
check("it is sent", replicateSent == before + 1)
replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("and read", Prices:Get(SWORD) ~= nil and not Scanner.isScanning)
check("still quiet", #printed == 0)

-- Once a visit, whatever happened.
local queued = #queue
Scanner:ConsiderAutoScan()
check("not again on the same visit", #queue == queued and not Scanner.scanQueued)

-- The quick scan cooling down: nothing, and no page-by-page sweep.
reset()
ns.db.lastReplicateRequest = time() - 60
Scanner:ConsiderAutoScan()
check("cooling down: nothing starts", #queue == 0 and not Scanner.browseQueued)
check("nothing said", #printed == 0)

-- No answer: it stands down quietly, still listening for a late one.
reset()
Scanner:ConsiderAutoScan()
sendNext()
local waits = live()
check("it waits for an answer", #waits == 1)
fire(waits[1])
check("no answer: no page-by-page sweep", not Scanner.isBrowsing and not Scanner.browseQueued)
check("the scan ends", not Scanner.isScanning)
check("nothing said", #printed == 0)
check("a late answer is still listened for", Scanner.awaitingReplicate == true)
replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("and read when it comes", not Scanner.awaitingReplicate and not Scanner.isScanning)

-- An empty answer: the same.
reset()
Scanner:ConsiderAutoScan()
sendNext()
replicateCount = 0
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("an empty answer: no sweep", not Scanner.isBrowsing and not Scanner.browseQueued and #printed == 0)

-- In a fight it waits.
reset()
fighting = true
Scanner:ConsiderAutoScan()
check("in a fight: nothing starts", #queue == 0)
fighting = false

-- Turned off: nothing.
reset()
settings.autoScan = false
Scanner:ConsiderAutoScan()
check("Auto Scan off: nothing", #queue == 0)
settings.autoScan = true

-- No prices at all: the full scan as before, page by page if it must.
reset()
count, lastScan = 0, nil
ns.db.lastReplicateRequest = time() - 60
Scanner:ConsiderAutoScan()
check("no prices: it scans anyway, page by page", Scanner.browseQueued == true)
check("and says so", said("no price data, so scanning automatically"))

-- The Scan button still says what it does.
reset()
count, lastScan = 50, time() - 20 * 60
Scanner:StartFullScan()
check("the Scan button still talks", said("asking for a quick full scan..."))
check("and is not quick only", Scanner.quickOnly == false)

InCombatLockdown = savedCombat
print(("\n%d checks passed"):format(checks))
