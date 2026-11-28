-- A faster Snipe tab (the owner said build it, 2026-11-28).
--
-- What must hold:
--   1. At Start, deals the last full scan saw show at once, marked fromScan,
--      before any search; old records (before the scan) are left out.
--   2. Those items are searched first.
--   3. A live search that sees one clears the mark; one that is gone drops.
--   4. Likely deals (near the deal line, or listed a lot) come up every
--      pass; the rest every COLD_EVERY passes.
--   5. A search answered in two parts reads both, and does not shrink the
--      next search; one with no answer still shrinks it.
--   6. Progress counts items checked and guesses a pass's length from the
--      player's own passes.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Util = { HasFunction = function() return true end }
ns.Print = function() end
ns.Notice = { Show = function() end }
ns.RegisterEvent = function() return true end
ns.db = {}
local settings = { snipeCap = 100000000, snipePct = 70, snipeWatch = "priced", snipeSound = false }
ns.Config = { Get = function(_, k) return settings[k] end }

local timers = {}
local savedTimer, savedTime, savedFrame = C_Timer, GetTime, AuctionHouseFrame
local clock = 1000
GetTime = function() return clock end
C_Timer = { After = function(s, fn) timers[#timers + 1] = { at = clock + s, fn = fn } end }
AuctionHouseFrame = nil
local function Pass(seconds)
    local stop = clock + seconds
    while true do
        local soonest, idx
        for i, t in ipairs(timers) do
            if t.at <= stop and (not soonest or t.at < soonest) then soonest, idx = t.at, i end
        end
        if not idx then break end
        local t = table.remove(timers, idx)
        clock = math.max(clock, t.at)
        t.fn()
    end
    clock = stop
end

assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe.noReady = true   -- buying is walked in other suites

local G = 10000
local SCAN = 5000000
-- Item 1: last scan had one at 50g against 100g: a deal at once.
-- Item 2: a deal in an old record only (before the scan): not shown.
-- Item 3: listed far above the line, few up: cold.
-- Item 4: listed far above the line, but 60 up: hot.
-- Item 5: listed near the line: hot, no deal yet.
-- Items 6 to 9: cold, listed far above.
local worth, records = {}, {}
for id = 1, 9 do worth[id] = 100 * G end
records[1] = { rivalMin = 50 * G, quantity = 3, seen = SCAN }
records[2] = { rivalMin = 40 * G, quantity = 2, seen = SCAN - 2 * 3600 - 10 }
records[3] = { rivalMin = 99 * G, quantity = 2, seen = SCAN }
records[4] = { rivalMin = 99 * G, quantity = 60, seen = SCAN }
records[5] = { rivalMin = 80 * G, quantity = 4, seen = SCAN }
for id = 6, 9 do records[id] = { rivalMin = 98 * G, quantity = 2, seen = SCAN } end
ns.Prices = {
    GetTable = function() return worth end,
    GetValue = function(_, id) return worth[id] end,
    Get = function(_, id) return records[id] end,
    GetLastScan = function() return SCAN end,
}
C_Item = { GetItemInfoInstant = function() return nil end }

local requests = {}
ns.AHQueue = {
    BUDGET_MAX = 8, PRIORITY = { urgent = 10, scan = 90 },
    RecentSendCount = function() return 0 end,
    Request = function(_, r) requests[r.key] = r; return true end,
    Cancel = function(_, key) requests[key] = nil; return true end,
}
local asked, rows, full = {}, {}, true
C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id } end,
    SearchForItemKeys = function(keys)
        asked = {}
        for _, k in ipairs(keys) do asked[#asked + 1] = k.itemID end
    end,
    GetBrowseResults = function() return rows end,
    HasFullBrowseResults = function() return full end,
}
local function Has(list, id)
    for _, v in ipairs(list) do if v == id then return true end end
    return false
end
local function FindOf(id)
    for _, f in ipairs(Snipe:Finds()) do if f.itemID == id then return f end end
end

-- 1. Start: the scan's deal is there before any search.
Snipe:Start()
assert(Snipe:IsRunning())
local first = FindOf(1)
assert(first and first.fromScan and first.price == 50 * G, "the last scan's deal shows at once")
assert(not FindOf(2), "an old record is not a find")
assert(#Snipe:Finds() == 1)

-- 2. Searched first.
assert(requests.snipe and requests.snipe.send() == true)
assert(asked[1] == 1, "the scan's find is searched first")
-- 4. This pass holds the hot items, and only a share of the cold ones.
assert(Has(asked, 4) and Has(asked, 5), "likely deals come up")
local _, total = Snipe:Progress()
assert(total < 9, "not every cold item is in every pass, got " .. tostring(total))
local passOne = {}
for _, id in ipairs(asked) do passOne[id] = true end

-- 3 and 5. The answer comes in two parts. The first part alone is held.
local batchBefore = Snipe:BatchSize()
full = false
rows = { { itemKey = { itemID = 4 }, minPrice = 99 * G, totalQuantity = 60 } }
Snipe:OnBrowseResults()
assert(FindOf(1) and FindOf(1).fromScan, "the first part alone settles nothing")
-- The rest comes: item 1 is still there, cheaper.
rows[#rows + 1] = { itemKey = { itemID = 1 }, minPrice = 45 * G, totalQuantity = 2 }
full = true
Snipe:OnBrowseResults()
first = FindOf(1)
assert(first and not first.fromScan, "a live search clears the Last Scan mark")
assert(first.price == 45 * G, "and reads the second part's price")
assert(Snipe:BatchSize() >= batchBefore, "a split answer does not shrink the next search")
local checked = Snipe:Progress()
assert(checked == #asked, "progress counts the items checked")

-- A split answer that never finishes is read as it stands after a moment.
Pass(Snipe.REST + 0.1)
assert(requests.snipe.send() == true)
full = false
rows = {}
for _, id in ipairs(asked) do
    if id == 5 then rows[1] = { itemKey = { itemID = 5 }, minPrice = 60 * G, totalQuantity = 1 } end
end
Snipe:OnBrowseResults()
Pass(Snipe.PART_WAIT + 0.1)
if Has(asked, 5) then assert(FindOf(5), "the part that came is read after the wait") end
full = true

-- Walk to the end of the pass; the pass time is learned.
for _ = 1, 10 do
    Pass(Snipe.REST * 3 + 0.1)
    if requests.snipe and requests.snipe.send() then
        rows = {}
        for _, id in ipairs(asked) do rows[#rows + 1] = { itemKey = { itemID = id }, minPrice = 99 * G, totalQuantity = 2 } end
        Snipe:OnBrowseResults()
    end
end
assert(ns.db.snipePace and ns.db.snipePace > 0, "a pass's length is kept")
local _, _, seconds = Snipe:Progress()
assert(seconds and seconds > 0, "and a pass's length is guessed")
-- 3. Item 1 was gone in a whole answer: it drops.
assert(not FindOf(1), "a find gone in a live search drops")

-- 4. Over COLD_EVERY passes every cold item comes up at least once.
local seen = {}
for id in pairs(passOne) do seen[id] = true end
for _ = 1, 30 do
    Pass(Snipe.REST * 3 + 0.1)
    if requests.snipe and requests.snipe.send() then
        for _, id in ipairs(asked) do seen[id] = true end
        rows = {}
        for _, id in ipairs(asked) do rows[#rows + 1] = { itemKey = { itemID = id }, minPrice = 99 * G, totalQuantity = 2 } end
        Snipe:OnBrowseResults()
    end
end
for id = 3, 9 do assert(seen[id], "item " .. id .. " came up in time") end

-- 5. A search with no answer still asks about fewer next time.
Pass(Snipe.REST * 3 + 0.1)
assert(requests.snipe.send() == true)
local before = Snipe:BatchSize()
Snipe.batch = 30
before = Snipe:BatchSize()
requests.snipe.onGiveUp()
assert(Snipe:BatchSize() < before, "no answer: fewer next time")

Snipe:Stop()
C_Timer, GetTime, AuctionHouseFrame = savedTimer, savedTime, savedFrame
C_AuctionHouse, C_Item = nil, nil
ns.AHQueue = nil
print("test_snipefaster: ok")
