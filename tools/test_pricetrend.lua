-- The price trend (asked 2026-10-14): the Prices tab's TREND column and the
-- tooltip line.
--
--   1. Each record keeps one market value a day, the last scan's, for
--      fourteen days; an old save with no trend reads as none.
--   2. The trend is the market value now against its average over the last
--      7 or 14 days, and says nothing until three days were scanned.
--   3. It reads "+24%" in green, "-12%" in red, "0%" plain.
--   4. The tooltip line follows the picked days and can be turned off.

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

local settings = {}
local Prices
do
  local priceNs = {
    NewModule = function() Prices = {}; return Prices end,
    Util = { Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end },
    RegisterCommand = function() end,
    Config = { Get = function(_, key) return settings[key] end },
  }
  assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", priceNs)
end

local table_ = {}
Prices.GetTable = function() return table_ end

--------------------------------------------------------------------------------
print("\none value a day")
--------------------------------------------------------------------------------

local record = {}
table_[1] = record
local today = math.floor(NOW / DAY)

-- Twenty days at 100, so the oldest drop off.
for day = 19, 1, -1 do
  record.market = 100
  Prices.NoteTrend(record, NOW - day * DAY)
end
check("fourteen days kept", #record.trend, 28)
check("the oldest kept is thirteen days back", record.trend[1], today - 14)

record.market = 90
Prices.NoteTrend(record, NOW - 2 * HOUR)
record.market = 124
Prices.NoteTrend(record, NOW - HOUR)
check("two scans today keep one day", #record.trend, 28)
check("the later scan stands for the day", record.trend[28], 124)

Prices.NoteTrend(record, NOW - 30 * DAY)
check("an older scan is not written out of order", #record.trend, 28)

--------------------------------------------------------------------------------
print("\nthe trend")
--------------------------------------------------------------------------------

-- 6 days at 100 and today at 124: average 103.4, now 124.
local trend, count = Prices:GetTrend(1, 7)
check("days counted over 7 days", count, 7)
check("about 20% up over 7 days", math.floor(trend * 100 + 0.5), 20)
trend = Prices:GetTrend(1, 14)
check("about 22% up over 14 days", math.floor(trend * 100 + 0.5), 22)
check("7 days unless 14 is picked", Prices:TrendDays(), 7)
settings.priceTrendDays = 14
check("14 when picked", Prices:TrendDays(), 14)
settings.priceTrendDays = 9
check("anything else is 7", Prices:TrendDays(), 7)

table_[2] = { market = 50, trend = { today - 1, 40, today, 50 } }
check("two days say nothing yet", Prices:GetTrend(2, 7), nil)
table_[3] = { market = 50, history = {} }
check("an old save with no trend says nothing", Prices:GetTrend(3, 7), nil)
check("an item never scanned says nothing", Prices:GetTrend(4, 7), nil)
table_[5] = { market = 50, trend = "unreadable" }
check("a trend it cannot read says nothing", Prices:GetTrend(5, 7), nil)

check("up is green", select(2, Prices.TrendText(0.24)), "profit")
check("up reads with a plus", Prices.TrendText(0.24), "+24%")
check("down is red", select(2, Prices.TrendText(-0.12)), "loss")
check("down reads with a minus", Prices.TrendText(-0.12), "-12%")
check("under half a percent is level", Prices.TrendText(0.004), "0%")
check("no trend, no text", Prices.TrendText(nil), nil)


--------------------------------------------------------------------------------
print("\nthe tooltip")
--------------------------------------------------------------------------------

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.Config = { Get = function(_, key) return settings[key] end }
ns.Util = { FormatMoney = function(c) return tostring(c) end }
ns.Prices = Prices

local ItemTooltip
do
  ns.NewModule = function(name) local m = {}; ns[name] = m; ItemTooltip = m; return m end
  assert(loadfile(lfs_cwd .. "/UI/ItemTooltip.lua"))("Blackthornes_TS", ns)
end

settings.priceTrendDays = 7
local line = ItemTooltip:TrendLine(1)
check("the line names the days", line and line[1], "Trend (7 days)")
check("and the trend", line and line[2], "+20%")
check("in green", line and line.color, "profit")
settings.priceTrendDays = 14
line = ItemTooltip:TrendLine(1)
check("14 days when picked", line and line[1], "Trend (14 days)")
check("no line until days are scanned", ItemTooltip:TrendLine(2), nil)
settings.tooltipTrend = false
check("no line when turned off", ItemTooltip:TrendLine(1), nil)

time = realTime
if failures > 0 then error(("%d check(s) failed"):format(failures)) end
print("\ntest_pricetrend: ok")
