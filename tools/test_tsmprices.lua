-- TradeSkillMaster's prices as a last resort (asked 2026-10-12).
--
-- What must hold:
--   1. Without TSM loaded, nothing changes.
--   2. An item nobody has priced takes TSM's DBMarket (market) or
--      DBMinBuyout (min, lowest); "rival" never asks TSM.
--   3. Your own scan always wins over TSM's.
--   4. Unticked, TSM is never asked.
--   5. A TSM error, a non-number or a silly number counts as no price.
--   6. Answers are kept for a while, so a redraw does not ask TSM again.

local GLOBALS = { "TSM_API", "GetTime" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

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
local priceTable = {}
local settings = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetPriceTable = function() return priceTable end,
}
ns.db = {}
time = time or os.time

local clock = 100
GetTime = function() return clock end
TSM_API = nil

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/TSMPrices.lua"))("Blackthornes_TS", ns)
local Prices, TSM = ns.Prices, ns.TSMPrices

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nTSM prices")

check("without TSM an unpriced item has no price", Prices:GetValue(2589) == nil)

local asked = {}
local answers = { DBMarket = 1234.4, DBMinBuyout = 999 }
TSM_API = {
    GetCustomPriceValue = function(source, item)
        asked[#asked + 1] = source .. " " .. item
        return answers[source]
    end,
}

check("an unpriced item takes TSM's market value", Prices:GetValue(2589) == 1234)
check("asked by TSM's item string", asked[1] == "DBMarket i:2589")
check("min reads DBMinBuyout", Prices:GetValue(2589, "min") == 999)
check("lowest reads DBMinBuyout", Prices:GetValue(2589, "lowest") == 999)
check("rival never asks TSM", Prices:GetValue(2589, "rival") == nil)

local before = #asked
Prices:GetValue(2589)
check("a second look within the minute is kept", #asked == before)
clock = clock + 61
Prices:GetValue(2589)
check("and asked again after", #asked == before + 1)

priceTable[2589] = { market = 500, scans = 1, history = {}, seen = time() }
check("your own scan wins", Prices:GetValue(2589) == 500)
check("the scans alone never include TSM", Prices:GetScanValue(2590) == nil)

settings.tsmPrices = false
TSM:Forget()
before = #asked
check("unticked, TSM gives nothing", Prices:GetValue(2590) == nil and #asked == before)
settings.tsmPrices = nil

TSM:Forget()
TSM_API.GetCustomPriceValue = function() error("boom") end
check("a TSM error is no price", Prices:GetValue(2591) == nil)
TSM:Forget()
TSM_API.GetCustomPriceValue = function() return "12" end
check("a string is no price", Prices:GetValue(2592) == nil)
TSM:Forget()
TSM_API.GetCustomPriceValue = function() return -5 end
check("a negative number is no price", Prices:GetValue(2593) == nil)
TSM:Forget()
TSM_API.GetCustomPriceValue = function() return 0/0 end
check("NaN is no price", Prices:GetValue(2594) == nil)
TSM_API = { GetCustomPriceValue = "nope" }
check("an API without the call counts as not loaded", not TSM:Loaded())

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
print(("\n%d check(s) passed\n"):format(checks))
