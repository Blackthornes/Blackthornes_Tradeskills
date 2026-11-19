-- A quick full scan that stops partway keeps what it read.
--
-- The game hands over the whole snapshot at once, and Tradeskills reads it a
-- few hundred rows a frame. Closing the auction house (or Cancel) while it
-- read threw every row already read away, and the quick scan cannot be asked
-- for again for fifteen minutes. The page by page scan already kept its part.
--
-- A part is not the whole, though: nothing it did not reach is marked sold
-- out, it is not stamped as a full scan, its counts stay out of Sold a Day,
-- and posting still searches first rather than trust a half read book.

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

local IRON, COPPER, SILVER, OLD = 2772, 2770, 2775, 4444
local stackSizes = { [IRON] = 20, [COPPER] = 20, [SILVER] = 20, [OLD] = 20 }
C_Item = {
    GetItemInfo = function(itemID)
        local stack = stackSizes[itemID]
        if not stack then return nil end
        return "item", "link", 1, 1, 1, "Trade Goods", "Metal", stack
    end,
}

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
local said = {}
ns.Print = function(msg) said[#said + 1] = tostring(msg) end
ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop

local priceTable = {}
ns.db = { commodity = { [IRON] = true, [COPPER] = true, [SILVER] = true, [OLD] = true } }
ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return "TestRealm-Alliance" end,
    GetPriceTable = function() return priceTable end,
}

local noted
ns.Posting = { NoteScanned = function(_, items, whole) noted = { items = items, whole = whole } end }
local completed
ns.UI = { OnScanComplete = function(_, info) completed = info or {} end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)

local Prices, Scanner = ns.Prices, ns.Scanner

-- A worker that reads `stopAfter` rows, then is cancelled the way closing
-- the auction house cancels it (Scanner:CancelScan).
local stopAfter
ns.Util.NewWorker = function(opts)
    local running = false
    local w = {}
    function w:IsRunning() return running end
    function w:Cancel()
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

-- A price from an earlier scan, for an item the stopped scan never reaches.
Prices:Record(OLD, 500, 500, 30, 90000)
Prices:Record(SILVER, 900, 900, 12, 90000)

rows = {
    { 10, 1000, IRON },    -- 1s each
    { 20, 1600, COPPER },  -- 80c each
    { 5, 4000, SILVER },   -- never read: the scan stops before it
}

print("")
print("a quick scan stopped after two of three rows")

stopAfter = 2
Scanner.isScanning = true
Scanner.scanStartedAt = 990
Scanner.scanStartedWall = time()
Scanner:ReadReplicateResults(#rows)
Scanner:CancelScan()

check("the rows it read are kept", Prices:Get(IRON) and Prices:Get(IRON).min == 100)
check("both of them", Prices:Get(COPPER) and Prices:Get(COPPER).min == 80)
check("an item it never reached keeps its old price", Prices:Get(SILVER).min == 900)
check("nothing it did not reach is marked sold out",
    (Prices:Get(OLD).quantity or 0) == 30 and (Prices:Get(SILVER).quantity or 0) == 12)
check("it is not stamped as a full scan",
    not (ns.db.lastFullScanByRealm and ns.db.lastFullScanByRealm["TestRealm-Alliance"]))
check("posting is not told the whole house was read", not (noted and noted.whole))
check("posting is not told to trust the half read prices", noted == nil)
check("the scan is over", not Scanner.isScanning and not Scanner.isReading)
check("the window hears how many were kept", completed and completed.items == 2)
local saidKept = false
for _, line in ipairs(said) do
    if line:find("2") and line:find("stopped") then saidKept = true end
end
check("chat says it stopped and how many it kept", saidKept)

print("")
print("a quick scan read to its end is unchanged")

stopAfter = nil
noted, completed = nil, nil
Scanner.isScanning = true
Scanner:ReadReplicateResults(#rows)
check("it is stamped as a full scan", ns.db.lastFullScanByRealm["TestRealm-Alliance"] == time())
check("posting is told the whole house was read", noted and noted.whole == true)
check("the third row is read too", Prices:Get(SILVER).min == 800)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "stopped quick scan checks failed")
