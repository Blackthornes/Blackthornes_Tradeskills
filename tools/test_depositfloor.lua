-- The auction house's least deposit (a player's report, 2026-10-16).
--
-- A listing pays at least a set deposit, 1s for one Linen Belt and for
-- twenty alike, so a small listing's share each runs high. The remembered
-- share used to come from whatever was listed last: list one, and every
-- later guess said 1s a belt. Now the biggest listing gives the share and
-- the smallest says where the floor is.

local GLOBALS = { "time", "GetTime", "C_Timer", "Enum" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Util = { HasFunction = function() return false end, FormatMoney = tostring }

local settings = { postDuration = 2 }
ns.Config = { Get = function(_, key) return settings[key] end }
ns.db = {}
ns.Scanner = { isAuctionHouseOpen = false }

local clock = 1000
time = function() return clock end
GetTime = function() return clock end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end }
Enum = Enum or { ItemCommodityStatus = { Commodity = 2 }, BagIndex = {} }

assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)
local Posting = ns.Posting

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(("  %-50s %-10s %s"):format(label, tostring(got), ok and "ok" or ("WRONG, wanted " .. tostring(want))))
end

local BELT, CLOTH = 5000, 2589

print("a floor of 1s")
Posting:CacheUnitDeposit(BELT, 100, 20, 2)
Posting:CacheUnitDeposit(BELT, 100, 1, 2)
check("one belt listed last keeps the share of twenty", Posting:GetCachedUnitDeposit(BELT), 5)
check("one belt still pays the 1s", Posting:EstimateDeposit(BELT, 1), 100)
check("ten belts pay the 1s too", Posting:EstimateDeposit(BELT, 10), 100)
check("forty pay their share", Posting:EstimateDeposit(BELT, 40), 200)
check("away from the auction house, the same", Posting:GetDeposit(BELT, 1), 100)

print("")
print("no floor seen")
Posting:CacheUnitDeposit(CLOTH, 6, 2, 2)
Posting:CacheUnitDeposit(CLOTH, 60, 20, 2)
check("the share each", Posting:GetCachedUnitDeposit(CLOTH), 3)
check("one pays its share alone", Posting:EstimateDeposit(CLOTH, 1), 3)

print("")
print("an older record")
ns.db.deposits[42] = { unit = 2.4, duration = 2, at = 1 }
check("still read", Posting:EstimateDeposit(42, 5), 12)
Posting:CacheUnitDeposit(42, 30, 10, 2)
check("and replaced by a new answer", Posting:EstimateDeposit(42, 10), 30)

print("")
print("another listing length starts over")
settings.postDuration = 8
check("no guess for 8 hours yet", Posting:EstimateDeposit(BELT, 1), nil)
Posting:CacheUnitDeposit(BELT, 300, 1, 8)
check("one at 8 hours", Posting:EstimateDeposit(BELT, 1), 300)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "deposit floor checks failed")
