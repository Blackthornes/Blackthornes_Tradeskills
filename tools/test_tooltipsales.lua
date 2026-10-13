-- The sales lines under Demand on an item's tooltip (asked 2026-10-13).
--
--   1. Each day's drops in stock are kept for seven days; looks closer than
--      the sales gap count once, an empty book counts nothing, and a drop
--      across more than a day lands on no day.
--   2. Sold a day is listings gone per day from the kept readings.
--   3. You sold counts only this week's sales and expiries.
--   4. The lines show always, or only with Shift when that is ticked, and
--      Demand then leaves the share of stock to them.

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

local DAY, HOUR = 86400, 3600
local NOW = 20000 * DAY + 20 * HOUR
local realTime = time
time = function() return NOW end

--------------------------------------------------------------------------------
print("\nthe days")
--------------------------------------------------------------------------------

local Prices
do
  local priceNs = {
    NewModule = function() Prices = {}; return Prices end,
    Util = { Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end },
    RegisterCommand = function() end,
  }
  assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", priceNs)
end

local table_ = {}
Prices.GetTable = function() return table_ end

local record = {}
table_[1] = record
local start = math.floor(NOW / DAY) * DAY - 6 * DAY + HOUR

Prices.NoteDaily(record, start, 50)
Prices.NoteDaily(record, start + 5 * 60, 40)         -- too close: counts once
Prices.NoteDaily(record, start + 2 * HOUR, 30)       -- 20 gone since the first
Prices.NoteDaily(record, start + 3 * HOUR, 0)        -- empty: nothing counted
Prices.NoteDaily(record, start + 4 * HOUR, 25)       -- 5 more
Prices.NoteDaily(record, start + DAY + HOUR, 60)     -- restocked: nothing
Prices.NoteDaily(record, start + 4 * DAY, 40)        -- three days later: no day
Prices.NoteDaily(record, NOW - 5 * HOUR, 40)
Prices.NoteDaily(record, NOW - HOUR, 30)             -- today: 10

local days = Prices:GetDailySales(1)
check("seven days", #days, 7)
check("the first day's drops", days[1], 25)
check("a restock is no sale", days[2], 0)
check("a day nothing scanned it", days[3], false)
check("a drop over days lands on none", days[5], 0)
check("today last", days[7], 10)

Prices.NoteDaily(record, NOW + 2 * DAY, 30)
local trimmed = 0
for i = 1, #record.daily.days, 2 do
  if record.daily.days[i] < math.floor((NOW + 2 * DAY) / DAY) - 6 then trimmed = trimmed + 1 end
end
check("older than a week is dropped", trimmed, 0)
check("an item with no record says nothing", Prices:GetDailySales(2), nil)

record.history = {
  { t = NOW - 2 * DAY, q = 100 },
  { t = NOW - DAY, q = 60 },
  { t = NOW, q = 80 },
}
check("about 20 a day gone", Prices:GetUnitsSoldPerDay(1), 20)
check("the share is the same reading", math.floor(Prices:GetSalesPerDay(1) * 100 + 0.5), 25)

--------------------------------------------------------------------------------
print("\nyour week")
--------------------------------------------------------------------------------

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end
local entries = {
  { t = NOW - 8 * DAY, kind = "sold", itemID = 1, quantity = 9 },
  { t = NOW - 2 * DAY, kind = "sold", itemID = 1, quantity = 5 },
  { t = NOW - DAY, kind = "sold", name = "Bolt", quantity = 7 },
  { t = NOW - DAY, kind = "expired", itemID = 1 },
  { t = NOW - DAY, kind = "removed", itemID = 1 },
}
ns.Mail = {
  GetLedger = function() return { entries = entries } end,
  GetItems = function() return {} end,
  NameIndex = function() return { Bolt = 1 } end,
}
assert(loadfile(lfs_cwd .. "/Logic/Demand.lua"))("Blackthornes_TS", ns)

local week = ns.Demand:Week(1)
check("units sold this week, by id or name", week and week.sold, 12)
check("expiries this week; cancels left out", week and week.expired, 1)
check("an item not sold says nothing", ns.Demand:Week(2), nil)

--------------------------------------------------------------------------------
print("\nthe tooltip")
--------------------------------------------------------------------------------

local shift = false
IsShiftKeyDown = function() return shift end
local settings = {}
ns.Config = { Get = function(_, key) return settings[key] end }
ns.Util = {
  FormatMoney = function(c) return ("<%d>"):format(c) end,
  FormatAgeAgo = function(s) return ("%d hours ago"):format(s / 3600) end,
}
ns.Prices = {
  Get = function(_, id) return id == 1 and { quantity = 58, seen = NOW - 2 * HOUR } or nil end,
  GetAge = function() return 2 * HOUR end,
  GetUnitsSoldPerDay = function() return 34.4 end,
  GetDailySales = function() return { 22, 25, 19, 28, 31, 30, 37 } end,
}
ns.Demand.Get = function() return { level = "high", source = "market", rate = 1 } end

local ItemTooltip
do
  local realNew = ns.NewModule
  ns.NewModule = function(name) local m = realNew(name); ItemTooltip = m; return m end
  assert(loadfile(lfs_cwd .. "/UI/ItemTooltip.lua"))("Blackthornes_TS", ns)
  ns.NewModule = realNew
end

local lines = {}
ItemTooltip:AddDemandLines(lines, 1)
check("demand and four lines", #lines, 5)
check("demand leaves the share to them", lines[1][2], "High")
check("sold a day", lines[2][2], "about 34 (from your scans)")
check("listed now with its age", lines[3][2], "58  (scanned 2 hours ago)")
check("seven bars", select(2, lines[4][2]:gsub("|T", "")), 7)
check("rising", lines[4][2]:match("up %d+%%$") ~= nil, true)
check("in green", lines[4].color, "profit")
check("you sold", lines[5][2], "12 this week, 1 expired")
check("indented under Demand", lines[2][1], "   Sold a day")

settings.tooltipSalesShift = true
lines = {}
ItemTooltip:AddDemandLines(lines, 1)
check("with Shift ticked and not held: demand only", #lines, 1)
check("saying the share again", lines[1][2], "High (100% of its stock sells a day)")
shift = true
lines = {}
ItemTooltip:AddDemandLines(lines, 1)
check("held: all of them", #lines, 5)
settings.tooltipSalesShift = nil

check("too few days for a trend", ItemTooltip.Trend({ false, false, false, 4, 5, 6, 1 }), nil)
check("level is steady", ItemTooltip.Trend({ 10, 10, 10, 10, 10, 10, 1 }), 0)
check("a day not scanned is a flat mark", ItemTooltip.Bars({ false, 1 }):match("^|T[^:]+:1:") ~= nil, true)

time = realTime
if failures > 0 then error(("%d check(s) failed"):format(failures)) end
print("\ntest_tooltipsales: ok")
