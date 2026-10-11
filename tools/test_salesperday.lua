-- Prices:GetSalesPerDay: the share of an item's stock that sells per day,
-- the same however often it was scanned (what Demand reads).
--
--   1. The same sales read the same scanned every minute or every few hours.
--   2. Scans a few minutes apart count once, so no dilution.
--   3. Under an hour of readings has no answer.
--   4. An empty answer is not a sell-out.

time = time or os.time

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = {
  Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
  Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
  FormatMoney = tostring, FormatAge = function() return "" end,
  HasFunction = function() return false end,
}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = function() end, function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local table_ = {}
ns.db = {}
ns.Config = {
  Get = function() return nil end,
  GetRealmKey = function() return "R" end,
  GetPriceTable = function() return table_ end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
local Prices = ns.Prices

local failures = 0
local function check(label, got, want)
  local ok = got == want
  if type(got) == "number" and type(want) == "number" then ok = math.abs(got - want) < 0.005 end
  if not ok then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

-- Stock falls from 100 to 80 over 4 hours, in a straight line.
local function Series(step)
  local h = {}
  for t = 0, 4 * 3600, step do
    h[#h + 1] = { t = t, q = 100 - 20 * t / (4 * 3600) }
  end
  while #h > 12 do table.remove(h, 1) end
  return h
end

print("\nthe same sales, however often it is scanned")
table_[1] = { history = Series(3600) }
local hourly = Prices:GetSalesPerDay(1)
check("20 of ~90 over 4 hours is over a day's worth", hourly ~= nil and hourly > 0.9, true)

table_[2] = { history = {} }
for t = 0, 4 * 3600, 900 do table_[2].history[#table_[2].history + 1] = { t = t, q = 100 - 20 * t / (4 * 3600) } end
check("every quarter hour reads the same", Prices:GetSalesPerDay(2), hourly)

print("\nscans minutes apart")
table_[3] = { history = {} }
for i = 0, 11 do table_[3].history[#table_[3].history + 1] = { t = i * 60, q = 50 } end
check("eleven minutes of readings has no answer", Prices:GetSalesPerDay(3), nil)

table_[4] = { history = {} }
for t = 0, 3 * 3600, 60 do table_[4].history[#table_[4].history + 1] = { t = t, q = 50 } end
check("an unchanged book scanned every minute is nothing sold", Prices:GetSalesPerDay(4), 0)

print("\nan empty answer")
table_[5] = { history = { { t = 0, q = 40 }, { t = 7200, q = 0 }, { t = 14400, q = 40 } } }
check("is not counted as a sell-out", Prices:GetSalesPerDay(5), 0)

check("no record has no answer", Prices:GetSalesPerDay(99), nil)

print("")
if failures > 0 then error(string.format("%d sales-per-day check(s) failed", failures)) end
print("  all sales-per-day checks passed")
print("")
