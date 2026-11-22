-- A quick full scan stopped before its answer came still gets read.
--
-- A player's report (2026-11-22): the quick full scan "almost never works,
-- always aborts halfway, doesn't save any prices but still triggers the 15
-- min cd". The game counts a quick scan when it is sent. Stopping one while
-- it waited for its answer (Cancel, or shutting the auction house, and the
-- auto scan sends one by itself on the way in) threw the answer away, so
-- the wait was spent for no prices. Shutting the auction house while the
-- rows were read kept only the ones read so far.
--
--  * A stopped scan's answer is read when it comes, quietly.
--  * An answer that comes with the auction house shut, and rows cut short
--    by shutting it, are read on the way back in, within five minutes.

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

local now = 100000
time = function() return now end
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

-- A worker that reads `stopAfter` rows and then waits, the way a read
-- spread over frames is still going when the auction house shuts.
local stopAfter
ns.Util.NewWorker = function(opts)
    local running = false
    local w = {}
    function w:IsRunning() return running end
    function w:Cancel()
        if not running then return end
        running = false
        if opts.onCancel then opts.onCancel() end
    end
    function w:Start(items)
        running = true
        for i, item in ipairs(items) do
            if stopAfter and i > stopAfter then return end
            opts.onItem(item)
        end
        running = false
        if opts.onDone then opts.onDone() end
    end
    return w
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


local function wipe() for k in pairs(priceTable) do priceTable[k] = nil end end
local function fresh()
    wipe()
    for i = #queue, 1, -1 do queue[i] = nil end
    for i = #printed, 1, -1 do printed[i] = nil end
    now = now + 3600
    ns.db.lastReplicateRequest = nil
    Scanner.replicateUnread, Scanner.stoppedWaiting, Scanner.awaitingReplicate = nil, nil, false
    Scanner.isAuctionHouseOpen = true
    stopAfter = nil
    replicateCount = 0
end

print("\na quick full scan stopped while it waited for its answer")

--------------------------------------------------------------------------------
-- Cancel, then the answer comes
--------------------------------------------------------------------------------

fresh()
Scanner:StartFullScan()
sendNext()
check("the quick scan was sent and the wait began", replicateSent == 1 and Scanner:GetSnapshotCooldown() ~= nil)
Scanner:CancelScan()
check("Cancel stops the scan", not Scanner.isScanning)

for i = #printed, 1, -1 do printed[i] = nil end
replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("its answer is still read", Prices:Get(SWORD) ~= nil and Prices:Get(AXE) ~= nil)
check("as a full scan", Prices:GetLastScan() == now)
check("without a word in chat", #printed == 0)
check("no page-by-page scan started", not Scanner.isBrowsing and not Scanner.browseQueued and #queue == 0)
check("and the scan is over", not Scanner.isScanning and not Scanner.isReading)

wipe()
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("a second answer nobody asked for is left alone", Prices:Get(SWORD) == nil)

-- A stopped scan that comes back empty starts nothing.
fresh()
Scanner:StartFullScan()
sendNext()
Scanner:CancelScan()
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("an empty answer to a stopped scan starts no page-by-page scan",
    not Scanner.isScanning and not Scanner.browseQueued and #queue == 0)

--------------------------------------------------------------------------------
-- The auction house shuts while it waits
--------------------------------------------------------------------------------

print("\nthe auction house shut before the answer came")

fresh()
Scanner:StartFullScan()
sendNext()
Scanner:AUCTION_HOUSE_CLOSED()
replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("nothing is read with the auction house shut", Prices:Get(SWORD) == nil and not Scanner.isReading)

now = now + 60
Scanner:AUCTION_HOUSE_SHOW()
check("opening it again reads the answer", Scanner:ReadWaitingSnapshot() == true)
check("every row", Prices:Get(SWORD) ~= nil and Prices:Get(AXE) ~= nil)
check("and it is not read twice", Scanner:ReadWaitingSnapshot() == false)

-- Back too late: the rows are old news.
fresh()
Scanner:StartFullScan()
sendNext()
Scanner:AUCTION_HOUSE_CLOSED()
replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
now = now + Scanner.REREAD_WITHIN + 1
Scanner:AUCTION_HOUSE_SHOW()
check("after five minutes the old rows are left alone",
    Scanner:ReadWaitingSnapshot() == false and Prices:Get(SWORD) == nil)

--------------------------------------------------------------------------------
-- The auction house shuts while the rows are read
--------------------------------------------------------------------------------

print("\nthe auction house shut while the rows were read")

fresh()
Scanner:StartFullScan()
sendNext()
replicateCount = #rows
stopAfter = 1
Scanner:REPLICATE_ITEM_LIST_UPDATE()
check("the read is under way", Scanner.isReading == true)
Scanner:AUCTION_HOUSE_CLOSED()
check("the row read so far is kept", Prices:Get(SWORD) ~= nil and Prices:Get(AXE) == nil)
check("it is not a full scan yet", Prices:GetLastScan() ~= now)

stopAfter = nil
now = now + 30
Scanner:AUCTION_HOUSE_SHOW()
check("opening it again reads the rest", Scanner:ReadWaitingSnapshot() == true and Prices:Get(AXE) ~= nil)
check("now it is a full scan", Prices:GetLastScan() == now)

-- The game no longer hands the rows out.
fresh()
Scanner:StartFullScan()
sendNext()
replicateCount = #rows
stopAfter = 1
Scanner:REPLICATE_ITEM_LIST_UPDATE()
Scanner:AUCTION_HOUSE_CLOSED()
stopAfter = nil
local lastScan = Prices:GetLastScan()
local keep = rows
rows = {}
now = now + 30
Scanner:AUCTION_HOUSE_SHOW()
Scanner:ReadWaitingSnapshot()
rows = keep
check("rows the game will not hand out again stamp no scan",
    Prices:GetLastScan() == lastScan and not Scanner.isScanning and not Scanner.isReading)

-- A scan read to its end leaves nothing to read again.
fresh()
Scanner:StartFullScan()
sendNext()
replicateCount = #rows
Scanner:REPLICATE_ITEM_LIST_UPDATE()
Scanner:AUCTION_HOUSE_CLOSED()
Scanner:AUCTION_HOUSE_SHOW()
check("a finished scan is not read again", Scanner:ReadWaitingSnapshot() == false)

print(("\n%d check(s) passed\n"):format(checks))
