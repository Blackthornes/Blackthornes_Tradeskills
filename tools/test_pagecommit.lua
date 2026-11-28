-- A finished page-by-page scan writes its prices a few items a frame.
--
-- When the last page landed, every item of the sweep was recorded in one
-- frame, and the game hitched as the scan finished. Scanner:
-- CommitBrowseResults now records a long sweep through the frame worker.
-- What must hold:
--   1. A short sweep is still recorded at once.
--   2. A long one: partway through, the scan still counts as running and
--      nothing has been told it finished.
--   3. At the end every price is there, the full scan is stamped, and the
--      finish is told once.
--   4. The prices are the very ones the all-at-once way writes.
--   5. Stopped partway, the rest is written at once.

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


-- A worker that runs only when stepped, as the frame worker does.
local workers = {}
ns.Util.NewWorker = function(opts)
    local worker = { index = 0, running = false }
    function worker:Start(items)
        self.items, self.index, self.running = items, 0, true
        workers[#workers + 1] = self
        return self
    end
    function worker:IsRunning() return self.running end
    function worker:GetProgress() return #self.items == 0 and 1 or self.index / #self.items end
    function worker:Step(count)
        while self.running and count > 0 and self.index < #self.items do
            self.index = self.index + 1
            opts.onItem(self.items[self.index], self.index, self)
            count = count - 1
        end
        if self.running and self.index >= #self.items then
            self.running = false
            if opts.onDone then opts.onDone(self) end
        end
    end
    function worker:Cancel()
        if not self.running then return end
        self.running = false
        if opts.onCancel then opts.onCancel(self) end
    end
    return worker
end

local finished = {}
ns.UI = { OnScanComplete = function(_, result) finished[#finished + 1] = result or false end }
local noted
ns.Posting = { NoteScanned = function(_, items, whole) noted = { items = items, whole = whole } end }


local function Sweep(count)
    local results = {}
    for i = 1, count do
        results[i] = { itemKey = { itemID = 50000 + i }, minPrice = 100 + i, totalQuantity = i }
    end
    return results
end

local function Begin(count, opts)
    workers, finished, noted = {}, {}, nil
    Scanner.isScanning, Scanner.isBrowsing = true, true
    Scanner.scanStartedWall = time()
    Scanner:CommitBrowseResults(Sweep(count), opts or { ended = true })
end

local function Count(table_)
    local n = 0
    for _ in pairs(table_) do n = n + 1 end
    return n
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
print("a short sweep, at once")

Begin(Scanner.COMMIT_AT_ONCE)
check("no pass of the worker is started", #workers == 0)
check("every item has a price", Count(Prices:GetTable()) == Scanner.COMMIT_AT_ONCE)
check("the scan is over and told once", Scanner.isScanning == false and #finished == 1)

print("")
print("a long sweep, a few items a frame")

local LONG = Scanner.COMMIT_AT_ONCE + 150
realm = "LongRealm-Alliance"
Begin(LONG)
check("one pass of the worker is started", #workers == 1 and workers[1]:IsRunning())
check("no price is written in that frame", Count(Prices:GetTable()) == 0)
check("the scan still counts as running", Scanner.isScanning == true and Scanner.isBrowsing == false)
check("nothing is told it finished yet", #finished == 0 and noted == nil)
check("no full scan is stamped yet", Prices:GetLastFullScan() == nil)

workers[1]:Step(40)
check("forty items are written after a step of forty", Count(Prices:GetTable()) == 40)
check("and it is still running", Scanner.isScanning == true and #finished == 0)

workers[1]:Step(LONG)
check("stepped to the end, every item has a price", Count(Prices:GetTable()) == LONG)
check("the scan is over", Scanner.isScanning == false and Scanner.committing == nil)
check("the full scan is stamped", Prices:GetLastFullScan() == time())
check("the finish is told once, with the count", #finished == 1 and finished[1].items == LONG)
check("every item is marked as just scanned", noted ~= nil and noted.items[50001] == true)

print("")
print("the same prices as all at once")

local stepped = priceTables[realm]
realm = "OnceRealm-Alliance"
local limit = Scanner.COMMIT_AT_ONCE
Scanner.COMMIT_AT_ONCE = LONG
Begin(LONG)
Scanner.COMMIT_AT_ONCE = limit
check("written at once", #workers == 0 and Count(Prices:GetTable()) == LONG)
local same = true
for itemID, record in pairs(priceTables[realm]) do
    local other = stepped[itemID]
    for _, field in ipairs({ "market", "min", "rivalMin", "ownMin", "quantity", "seen", "scans" }) do
        if not other or other[field] ~= record[field] then same = false end
    end
end
check("every item's price is the same both ways", same)

print("")
print("stopped partway")

realm = "StopRealm-Alliance"
Begin(LONG)
workers[1]:Step(10)
check("ten items written when it stops", Count(Prices:GetTable()) == 10)
Scanner:CancelScan()
check("the rest is written at once", Count(Prices:GetTable()) == LONG)
check("the finish is told once", #finished == 1 and finished[1].items == LONG)
check("the scan is over", Scanner.isScanning == false and Scanner.committing == nil)
workers[1]:Step(10)
check("the stopped pass writes nothing more", #finished == 1)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "page scan commit checks failed")
