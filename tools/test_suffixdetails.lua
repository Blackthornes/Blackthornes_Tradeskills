-- A suffix row picked on the Prices tab shows that suffix's graph and Stats
-- (a player's report, 2026-11-21): once suffix rows showed, picking
-- "Cabalist Chestpiece of Arcane Wrath" still drew the plain item's graph,
-- and Stats opened on the plain item.
--
-- What must hold:
--   1. Each suffix reading is kept beside the suffix: a short line of its own
--      market values, and an hour by hour line when the item is kept.
--   2. The item's own lines are untouched by its suffixes, and one suffix's by
--      another's.
--   3. The graph draws the suffix picked: hourly when kept, else its own
--      readings, never the item's.
--   4. Stats builds for the suffix: its worth, its readings, its graph, its
--      own key; what only the item knows (sales) stays the item's.
--   5. Details and Stats hand the suffix on, and a pick from Stats' own list
--      shows the plain item again.
--   6. Old saves with no suffix lines read and prune as before.

time = time or os.time
date = date or os.date

local DAY, HOUR = 86400, 3600
local now = 1790000000
local clock = now
time = function() return clock end

local passed, failed = 0, 0
local function check(label, got, want)
    if got == want then
        passed = passed + 1
        print(("  ok    %-62s %s"):format(label, tostring(got)))
    else
        failed = failed + 1
        print(("  FAIL  %-62s got %s, want %s"):format(label, tostring(got), tostring(want)))
    end
end

local realm = "Forever-Alliance"
local CHEST, PLAIN = 7527, 9999
local WRATH, BEAR = 1890, 14322

local ns = {}
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    HasFunction = function() return false end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    Comma = function(n) return tostring(n) end,
}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.commands = {}
ns.RegisterCommand = function(name, _, fn) ns.commands[name] = fn end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.db = {
    prices = {},
    favouritePrices = { [CHEST] = "Cabalist Chestpiece" },
    characters = {},
}
ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return realm end,
    GetPriceTable = function()
        ns.db.prices[realm] = ns.db.prices[realm] or {}
        return ns.db.prices[realm]
    end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/PriceHistory.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/StatsLog.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/ItemStats.lua"))("Blackthornes_TS", ns)
ns.Theme, ns.Widgets = {}, {}
assert(loadfile(lfs_cwd .. "/UI/PriceGraph.lua"))("Blackthornes_TS", ns)

local P, H, G = ns.Prices, ns.PriceHistory, ns.PriceGraph

print("suffix readings are kept")
-- The plain item's price, then three hours of scans with two suffixes.
P:Record(CHEST, 12000, 11000, 10, now - 3 * HOUR)
local wrathPrices, bearPrices = { 90000, 92000, 95000 }, { 30000, 31000, 29000 }
for i = 1, 3 do
    local at = now - (4 - i) * HOUR
    P:RecordSuffix(CHEST, WRATH, wrathPrices[i], wrathPrices[i] - 1000, wrathPrices[i] - 1000, i, at)
    P:RecordSuffix(CHEST, BEAR, bearPrices[i], bearPrices[i], bearPrices[i], 2, at)
end

local wrath = P:GetSuffixEntry(CHEST, WRATH)
check("a suffix keeps its own readings", P.HistoryCount(wrath and wrath.history), 3)
check("the item's readings are its own", P.HistoryCount(P:Get(CHEST).history), 1)

