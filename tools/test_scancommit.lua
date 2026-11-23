-- A finished quick scan writes its prices a few items a frame.
--
-- Once every row was read, every item was summed up and recorded in one
-- frame, thousands at once, and the game froze for a moment as the scan
-- finished. Scanner:ReadReplicateResults now records them through a second
-- pass of the frame worker. What must hold:
--   1. Partway through, the scan still counts as reading, the bar is full,
--      and nothing has been told it finished.
--   2. At the end every price is there, the full scan is stamped, and the
--      finish is told once.
--   3. The prices are the very ones the all-at-once way writes.
--   4. Stopped partway (the auction house shut), the rest is written at
--      once and it is still a whole scan, with nothing left to read again.

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

local SNAPSHOT = {
    { 100, 10000, WOOL }, { 40, 4000, WOOL },
    { 5, 200, LINEN }, { 200, 8000, LINEN },
    { 20, 3000, BAR }, { 1, 5000, SWORD }, { 1, 7000, SWORD },
}

local function Begin(snapshot)
    rows = snapshot
    workers, finished, noted = {}, {}, nil
    Scanner.isScanning = true
    Scanner.scanStartedWall = time()
    Scanner:ReadReplicateResults(#rows)
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
print("a few items a frame")

Begin(SNAPSHOT)
check("the read starts one pass of the worker", #workers == 1)
workers[1]:Step(#SNAPSHOT)
check("every row read, no price is written in that frame", Count(Prices:GetTable()) == 0)
check("a second pass was started to write them", #workers == 2 and workers[2]:IsRunning())
check("the scan still counts as reading", Scanner.isReading == true and Scanner.isScanning == true)
check("the bar stays full", Scanner:GetProgress() == 1)
check("nothing is told it finished yet", #finished == 0)

workers[2]:Step(2)
check("two items are written after one step of two", Count(Prices:GetTable()) == 2)
check("and it is still reading", Scanner.isReading == true and #finished == 0)
check("no full scan is stamped yet", Prices:GetLastFullScan() == nil)

workers[2]:Step(10)
check("stepped to the end, all four items have a price", Count(Prices:GetTable()) == 4)
check("the scan is over", Scanner.isReading == false and Scanner.isScanning == false)
check("the full scan is stamped", Prices:GetLastFullScan() == time())
check("the finish is told once, with the count", #finished == 1 and finished[1].items == 4)
check("every item is marked as just scanned", noted ~= nil and noted.whole == true and noted.items[WOOL] ~= nil)
check("the bar is let go", Scanner:GetProgress() == nil)
check("a commodity is marked as priced by its row", Prices:Get(WOOL).rowPriceFixed == true)

print("")
print("the same prices as all at once")

local stepped = priceTables[realm]
realm = "OtherRealm-Alliance"
ns.db.commodity = {}
-- Hidden from the scanner, so it takes the all-at-once way (KeepRead), and
-- handed back only while CommitScan runs, which needs it.
local commitOne, commitScan = Prices.CommitOne, Prices.CommitScan
Prices.CommitOne = nil
Prices.CommitScan = function(self, ...)
    self.CommitOne = commitOne
    local recorded = commitScan(self, ...)
    self.CommitOne = nil
    return recorded
end
Begin(SNAPSHOT)
workers[1]:Step(#SNAPSHOT)
Prices.CommitOne, Prices.CommitScan = commitOne, commitScan
check("without the second pass it is written at once", #workers == 1 and Count(Prices:GetTable()) == 4)

local atOnce = priceTables[realm]
local same = true
for itemID, record in pairs(atOnce) do
    local other = stepped[itemID]
    for _, field in ipairs({ "market", "min", "rivalMin", "ownMin", "quantity", "seen", "scans", "rowPriceFixed" }) do
        if not other or other[field] ~= record[field] then
            same = false
            print(("    %s differs for %d: %s and %s"):format(field, itemID,
                tostring(other and other[field]), tostring(record[field])))
        end
    end
    local ladderA, ladderB = record.ladder or {}, other and other.ladder or {}
    if table.concat(ladderA, ",") ~= table.concat(ladderB, ",") then same = false end
end
check("every item's price is the same both ways", same)

print("")
print("the auction house shuts partway")

realm = "ThirdRealm-Alliance"
ns.db.commodity = {}
Begin(SNAPSHOT)
workers[1]:Step(#SNAPSHOT)
workers[2]:Step(1)
check("one item written when it shuts", Count(Prices:GetTable()) == 1)
Scanner.isAuctionHouseOpen = true
Scanner:AUCTION_HOUSE_CLOSED()
check("the rest is written at once", Count(Prices:GetTable()) == 4)
check("it is still a whole scan", Prices:GetLastFullScan() == time() and #finished == 1 and finished[1].items == 4)
check("the scan is over", Scanner.isReading == false and Scanner.isScanning == false)
check("nothing is left to read on the next visit", Scanner.replicateUnread == nil)
workers[2]:Step(10)
check("the stopped pass writes nothing more", #finished == 1)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "scan commit checks failed")
