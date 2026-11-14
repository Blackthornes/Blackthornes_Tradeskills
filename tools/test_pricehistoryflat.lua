-- Saved price history kept flat (memory review item 2, 2026-11-14).
--
-- What must hold:
--   1. A save from before, with { t =, m =, q = } readings, reads exactly as
--      it did: count, each reading, sales per day and the usual price.
--   2. Laying it out flat keeps every number, a missing price or count kept
--      as false and read back as nil.
--   3. A new reading on an old record lays it out first, then keeps only the
--      newest MAX_HISTORY readings.
--   4. The background pass lays out every old record, a batch a frame, and
--      leaves flat ones alone.

local now = 1790000000
local oldTime, oldTimer = time, C_Timer
time = function() return now end

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(("  FAIL  %-60s got %s, want %s"):format(label, tostring(got), tostring(want)))
    else
        print(("  ok    %-60s %s"):format(label, tostring(got)))
    end
end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    HasFunction = function() return false end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local realm = "Forever-Alliance"
local HOUR = 3600

-- An old save: twelve readings as tables, one with no price, one with no count.
local function OldHistory(n)
    local h = {}
    for i = 1, n do
        h[i] = { t = now - (n - i + 1) * HOUR, m = 1000 + i * 10, q = 100 - i * 5 }
    end
    return h
end
local old = OldHistory(12)
old[4].m = nil
old[7].q = nil

ns.db = {
    prices = { [realm] = {
        [2589] = { market = 1120, seen = old[12].t, scans = 12, history = old },
        [2592] = { market = 500, seen = now - HOUR, scans = 3, history = OldHistory(3) },
    } },
    favouritePrices = {}, myPrices = {}, characters = {},
}
ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return realm end,
    GetPriceTable = function() return ns.db.prices[realm] end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/VendorFlips.lua"))("Blackthornes_TS", ns)
local P, VF = ns.Prices, ns.VendorFlips
local record = ns.db.prices[realm][2589]

-- Copy every reading as the old layout says it.
local before = {}
for i, point in ipairs(old) do before[i] = { t = point.t, m = point.m, q = point.q } end

print("\nan old save reads as before")
check("count", P.HistoryCount(record.history), 12)
local t, m, q = P.HistoryReading(record.history, 4)
check("reading 4 time", t, before[4].t)
check("reading 4 has no price", m, nil)
check("reading 4 count", q, before[4].q)
local seen = 0
for i, rt, rm, rq in P.EachReading(record.history) do
    if rt == before[i].t and rm == before[i].m and rq == before[i].q then seen = seen + 1 end
end
check("every reading through EachReading", seen, 12)
local liquidityOld = P:GetLiquidity(2589)
local salesOld = P:GetSalesPerDay(2589)
local usualOld = VF.UsualPrice(record)
check("liquidity reads", liquidityOld ~= nil, true)
check("usual price reads", usualOld ~= nil, true)

print("\nlaid out flat, nothing lost")
check("flattening changes it", P.FlattenHistory(record), true)
check("flat holds three values a reading", #record.history, 36)
check("no tables left", type(record.history[1]), "number")
check("missing price kept as false", record.history[(4 - 1) * 3 + 2], false)
check("missing count kept as false", record.history[(7 - 1) * 3 + 3], false)
local same = 0
for i, rt, rm, rq in P.EachReading(record.history) do
    if rt == before[i].t and rm == before[i].m and rq == before[i].q then same = same + 1 end
end
check("every number reads back the same", same, 12)
check("liquidity unchanged", P:GetLiquidity(2589), liquidityOld)
check("sales per day unchanged", P:GetSalesPerDay(2589), salesOld)
check("usual price unchanged", VF.UsualPrice(record), usualOld)
check("flattening twice changes nothing", P.FlattenHistory(record), false)

print("\na new reading on an old record")
local small = ns.db.prices[realm][2592]
P.AddReading(small, now, 520, 40)
check("laid out flat first", type(small.history[1]), "number")
check("four readings now", P.HistoryCount(small.history), 4)
local lt, lm, lq = P.HistoryReading(small.history, 4)
check("the new one is last", lt == now and lm == 520 and lq == 40, true)
for i = 1, 20 do P.AddReading(small, now + i, 600 + i, i) end
check("kept to MAX_HISTORY", P.HistoryCount(small.history), P.MAX_HISTORY)
check("newest kept", select(2, P.HistoryReading(small.history, P.MAX_HISTORY)), 620)
local empty = { }
P.AddReading(empty, now, nil, 3)
check("a missing price on a new record reads nil", select(2, P.HistoryReading(empty.history, 1)), nil)

print("\nthe background pass")
local prices = ns.db.prices[realm]
for id = 10000, 10449 do prices[id] = { market = 1, history = OldHistory(2) } end
local queued = {}
C_Timer = { After = function(_, fn) queued[#queued + 1] = fn end }
local found = P:FlattenSoon()
check("finds only old records", found, 450)
check("waits after login", #queued, 1)
local steps = 0
while #queued > 0 do
    local fn = table.remove(queued, 1)
    fn()
    steps = steps + 1
end
check("spread over frames", steps, 3)
local left = 0
for id = 10000, 10449 do if type(prices[id].history[1]) == "table" then left = left + 1 end end
check("every old record laid out", left, 0)
check("nothing left to do", P:FlattenSoon(), 0)

time, C_Timer = oldTime, oldTimer

if failures > 0 then error(("%d flat price history check(s) failed"):format(failures)) end
print("\n  flat price history: all checks passed")
