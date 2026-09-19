-- The floor under a listing: what it cost to make, or what a vendor pays.
--
-- The bug this guards against: material cost only exists for things made from a
-- recipe the account knows. Gathered mats, drops and vendor trash have none, so
-- the old test -- `price < unitCost` -- could never be true for them, and the
-- sell list happily offered to auction a stack of Linen Cloth for less than the
-- vendor in the same building would have paid for it, with nothing marked red.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

-- What the client has cached. nil sellPrice stands for an item the client has
-- not loaded yet, which must not be read as "worthless".
local itemSellPrice = {}

C_Item = {
    GetItemInfo = function(itemID)
        local sell = itemSellPrice[itemID]
        -- name, link, quality, iLevel, reqLevel, class, subclass, maxStack,
        -- equipSlot, texture, sellPrice
        return "item" .. tostring(itemID), nil, 1, 1, 1, nil, nil, 20, nil, nil, sell
    end,
}

ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    HasFunction = function(path) return path == "C_Item.GetItemInfo" end,
}

-- Core/Util.lua builds a worker frame at load time. Nothing here drives it;
-- it only has to exist so the file loads outside the client.
CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

GetTime = function() return os.clock() end

ns.Config = {
    Get = function(_, k)
        if k == "undercutCopper" then return 1 end
        if k == "staleAfterSeconds" then return 48 * 3600 end
        return nil
    end,
    GetPriceTable = function() return {} end,
}

time = time or os.time

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Util, Posting = ns.Util, ns.Posting

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

print("")
print("reading what a vendor pays")

itemSellPrice = { [2589] = 10, [4306] = 0, [1] = nil }

check("a cached item reports its sell price", Util.GetVendorSellPrice(2589), 10)
check("zero is not a price", Util.GetVendorSellPrice(4306), nil)
check("an uncached item reports nothing", Util.GetVendorSellPrice(1), nil)
check("no item, no price", Util.GetVendorSellPrice(nil), nil)

print("")
print("the floor under a listing")

itemSellPrice = { [2589] = 10, [2447] = 3, [9999] = nil }

do
    -- Linen Cloth: nothing crafts it, so before this change it had no floor at
    -- all and could be listed for a single copper without complaint.
    local floor, reason = Posting:GetLossFloor(2589, nil)
    check("an uncrafted item floors at vendor", floor, 10)
    check("and says why", reason, "vendor")
end

do
    -- Crafted and worth more than its materials: cost is the binding floor.
    local floor, reason = Posting:GetLossFloor(2447, 50)
    check("cost wins when it is the higher", floor, 50)
    check("and says why", reason, "cost")
end

do
    -- Crafted from cheap materials into something a vendor values more. Selling
    -- below vendor is a loss even though it is above cost.
    local floor, reason = Posting:GetLossFloor(2589, 4)
    check("vendor wins when it is the higher", floor, 10)
    check("and says why", reason, "vendor")
end

do
    -- Neither known: no floor, and no false accusation of a loss either.
    local floor, reason = Posting:GetLossFloor(9999, nil)
    check("nothing known means no floor", floor, nil)
    check("and no reason", reason, nil)
end

do
    local _, _, vendor = Posting:GetLossFloor(2589, 4)
    check("the vendor price comes back for display", vendor, 10)
end

print("")
print("what gets flagged")

itemSellPrice = { [2589] = 10 }

local function IsLoss(price, itemID, unitCost)
    local floor = Posting:GetLossFloor(itemID, unitCost)
    return price ~= nil and floor ~= nil and price < floor
end

check("listing under vendor is a loss",            IsLoss(6, 2589, nil), true)
check("listing over vendor is not",                IsLoss(14, 2589, nil), false)
check("listing exactly at vendor is not a loss",   IsLoss(10, 2589, nil), false)
check("an unpriced item is not a loss",            IsLoss(nil, 2589, nil), false)
check("an unknown item is never flagged",          IsLoss(1, 9999, nil), false)

print("")

if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- a listing is measured against the better of cost and vendor price")
print("")