local points = H:GetPoints(CHEST, nil, now, WRATH)
check("a kept item's suffix has hourly prices", #points, 3)
check("its cheapest each hour", points[3] and points[3].p, 94000)
check("another suffix has its own", (H:GetPoints(CHEST, nil, now, BEAR)[1] or {}).p, 30000)
check("the item's hourly line is untouched", #H:GetPoints(CHEST, nil, now), 1)
check("so is the item's price", (H:GetPoints(CHEST, nil, now)[1] or {}).p, 11000)
local listed = H:GetListed(CHEST, nil, now, WRATH)
check("and how many were listed", listed[3] and listed[3].q, 3)

print("the graph draws the suffix")
local series, kind = G.Series(CHEST, "day", now, WRATH)
check("hourly for a kept item", kind, "hourly")
check("with the suffix's prices", series[1] and series[1].p, 89000)
local plain = G.Series(CHEST, "day", now)
check("the item alone still draws the item", plain[1] and plain[1].p, 11000)

-- An item nobody keeps: the suffix's own readings, not the item's.
P:Record(PLAIN, 500, 400, 4, now - 3 * HOUR)
P:Record(PLAIN, 520, 410, 4, now - 2 * HOUR)
for i = 1, 3 do P:RecordSuffix(PLAIN, BEAR, 7000 + i, 7000, 7000, 1, now - (4 - i) * HOUR) end
check("nothing hourly is kept for it", #H:GetPoints(PLAIN, nil, now, BEAR), 0)
series, kind = G.Series(PLAIN, "day", now, BEAR)
check("it falls back to the suffix's readings", kind, "market")
check("which are the suffix's prices", series[1] and series[1].p, 7001)

print("Stats builds for the suffix")
local stats = ns.ItemStats:Build(CHEST, now, WRATH)
check("it knows the suffix", stats.suffix, WRATH)
check("its worth is the suffix's", stats.worth, wrath.market)
check("its readings are the suffix's", #stats.stock, 3)
check("its last reading's count", stats.stock[3] and stats.stock[3].q, 3)
local item = ns.ItemStats:Build(CHEST, now)
check("the item alone is worth the item's", item.worth, P:GetValue(CHEST, "market"))
check("and has no suffix", item.suffix, nil)
check("each suffix has its own key",
    ns.ItemStats:Key(CHEST, WRATH) ~= ns.ItemStats:Key(CHEST, BEAR)
    and ns.ItemStats:Key(CHEST, WRATH) ~= ns.ItemStats:Key(CHEST), true)

print("handing the suffix on")
ns.UI = { RegisterTab = function() end }
ns.Prices.GetFavourites = function() return ns.db.favouritePrices end
assert(loadfile(lfs_cwd .. "/UI/Tab_Stats.lua"))("Blackthornes_TS", ns)
ns.StatsUI:Pick(CHEST, WRATH)
local picked, suffix = ns.UI._StatsPicked()
check("Stats picks the item", picked, CHEST)
check("and the suffix", suffix, WRATH)
ns.StatsUI:Pick(CHEST, BEAR)
picked, suffix = ns.UI._StatsPicked()
check("another suffix of the same item moves it", suffix, BEAR)
ns.StatsUI:Pick(CHEST)
picked, suffix = ns.UI._StatsPicked()
check("the plain item clears the suffix", suffix, nil)

assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Tab_Prices.lua"))("Blackthornes_TS", ns)
local id, kidSuffix = ns.PricesUI.Subject({ itemID = CHEST, kid = true, suffix = WRATH })
check("Details hands on a suffix row's item", id, CHEST)
check("and its suffix", kidSuffix, WRATH)
id, kidSuffix = ns.PricesUI.Subject({ itemID = CHEST })
check("an item row hands on no suffix", kidSuffix, nil)

print("upkeep")
for i = 1, 20 do P:RecordSuffix(PLAIN, BEAR, 7000, 7000, 7000, 1, now + i * HOUR) end
check("a suffix keeps only its newest readings",
    P.HistoryCount(P:GetSuffixEntry(PLAIN, BEAR).history), P.SUFFIX_READINGS)
clock = now + 15 * DAY
H:Prune(clock)
check("old suffix prices are let go", ns.db.suffixHistory[realm][CHEST], nil)
ns.db.suffixHistory, ns.db.suffixListed = nil, nil
check("an old save reads as no suffix points", #H:GetPoints(CHEST, nil, clock, WRATH), 0)
H:Prune(clock)
check("and is not given a table by pruning", ns.db.suffixHistory, nil)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d suffix details check(s) failed"):format(failed)) end
