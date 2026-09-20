-- Commodity status: remembered, learned from searches, and what an unknown
-- status does to a price estimate.
--
-- The client only answers GetItemCommodityStatus for something in your bags,
-- and the answer used to live for the session and only for held items. So
-- every craft not yet made was priced as an item auction, whole-silver step
-- included: a 45c commodity rival became a 1s "match" in the Profit tab,
-- more than double the revenue that could be had.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
local warnings = 0
ns.Print, ns.PrintRaw, ns.Debug = function() end, function() end, function() end
ns.Warn = function() warnings = warnings + 1 end

ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    Comma = tostring,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    FormatAgeAgo = function() return "" end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    GetMaxStackSize = function() return 20 end,
    UnitPriceFromStack = function(_, buyout, quantity) return math.floor(buyout / (quantity or 1)) end,
    HasFunction = function(path) return path == "C_AuctionHouse.GetItemCommodityStatus" end,
    RoundToSilver = function(p) if p < 100 then return 100 end return math.floor(p / 100) * 100 end,
}

local priceTable = {}
ns.Config = {
    Get = function(_, k) if k == "undercutCopper" then return 1 end return nil end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "TestRealm" end,
}
ns.db = {}
ns.AHQueue = { PRIORITY = { urgent = 10, normal = 50, scan = 90 } }
ns.Cost = { FindRecipeForItem = function() return nil end }
ns.Inventory = { GetCarriedBags = function() return { 0 } end }

time = time or os.time
GetTime = function() return 1 end
C_Timer = { NewTimer = function() return { Cancel = function() end } end, After = function() end }
Enum = { ItemCommodityStatus = { Commodity = 2 }, BagIndex = { ReagentBag = 5 } }
UnitName = function() return "Tester" end
GetRealmName = function() return "TestRealm" end

-- One bag with whatever `held` says is in it.
local held = {}
local slotWalks = 0
C_Container = {
    GetContainerNumSlots = function() slotWalks = slotWalks + 1 return #held end,
    GetContainerItemInfo = function(_, slot) return held[slot] and { itemID = held[slot] } or nil end,
}
ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsValid = function() return true end }
    end,
}
local clientSays = {}
local itemResults, commodityResults = {}, {}
C_AuctionHouse = {
    GetItemCommodityStatus = function(location)
        local itemID = held[location.slot]
        return clientSays[itemID]
    end,
    GetNumItemSearchResults = function() return #itemResults end,
    GetItemSearchResultInfo = function(_, i) return itemResults[i] end,
    GetNumCommoditySearchResults = function() return #commodityResults end,
    GetCommoditySearchResultInfo = function(_, i) return commodityResults[i] end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

local Scanner, Prices, Profit = ns.Scanner, ns.Prices, ns.Profit
Scanner.isAuctionHouseOpen = true

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\ncommodity status")

-- A potion that sells by the unit, cheapest rival 45c, none in the bags.
Prices:Record(118, 45, 45, 500, time(), 45, nil)

check("nothing held and nothing searched: status is unknown, not false",
    Scanner:GetCommodityStatus(118) == nil)

local price, basis, _, uncertain = Profit:ChoosePostPrice(118)
check("an unknown status is priced without the whole-silver step",
    price == 44 and basis == "undercut")
check("and says so", uncertain == true)

-- The bags are not walked again for the same item until they change.
slotWalks = 0
Scanner:GetCommodityStatus(118)
Scanner:GetCommodityStatus(118)
check("an item known not to be held is not looked for again", slotWalks == 0)
Scanner:ForgetNotHeld()
Scanner:GetCommodityStatus(118)
check("until the bags change", slotWalks == 1)

-- A search answers through the commodity event: learned without holding one.
commodityResults = { { unitPrice = 45, quantity = 100 } }
Scanner:COMMODITY_SEARCH_RESULTS_UPDATED(nil, 118)
check("a commodity search result teaches the status", Scanner:GetCommodityStatus(118) == true)
check("and it is kept in the database, not the session", ns.db.commodity[118] == true)

-- An item auction learned the same way, from the item event.
Prices:Record(2589, 45, 45, 10, time(), 45, nil)
itemResults = { { buyoutAmount = 45, quantity = 1 } }
Scanner:ITEM_SEARCH_RESULTS_UPDATED(nil, { itemID = 2589 })
check("an item search result teaches the opposite", Scanner:GetCommodityStatus(2589) == false)

price, basis, _, uncertain = Profit:ChoosePostPrice(2589)
check("a known item auction keeps the whole-silver step", price == 100 and basis == "match")
check("and is not uncertain", not uncertain)

-- Holding one asks the client, and the client's answer is remembered.
held = { 4306 }
clientSays[4306] = 2
check("a held item is asked about", Scanner:IsCommodity(4306) == true)
held = {}
check("and remembered once it leaves the bags", Scanner:GetCommodityStatus(4306) == true)

-- IsCommodity stays a plain yes/no for the posting path.
check("IsCommodity is false for unknown", Scanner:IsCommodity(9999) == false)

-- A client that refuses the call warns once, not once per item.
held = { 5498, 5499 }
C_AuctionHouse.GetItemCommodityStatus = function() error("bad argument #1") end
warnings = 0
Scanner:GetCommodityStatus(5498)
Scanner:GetCommodityStatus(5499)
check("a refused status call warns once", warnings == 1)

print(("\n%d check(s) passed\n"):format(checks))
