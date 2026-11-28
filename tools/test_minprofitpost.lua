-- Post at Minimum Profit (the owner, 2026-11-16): when others sell a craft
-- for less than it can earn, it lists at the least that still makes the
-- Minimum Profit. Off unless ticked; Prices tab prices still come first.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.Util = { Clamp = function(v,l,h) return math.max(l, math.min(h,v)) end,
            Count = function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end,
            FormatMoney = function(c) return tostring(c) .. "c" end,
            FormatAge = function() return "" end,
            HasFunction = function() return false end,
            GetItemLabel = function(i) return "item"..tostring(i) end,
            ItemAuctionPrice = function(p) return math.max(100, math.floor(p)) end,
            ItemAuctionPriceUp = function(p) return math.max(100, math.ceil(p)) end }
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local settings = { undercutCopper = 0, minProfit = 1000, postAtMinProfit = false,
    auctionCut = 0.05, ignoreDeposit = true }
ns.Config = { Get = function(_, k) return settings[k] end, GetPriceTable = function() return {} end }
time = time or os.time

local rival, commodity, mine = 11000, false, nil
ns.Prices = {
    GetValue = function(_, _, which) if which == "rival" then return rival end return rival end,
    GetMine = function() if mine then return mine, "floor" end end,
}
ns.Scanner = { GetCommodityStatus = function() return commodity end }
local known = true
ns.Cost = {
    FindAnyRecipeForItem = function() return known and 1 or nil end,
    GetCraftCost = function() return { priceable = true, total = 12000, yield = 1 } end,
}
ns.Recipes = { GetAny = function() return { outputItemID = 5 } end }

assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
local Profit = ns.Profit

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got),
        ok and "ok" or ("EXPECTED " .. tostring(expected))))
end

-- Costs 12000, Minimum Profit 1000, 5% cut: (12000 + 1000) / 0.95 = 13684.2
local price, basis = Profit:ChoosePostPrice(5)
check("off: matches the cheaper rival", price, 11000)
check("off: basis is match", basis, "match")

settings.postAtMinProfit = true
local why
price, basis, why = Profit:ChoosePostPrice(5, nil, nil, true)
check("on: lists at the least that makes Minimum Profit", price, 13685)
check("on: basis is minprofit", basis, "minprofit")
check("on: says why", why ~= nil and why:find("1000c", 1, true) ~= nil, true)

settings.minProfit = 0
price, basis, why = Profit:ChoosePostPrice(5, nil, nil, true)
check("Minimum Profit 0: lists where you break even", price, 12632)
check("break even says so", why, "others sell for less, so it lists where you break even")
settings.minProfit = 1000

rival = 20000
price, basis = Profit:ChoosePostPrice(5, nil, nil, true)
check("a rival above that is matched as before", price, 20000)
rival = 11000

commodity = true
price = Profit:ChoosePostPrice(5, nil, nil, true)
check("a commodity lists at the same least price", price, 13685)
commodity = false

known = false
price, basis = Profit:ChoosePostPrice(5, nil, nil, true)
check("cost unknown: stays as before", basis, "match")
known = true

mine = 15000
price, basis = Profit:ChoosePostPrice(5, nil, nil, true)
check("a higher Prices tab floor still wins", price, 15000)
check("its basis stays floor", basis, "floor")
mine = nil

settings.undercutCopper = 50
price, basis = Profit:ChoosePostPrice(5, nil, nil, true)
check("undercutting below it lists at the least too", price, 13685)
settings.undercutCopper = 0

-- The owner (2026-11-17): it only lists what is in the bags at the
-- minimum. Every other ask (Profit tab, Queue, Level Up, craft lists) keeps
-- the market's price, so turning it on never makes every craft look worth it.
price, basis = Profit:ChoosePostPrice(5)
check("on, not for sale: the craft keeps the rival's price", price, 11000)
check("on, not for sale: basis stays match", basis, "match")
price, basis = Profit:ChooseMarketPostPrice(5)
check("on, market price: no floor either", basis, "match")

-- Light Leather, 2026-11-20: skinned leather is also a Leatherworking
-- craft (three Ruined Leather Scraps), so with a Minimum Profit of 20s it
-- listed at 21s 44c while the auction house sold it at 34c. Trade goods
-- (leather, cloth, bars, herbs) are materials and list at the market.
settings.postAtMinProfit = true
local itemClass = 7
C_Item = { GetItemInfoInstant = function(id) return id, "Trade Goods", "Leather", "", 1, itemClass, 6 end }
price, basis = Profit:ChoosePostPrice(5, nil, nil, true)
check("a trade good keeps the rival's price", price, 11000)
check("a trade good's basis stays match", basis, "match")
itemClass = 4
price, basis = Profit:ChoosePostPrice(5, nil, nil, true)
check("armor still lists at the least", price, 13685)
check("armor's basis is minprofit", basis, "minprofit")
C_Item = nil

if failures > 0 then
    error(string.format("%d minimum profit post check(s) failed", failures), 0)
end
print("PASS -- crafts list at the least that still makes Minimum Profit")
