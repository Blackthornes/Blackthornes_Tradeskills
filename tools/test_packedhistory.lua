-- Price histories saved packed (a lighter save, 2026-11-26).
--
-- What must hold:
--   1. A packed history reads exactly as the table did: count, each
--      reading, liquidity, sales per day and the usual price.
--   2. Packing keeps every number: a missing value, a fraction, a big
--      price, readings out of order. One that would not read back the
--      same stays a table.
--   3. A new reading on a packed record unpacks it first and keeps the
--      newest MAX_HISTORY.
--   4. The logout pass packs every realm's items and suffixes, and the
--      packed form is much shorter than the table the game would write.

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
local events = {}
ns.RegisterEvent = function(_, event, fn) events[event] = fn end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local realm, other = "Forever-Alliance", "Forever-Horde"
local HOUR = 3600

local function Flat(n, start)
    local h = {}
    for i = 1, n do
        h[#h + 1] = (start or now) - (n - i + 1) * HOUR
        h[#h + 1] = 1000 + i * 10
        h[#h + 1] = 100 - i * 5
    end
    return h
end
local function Copy(t) local c = {} for i, v in ipairs(t) do c[i] = v end return c end

local main = Flat(12)
main[(4 - 1) * 3 + 2] = false
main[(7 - 1) * 3 + 3] = false

ns.db = {
    prices = {
        [realm] = {
            [2589] = { market = 1120, seen = now - HOUR, scans = 12, history = Copy(main),
                       suffixes = { [1490] = { market = 900, seen = now - HOUR, history = Flat(8) } } },
            [2592] = { market = 500, seen = now - HOUR, scans = 3, history = Flat(3) },
            [2593] = { market = 5, seen = now - HOUR, history = { { t = now - HOUR, m = 5, q = 1 } } },
        },
        [other] = { [774] = { market = 70, history = Flat(5) } },
    },
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
local prices = ns.db.prices[realm]
local record = prices[2589]

local liquidity = P:GetLiquidity(2589)
local sales = P:GetSalesPerDay(2589)
local usual = VF.UsualPrice(record)

print("\npacking keeps every number")
check("packs", P.PackRecord(record), true)
check("saved as one string", type(record.history), "string")
check("count from the string", P.HistoryCount(record.history), 12)
local same = 0
for i, t, m, q in P.EachReading(record.history) do
    local base = (i - 1) * 3
    local want = { main[base + 1], main[base + 2], main[base + 3] }
    for k = 1, 3 do if want[k] == false then want[k] = nil end end
    if t == want[1] and m == want[2] and q == want[3] then same = same + 1 end
end
check("every reading reads back the same", same, 12)
check("reading 4 has no price", select(2, P.HistoryReading(record.history, 4)), nil)
check("reading 7 has no count", select(3, P.HistoryReading(record.history, 7)), nil)
check("liquidity unchanged", P:GetLiquidity(2589), liquidity)
check("unpacked in place once read", type(record.history), "table")
P.PackRecord(record)
check("sales per day unchanged", P:GetSalesPerDay(2589), sales)
P.PackRecord(record)
check("usual price unchanged", VF.UsualPrice(record), usual)

local odd = { now, 12.5, 3, now - 50, 2 ^ 31 - 1, false, false, 0, -4 }
local text = P.PackHistory(odd)
local back = P.UnpackHistory(text)
local exact = #back == #odd
for i = 1, #odd do if back[i] ~= odd[i] then exact = false end end
check("fractions, big prices, out of order, false", exact, true)
check("an empty history packs empty", P.PackHistory({}), "")
check("and reads as no readings", P.HistoryCount(""), 0)
check("a string in a history is not packed", P.PackHistory({ now, "x", 1 }), nil)
local strange = { history = { now, "x", 1 } }
check("so the record keeps its table", P.PackRecord(strange), false)
check("untouched", strange.history[2], "x")

print("\na new reading on a packed record")
local small = prices[2592]
P.PackRecord(small)
P.AddReading(small, now, 520, 40)
check("four readings", P.HistoryCount(small.history), 4)
local lt, lm, lq = P.HistoryReading(small.history, 4)
check("the new one is last", lt == now and lm == 520 and lq == 40, true)
P.PackRecord(small)
for i = 1, 20 do P.AddReading(small, now + i, 600 + i, i) end
check("kept to MAX_HISTORY", P.HistoryCount(small.history), P.MAX_HISTORY)

print("\nthe logout pass")
check("packs at logout", type(events.PLAYER_LOGOUT), "nil")
P:OnEnable()
check("listens for logout", type(events.PLAYER_LOGOUT), "function")
events.PLAYER_LOGOUT()
check("item packed", type(prices[2592].history), "string")
check("suffix packed", type(record.suffixes[1490].history), "string")
check("an old layout packed too", type(prices[2593].history), "string")
check("another realm packed", type(ns.db.prices[other][774].history), "string")
check("suffix readings kept", P.HistoryCount(record.suffixes[1490].history), 8)

-- What the game would write for a 12-reading table, against the string.
local function Written(flat, depth)
    local tabs = string.rep("\t", depth)
    local out = { tabs .. '["history"] = {\n' }
    for i, v in ipairs(flat) do
        out[#out + 1] = ("%s\t%s, -- [%d]\n"):format(tabs, tostring(v), i)
    end
    out[#out + 1] = tabs .. "},\n"
    return table.concat(out)
end
local long = #Written(Flat(12), 4)
local short = #('\t\t\t\t["history"] = "' .. P.PackHistory(Flat(12)) .. '",\n')
check("under a third of the size", short * 3 < long, true)

time, C_Timer = oldTime, oldTimer

if failures > 0 then error(("%d packed price history check(s) failed"):format(failures)) end
print("\n  packed price history: all checks passed")
