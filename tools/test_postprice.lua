-- What the post price does after a price check, and in particular after one
-- that came back empty.
--
-- The case worth guarding: a rival sells out between the last scan and the
-- click. If the empty search leaves the old rival price in place, the listing
-- undercuts somebody who is no longer there -- silently, and at whatever the
-- rival's last price happened to be.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.Util = { Clamp = function(v,l,h) return math.max(l, math.min(h,v)) end,
            Count = function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end,
            FormatMoney = function(c) return tostring(c) end,
            FormatAge = function() return "" end,
            HasFunction = function() return false end,
            GetItemLabel = function(i) return "item"..tostring(i) end }
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local priceTable = {}
ns.Config = {
    Get = function(_, k)
        if k == "undercutCopper" then return 1 end
        if k == "staleAfterSeconds" then return 48 * 3600 end
        return nil
    end,
    GetPriceTable = function() return priceTable end,
}

-- WoW's own global; outside the client it is the standard library's.
time = time or os.time

-- Commodities throughout, so the prices here are the plain undercut ones and
-- the whole-silver step item auctions impose stays out of this test's way.
-- tools/test_silverstep.lua is where that rule is checked.
ns.Scanner = { IsCommodity = function() return true end }
ns.Cost = { FindRecipeForItem = function() return nil end }

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Prices, Posting = ns.Prices, ns.Posting

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end

    print(string.format("  %-46s %-8s %s", label, tostring(got),
        ok and "ok" or ("EXPECTED " .. tostring(expected))))
end

print("")

-- A rival at 100 is the price to beat.
Prices:Record(555, 120, 100, 10, time(), 100, nil)

local price, basis = Posting:GetPostPrice(555)
check("rival listed: undercuts it", price, 99)
check("rival listed: basis", basis, "undercut")

-- That rival sells out. The search now comes back with nothing.
Prices:RecordEmpty(555)

price, basis = Posting:GetPostPrice(555)
check("book empty: no ghost undercut", price ~= 99, true)
check("book empty: prices at market", price, 120)
check("book empty: basis", basis, "market")
check("book empty: rival cleared", Prices:GetValue(555, "rival"), nil)
check("book empty: market value survives", Prices:GetValue(555, "market"), 120)
check("book empty: depth is zero, not unknown", Prices:Get(555).quantity, 0)
check("book empty: counts as a look", Prices:GetAge(555) ~= nil, true)

-- An item nobody has ever listed must not acquire a price from an empty scan.
Prices:RecordEmpty(999)

price, basis = Posting:GetPostPrice(999)
check("never listed, empty scan: no price", price, nil)
check("never listed, empty scan: no basis", basis, nil)

print("")
if failures > 0 then
    error(string.format("%d post-price check(s) failed", failures), 0)
end
print("PASS -- an empty auction house clears the rival instead of undercutting it")
print("")
