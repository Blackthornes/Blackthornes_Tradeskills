-- Regression test for the vendor purchase loop.
--
-- The bug: BuyStep decided how much to buy from live bag counts, then fired
-- again 0.2s later. Bag updates are asynchronous, so the second pass could
-- still see the pre-purchase count and buy the same item twice. Needing 1
-- Coarse Thread bought 2.
--
-- The test simulates the worst case: bag counts that never update at all.

local ns = {}

ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end

ns.Util = {
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    HasFunction = function(path) return path == "BuyMerchantItem" end,
}

ns.NewModule = function(name)
    local m = {}
    ns[name] = m
    return m
end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end

-- Purchases recorded here.
local purchases = {}
_G = _G or {}
BuyMerchantItem = function(index, amount)
    purchases[#purchases + 1] = { index = index, amount = amount }
end

GetMoney = function() return 100000 end
time = os.time

-- Run timers immediately: this is the harshest possible schedule, giving bag
-- counts no chance at all to catch up.
C_Timer = {
    After = function(_, fn) fn() end,
}

-- The shortfall NEVER decreases, as if BAG_UPDATE never arrived.
local STALE_SHORTFALL = 1

ns.Queue = {
    GetShoppingList = function()
        return { { itemID = 2320, shortfall = STALE_SHORTFALL } }
    end,
    Count = function() return 1 end,
}

ns.Inventory = { GetOwnedCount = function() return 1 end }
ns.Cost = { InvalidateIndex = function() end }
ns.Recipes = {}

local chunk = assert(loadfile(lfs_cwd .. "/Data/Vendor.lua"))
chunk("Blackthornes_TS", ns)

local Vendor = ns.Vendor

-- One Coarse Thread short, vendor sells it singly.
Vendor.isMerchantOpen = true
Vendor.merchantItems = {
    [2320] = { index = 3, price = 10, stack = 1, numAvailable = -1, extendedCost = false },
}

Vendor:BuyNeeded()

local total = 0
for _, purchase in ipairs(purchases) do
    total = total + purchase.amount
end

print("")
print(("purchase calls : %d"):format(#purchases))
print(("units bought   : %d"):format(total))
print(("expected       : 1"))

if total == 1 then
    print("PASS -- bought exactly what was short, despite stale bag counts")
else
    print("FAIL -- over-bought; the purchase tally is not holding")
end
print("")
