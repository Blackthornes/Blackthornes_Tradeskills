-- The status line and progress bar on the auction house bar.
--
-- Trent, 2026-09-27: "can we get a scan progress bar on that bar to show the
-- player that it's scanning?" The bar reads Scanner:GetScanStatus a few times
-- a second, so what it shows has to come from the scanner's real state at
-- every step: waiting its turn, asking for the quick scan, each page of a
-- sweep, and nothing once the scan is over. A finished scan hands the UI its
-- count so the bar can celebrate it; a cancelled one hands it nothing.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
local warnings = {}
ns.Print, ns.PrintRaw, ns.Debug = function() end, function() end, function() end
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
    OnScanComplete = function(_, result)
        ui.completes = ui.completes + 1 ui.progress = nil ui.result = result
    end,
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

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function addPage(n)
    for i = 1, 50 do
        local id = 10000 + n * 100 + i
        browseResults[#browseResults + 1] = { itemKey = { itemID = id }, minPrice = 100 + i, totalQuantity = 5 }
    end
end

print("\nscan status on the auction house bar")

check("no status while nothing is scanning", Scanner:GetScanStatus() == nil)

Scanner:StartBrowseScan()
local s = Scanner:GetScanStatus()
check("a sweep waiting its turn says so", s and s.text:find("Waiting") and s.fraction == nil)

sendNext()
s = Scanner:GetScanStatus()
check("the first page is being asked for", s and s.text == "Scanning page 1" and s.fraction == 0)

for page = 1, 3 do
    addPage(page)
    Scanner:OnBrowseResults()
    sendNext()
end
s = Scanner:GetScanStatus()
check("after three pages it names the real count", s and s.text == "Scanning page 4 (3 read)")
check("and the bar has moved", s.fraction > 0 and s.fraction < 1)

addPage(4)
full = true
Scanner:OnBrowseResults()
check("a finished sweep leaves no status", Scanner:GetScanStatus() == nil)
check("and hands the UI how many prices it recorded", ui.result and ui.result.items == 200)

-- The quick scan: queued, then sent and waiting for the server to answer.
queue, ui.result = {}, nil
ns.db.lastReplicateRequest = nil
Scanner:StartFullScan()
s = Scanner:GetScanStatus()
check("a queued quick scan is waiting to start", s and s.text:find("Waiting") and s.fraction == nil)

sendNext()
s = Scanner:GetScanStatus()
check("a sent quick scan is asking, with nothing to measure yet",
    s and s.text:find("quick scan") and s.fraction == nil)

-- Reading the snapshot reports the worker's own progress.
Scanner.isReading = true
Scanner.worker = { IsRunning = function() return true end, GetProgress = function() return 0.42 end }
s = Scanner:GetScanStatus()
check("reading the quick scan shows the real share read",
    s and s.fraction == 0.42 and s.text == "Reading listings 42%")

-- Cancelling passes no result, so there is nothing to celebrate.
Scanner.worker = nil
Scanner.isReading = false
ui.result = "untouched"
Scanner:CancelScan()
check("a cancelled scan leaves no status", Scanner:GetScanStatus() == nil)
check("and gives the UI no result to celebrate", ui.result == nil)

print(("\n  scan status: %d checks passed"):format(checks))
