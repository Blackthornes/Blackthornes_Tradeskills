-- Telling other addons a scan finished (Farmer's top farm alert, 2026-10-14).
--
-- What must hold:
--   1. A watcher hears a finished scan that recorded prices, with the count.
--   2. A cancelled scan, or one that recorded nothing, says nothing.
--   3. A watcher that raises never stops the others.
--   4. The same function twice is one watcher; a non-function is refused.

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
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Config = {
    Get = function() return nil end,
    GetPriceTable = function() return {} end,
}
ns.db = {}
time = time or os.time

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
local Prices = ns.Prices

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nscan watchers")

local heard = {}
local function Listen(info) heard[#heard + 1] = info end

check("a function is watched", Prices:WatchScans(Listen) == true)
check("the same function twice is one watcher", Prices:WatchScans(Listen) == true and #Prices.scanWatchers == 1)
check("a non-function is refused", Prices:WatchScans("nope") == false and #Prices.scanWatchers == 1)

Prices:ScanFinished(nil)
check("a cancelled scan says nothing", #heard == 0)
Prices:ScanFinished({ items = 0 })
check("a scan that recorded nothing says nothing", #heard == 0)

Prices:ScanFinished({ items = 412, soldOut = 3 })
check("a finished scan is heard", #heard == 1)
check("with how many it recorded", heard[1].items == 412 and type(heard[1].at) == "number")
check("and the count of scans moves", Prices.scanCount == 1)

local after = 0
Prices.scanWatchers = {}
Prices:WatchScans(function() error("boom") end)
Prices:WatchScans(function() after = after + 1 end)
Prices:ScanFinished({ items = 5 })
check("a watcher that raises never stops the others", after == 1)

print(("\n%d check(s) passed\n"):format(checks))
