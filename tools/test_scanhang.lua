-- The page-by-page scan that "stopped answering" at page 8, and the quick
-- full scan cooldown nobody had started.
--
-- Trent, 2026-09-26: "the quick full scan can be used again in 13m" when he
-- had not scanned in hours, then "the page-by-page scan stopped answering
-- after 15s (8 page(s) read)" with the progress bar stuck at 40%.
--
--  * The no-answer timer was armed once, on the first query, and never again.
--    Paging is paced at eight requests in fifteen seconds, so a healthy sweep
--    reached page 8 just as that one timer ran out.
--  * When it did run out it cleared the flags and nothing else: the pages read
--    were thrown away and the progress bar was never hidden.
--  * The quick scan's cooldown was stamped when the scan was queued, so one
--    that waited behind posting and gave up, or was cancelled by closing the
--    auction house, still started a fifteen minute wait.

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

print("\npage-by-page scan and the quick scan cooldown")

--------------------------------------------------------------------------------
-- A healthy sweep past page 8 is not declared dead
--------------------------------------------------------------------------------

Scanner:StartBrowseScan()
sendNext() -- the first query

for page = 1, 8 do
    addPage(page)
    Scanner:OnBrowseResults()
    sendNext() -- the next page is asked for when the budget allows
end

local waiting = live()
check("only one no-answer timer is running after 8 pages", #waiting == 1)
check("and it is the one for the page just asked for, not the first query",
    waiting[1] == timers[#timers])
check("the first query's timer was stopped when its page arrived", timers[1].cancelled == true)
check("the sweep is still going", Scanner.isBrowsing == true and #warnings == 0)

-- The sweep finishes normally.
addPage(9)
full = true
Scanner:OnBrowseResults()
check("a sweep that finishes clears the progress bar", ui.completes == 1 and not Scanner.isScanning)
check("and records all nine pages", Prices:Get(10901) ~= nil and Prices:Get(10101) ~= nil)
check("and leaves no timer behind", #live() == 0)

--------------------------------------------------------------------------------
-- A page that really never answers ends the scan cleanly
--------------------------------------------------------------------------------

for k in pairs(priceTable) do priceTable[k] = nil end
browseResults, full, timers, warnings, queue = {}, false, {}, {}, {}
ui.completes = 0

Scanner:StartBrowseScan()
sendNext()
for page = 1, 3 do
    addPage(page)
    Scanner:OnBrowseResults()
    sendNext()
end
check("the progress bar moved", ui.progress ~= nil)

fire(live()[1]) -- page 4 never comes

check("the scan says it stopped", #warnings == 1)
check("the scan is no longer running", not Scanner.isScanning and not Scanner.isBrowsing)
check("the progress bar is cleared and the Scan button given back", ui.completes == 1)
check("the pages that were read are kept", Prices:Get(10301) ~= nil and Prices:Get(10101) ~= nil)

--------------------------------------------------------------------------------
-- A sweep stopped at the 40 page limit is not a full scan
--------------------------------------------------------------------------------

-- Stamped as one, it hid the deals on the pages it never reached: they
-- looked older than the scan.
for k in pairs(priceTable) do priceTable[k] = nil end
browseResults, full, timers, warnings, queue, printed = {}, false, {}, {}, {}, {}
ui.completes = 0
ns.db.lastFullScanByRealm = nil
ns.db.lastFullScan = nil

Scanner:StartBrowseScan()
sendNext()
for page = 1, 40 do
    addPage(page)
    Scanner:OnBrowseResults()
    if page < 40 then sendNext() end
end

check("paging stops at the limit", not Scanner.isScanning and #queue == 0 and ui.completes == 1)
check("the pages read are kept", Prices:Get(14001) ~= nil)
check("it is not stamped as a full scan", Prices:GetLastFullScan() == nil)
local said = printed[#printed] or ""
check("chat says it stopped at the page limit", said:find("page limit", 1, true) ~= nil)
check("and not that the scan is complete", said:find("scan complete", 1, true) == nil)
check("but it is remembered, so the automatic scan does not repeat it at once",
    ns.db.lastCappedScanByRealm and ns.db.lastCappedScanByRealm.TestRealm ~= nil)
local lastScan, wasCapped = Prices:GetLastScan()
check("it counts as the last scan for the header and the deal lists",
    lastScan == ns.db.lastCappedScanByRealm.TestRealm and wasCapped == true)

-- One the game says is whole on its last page is still a full scan.
browseResults, full, queue, printed = {}, false, {}, {}
Scanner:StartBrowseScan()
sendNext()
addPage(1)
full = true
Scanner:OnBrowseResults()
check("a sweep that reaches the end is stamped", Prices:GetLastFullScan() ~= nil)

--------------------------------------------------------------------------------
-- The quick scan cooldown starts only when the scan is really sent
--------------------------------------------------------------------------------

queue, ui.completes = {}, 0
ns.db.lastReplicateRequest = nil

Scanner:StartFullScan()
check("queuing the quick scan does not start its cooldown", ns.db.lastReplicateRequest == nil)

giveUpNext() -- it waited behind posting and gave up
check("a quick scan that was never sent leaves no cooldown", Scanner:GetSnapshotCooldown() == nil)

Scanner:StartFullScan()
Scanner:CancelScan() -- the auction house was closed while it waited
check("a quick scan cancelled before sending leaves no cooldown", Scanner:GetSnapshotCooldown() == nil)

Scanner:StartFullScan()
sendNext()
check("a quick scan actually sent starts the cooldown",
    replicateSent == 1 and Scanner:GetSnapshotCooldown() ~= nil)

print(("\n%d scan hang checks passed"):format(checks))
